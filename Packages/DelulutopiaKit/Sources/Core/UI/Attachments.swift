import DLData
import DLDesignSystem
import DLI18n
import DLNetwork
import ImageIO
import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The attachment strip's state (FS-W6–W10; web media/useAttachments.ts): server attachments plus
/// uploads in flight, two at a time, in the order they were added. Refusals become lines under the
/// strip with the spec's text, never a silent failure (O4). Photos are shrunk to 2048 px JPEG on
/// the phone first (web media/prepare.ts).
@MainActor
@Observable
public final class Attachments {
    public struct Pending: Sendable, Equatable {
        public var kind: API.UploadKind
        public var progress: Double = 0
        public var processing = false
        public var durationMs: Int?
    }

    /// One strip entry: a saved attachment, or one still uploading; `local` previews it meanwhile.
    public struct Item: Identifiable, Equatable {
        public let key: String
        public var att: Att?
        public var pending: Pending?
        public var local: UIImage?
        public var id: String { key }
        public var kind: String { att?.kind ?? pending?.kind.rawValue ?? "" }
    }

    public struct Problem: Identifiable, Equatable {
        public let id: String
        public let text: String
    }

    public static var uploadFailed: String { t("media.uploadFailed") }
    static var readFailed: String { t("media.readFailedDevice", ["device": UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"]) }

    public private(set) var items: [Item]
    public private(set) var errors: [Problem] = []

    @ObservationIgnored private let path: String
    @ObservationIgnored private let api: API
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var running = 0
    @ObservationIgnored private var queue: [() -> Void] = []
    @ObservationIgnored private var seq = 0

    public init(_ initial: [Att], path: String, api: API) {
        self.items = initial.map { Item(key: $0.id, att: $0) }
        self.path = path
        self.api = api
    }

    public var uploading: Bool { items.contains { $0.pending != nil } }
    public var done: [Att] { items.compactMap(\.att) }
    public func has(_ kind: String) -> Bool { items.contains { $0.kind == kind } }
    public func count(_ kind: String) -> Int { items.filter { $0.kind == kind }.count }

    /// Adds an upload. `data` is read lazily (off the main actor) so a large pick never blocks.
    public func add(_ kind: API.UploadKind, name: String, mime: String, durationMs: Int? = nil, preview: UIImage? = nil,
                    data: @escaping @Sendable () async throws -> Data) {
        seq += 1
        let key = "up-\(seq)"
        items.append(Item(key: key, pending: Pending(kind: kind, durationMs: durationMs), local: preview))
        let api = api
        let path = path
        let start = { [self] in
            running += 1
            tasks[key] = Task {
                do {
                    let raw = try await data()
                    let (bytes, file, type) = await Self.prepare(kind, raw, name: name, mime: mime)
                    if let tooLarge = kind.precheck(bytes.count) { throw APIError(status: 413, code: "TOO_LARGE", message: tooLarge) }
                    let progress: @Sendable (Double) -> Void = { [weak self] f in
                        Task { @MainActor [weak self] in self?.patch(key) { $0.progress = f; $0.processing = f >= 0.99 } }
                    }
                    let att = try await api.upload(to: path, kind: kind, data: bytes, filename: file, mime: type, progress: progress)
                    landed(key, att)
                } catch is CancellationError {
                } catch let e as APIError {
                    fail(key, e.isOffline ? Self.uploadFailed : e.message)
                } catch is ReadError {
                    fail(key, Self.readFailed)
                } catch {
                    fail(key, Self.uploadFailed)
                }
                finished(key)
            }
        }
        if running < 2 { start() } else { queue.append(start) }
    }

    public struct ReadError: Error {
        public init() {}
    }

    private func finished(_ key: String) {
        tasks[key] = nil
        running = max(0, running - 1)
        if !queue.isEmpty, running < 2 { queue.removeFirst()() }
    }

    private func landed(_ key: String, _ att: Att) {
        items = items.map { $0.key == key ? Item(key: key, att: att, local: $0.local) : $0 }
    }

    private func patch(_ key: String, _ change: (inout Pending) -> Void) {
        items = items.map { item in
            guard item.key == key, var p = item.pending else { return item }
            change(&p)
            var copy = item
            copy.pending = p
            return copy
        }
    }

    private func fail(_ key: String, _ text: String) {
        items.removeAll { $0.key == key }
        errors.append(Problem(id: key, text: text))
    }

    /// Drop from the strip; an upload still in flight is cancelled. The caller deletes on the server.
    public func remove(_ key: String) {
        tasks[key]?.cancel()
        items.removeAll { $0.key == key }
    }

    public func restore(_ item: Item, at index: Int) {
        items.insert(item, at: min(index, items.count))
    }

    /// Replace everything (Load in the conflict dialog).
    public func reset(_ atts: [Att]) {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        queue.removeAll()
        running = 0
        items = atts.map { Item(key: $0.id, att: $0) }
    }

    public func dismissError(_ id: String) {
        errors.removeAll { $0.id == id }
    }

    /// A photo shrunk to 2048 px on its long edge, upright, as JPEG (only when that is smaller).
    nonisolated static func prepare(_ kind: API.UploadKind, _ data: Data, name: String, mime: String) async -> (Data, String, String) {
        guard kind == .photo, data.count <= 40 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return (data, name, mime) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return (data, name, mime) }
        let image = UIImage(cgImage: cg)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let flat = UIGraphicsImageRenderer(size: image.size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: image.size))
            image.draw(at: .zero)
        }
        guard let jpeg = flat.jpegData(compressionQuality: 0.9), jpeg.count < data.count else { return (data, name, mime) }
        let base = (name as NSString).deletingPathExtension
        return (jpeg, base + ".jpg", "image/jpeg")
    }
}

/// The attachment strip under the writing (canvas W-Draft): photo tiles with their upload ring, the
/// voice note and doodle chips, each with ✕; refusals as lines under it.
public struct AttachmentStrip: View {
    let attachments: Attachments
    let onRemove: (Attachments.Item) -> Void
    let onOpen: (Attachments.Item) -> Void

    public init(_ attachments: Attachments, onRemove: @escaping (Attachments.Item) -> Void, onOpen: @escaping (Attachments.Item) -> Void = { _ in }) {
        self.attachments = attachments
        self.onRemove = onRemove
        self.onOpen = onOpen
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(attachments.items) { item in
                            tile(item).transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 2)
                }
            }
            ForEach(attachments.errors) { problem in
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.dlError)
                    Text(problem.text).dlText(.footnote).foregroundStyle(.dlError)
                    Spacer(minLength: 0)
                    Button { attachments.dismissError(problem.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.dlInkQuiet).frame(width: 44, height: 32)
                    }
                    .accessibilityLabel(t("media.dismiss"))
                }
            }
        }
        .animation(DLMotion.easeOut(0.2), value: attachments.items)
    }

    @ViewBuilder
    private func tile(_ item: Attachments.Item) -> some View {
        let label = item.kind == "audio" ? t("emails.media.voiceNote") : item.kind == "doodle" ? t("media.doodle") : item.kind == "video" ? t("media.video") : t("emails.media.photo")
        ZStack(alignment: .topTrailing) {
            Button { if item.att != nil { onOpen(item) } } label: {
                Group {
                    if item.kind == "audio" {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform")
                            Text(DLTime.mediaLength(ms: item.att?.durationMs ?? item.pending?.durationMs))
                                .monospacedDigit()
                        }
                        .font(.custom(DLFontName.manropeBold.name, size: 13, relativeTo: .footnote))
                        .foregroundStyle(.dlInk)
                        .padding(.horizontal, 12)
                        .frame(height: 64)
                        .background(.dlCell, in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        ZStack {
                            if let local = item.local {
                                Image(uiImage: local).resizable().scaledToFill()
                            } else if let att = item.att {
                                RemoteImage(att.thumbUrl ?? att.url, contentMode: .fill, maxPixel: 256) { Color.dlLetterEnvelope }
                            } else {
                                Color.dlLetterEnvelope
                            }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            if item.kind == "video" {
                                Image(systemName: "play.fill").foregroundStyle(.white).shadow(radius: 2)
                            }
                        }
                    }
                }
                .overlay {
                    if let p = item.pending {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.35))
                            if p.processing {
                                ProgressView().tint(.white)
                            } else {
                                Circle().stroke(.white.opacity(0.35), lineWidth: 3).frame(width: 26, height: 26)
                                Circle().trim(from: 0, to: p.progress).stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .rotationEffect(.degrees(-90)).frame(width: 26, height: 26)
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.pending != nil ? t("media.labelUploading", ["label": label]) : label)
            Button { onRemove(item) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.dlInk.opacity(0.8), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .offset(x: 14, y: -14)
            .accessibilityLabel(t(item.kind == "audio" ? "media.removeVoiceNote" : item.kind == "doodle" ? "media.removeDoodle" : item.kind == "video" ? "media.removeVideo" : "media.removeThePhoto"))
        }
    }
}
