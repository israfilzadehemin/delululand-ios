import DLData
import DLDesignSystem
import DLI18n
import DLNetwork
import DLUI
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Vision

/// Adding one of Ours (doc "Delululand — Stickers" SK8, SK13, FS-SK18–SK24; web stickers/AddSticker.tsx):
/// Draw on a clear square, cut the subject out of a photo on the phone, or import an image; then a
/// preview with keywords, the white outline and the count after adding.
struct AddSticker: View {
    let store: StickerStore
    let onClose: () -> Void

    private enum Step: Equatable {
        case menu
        case preview(Data, String, Bool)
    }

    @State private var step: Step = .menu
    @State private var detent: PresentationDetent = .medium
    @State private var error: String?
    @State private var working = false
    /// The pickers hang off this view, not off menu rows, so nothing they were opened from goes away
    /// while they close (a PhotosPicker in a row took the whole sheet down with it on iOS).
    @State private var choosingPhoto = false
    @State private var choosingFile = false
    @State private var photoPick: PhotosPickerItem?
    @State private var filePick: PhotosPickerItem?
    /// FS-SK20: a photo with no subject found, kept for "Use whole photo".
    @State private var noSubject: Data?
    @State private var drawing = false
    @Environment(Backend.self) private var backend

    var body: some View {
        Group {
            switch step {
            case .menu: menu
            case let .preview(data, mime, outlinable):
                StickerPreview(store: store, data: data, mime: mime, outlinable: outlinable, onBack: { show(.menu) }, onDone: onClose)
            }
        }
        .overlay {
            if working {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .interactiveDismissDisabled(working)
        .photosPicker(isPresented: $choosingPhoto, selection: $photoPick, matching: .images)
        .photosPicker(isPresented: $choosingFile, selection: $filePick, matching: .images, preferredItemEncoding: .current)
        .fullScreenCover(isPresented: $drawing) {
            DoodlePad(surface: .sticker, title: t("stickers.draw"), doneLabel: t("stickers.next")) { png in
                drawing = false
                show(.preview(png, "image/png", true))
            } onClose: {
                drawing = false
            }
            .environment(backend)
        }
        .alert(
            t("stickers.noSubject"),
            isPresented: Binding(get: { noSubject != nil }, set: { if !$0 { noSubject = nil } }),
            presenting: noSubject
        ) { raw in
            Button(t("stickers.useWholePhoto")) {
                noSubject = nil
                if let jpeg = wholePhoto(raw) { show(.preview(jpeg, "image/jpeg", false)) } else { error = t("common.somethingWentWrong") }
            }
            Button(t("stickers.cancel"), role: .cancel) {}
        }
        .onChange(of: photoPick) { _, item in
            guard let item else { return }
            photoPick = nil
            error = nil
            working = true
            Task {
                defer { working = false }
                guard let raw = try? await item.loadTransferable(type: Data.self) else {
                    error = t("common.somethingWentWrong")
                    return
                }
                if let png = await cutOut(raw) {
                    show(.preview(png, "image/png", true))
                } else {
                    noSubject = raw
                }
            }
        }
        .onChange(of: filePick) { _, item in
            guard let item else { return }
            filePick = nil
            error = nil
            working = true
            Task {
                defer { working = false }
                let mime = item.supportedContentTypes.compactMap(\.preferredMIMEType).first { stickerTypes.contains($0) }
                    ?? item.supportedContentTypes.first?.preferredMIMEType ?? ""
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    error = t("common.somethingWentWrong")
                    return
                }
                if let refusal = checkSticker(bytes: data.count, mime: mime) {
                    error = refusal
                } else {
                    show(.preview(data, mime, false))
                }
            }
        }
    }

    /// The preview wants the full height; the menu goes back to half.
    private func show(_ next: Step) {
        step = next
        detent = next == .menu ? .medium : .large
    }

    private var menu: some View {
        NavigationStack {
            List {
                Button { drawing = true } label: {
                    menuRow(t("stickers.draw"), t("stickers.drawHint"), symbol: "scribble")
                }
                Button { choosingPhoto = true } label: {
                    menuRow(t("stickers.fromPhoto"), nil, symbol: "person.crop.square")
                }
                Button { choosingFile = true } label: {
                    menuRow(t("stickers.import"), t("stickers.importHint"), symbol: "square.and.arrow.down")
                }
                if let error {
                    Text(error).dlText(.footnote).foregroundStyle(.dlError)
                }
                Section {
                } footer: {
                    Text(t("stickers.capHint")).frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle(t("stickers.newSticker"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t("stickers.cancel"), action: onClose) }
            }
        }
    }

}

/// SK13, FS-SK19, FS-SK24: the sticker on a checkerboard, keywords, the count after adding, Add.
private struct StickerPreview: View {
    let store: StickerStore
    let data: Data
    let mime: String
    let outlinable: Bool
    let onBack: () -> Void
    let onDone: () -> Void

    @State private var outline = true
    @State private var outlined: Data?
    @State private var keywords = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        let shown = outlinable && outline ? (outlined ?? data) : data
        let shownMime = outlinable && outline && outlined != nil ? "image/png" : mime
        let cat = store.catalogue
        let full = cat.map { $0.custom.used >= $0.custom.cap } ?? false
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Group {
                        if let image = UIImage(data: shown) {
                            Image(uiImage: image).resizable().scaledToFit().padding(10)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 220, height: 220)
                    .background { Checkerboard() }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel(t("stickers.previewAlt"))
                    if outlinable {
                        Toggle(t("stickers.whiteOutline"), isOn: $outline).tint(.dlSeal)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(t("stickers.keywords")).font(.system(size: 13, weight: .semibold))
                            Text(t("stickers.keywordsHint")).font(.system(size: 12)).foregroundStyle(.dlInkQuiet)
                        }
                        TextField("", text: Binding(get: { keywords }, set: { keywords = String($0.prefix(260)) }))
                            .textFieldStyle(.roundedBorder)
                            .disabled(busy)
                            .accessibilityLabel(t("stickers.keywords"))
                    }
                    Text(t("stickers.bothCanUse")).font(.system(size: 13)).foregroundStyle(.dlInkQuiet).multilineTextAlignment(.center)
                    if let cat {
                        Text(t("stickers.afterAdding", ["used": min(cat.custom.used + 1, cat.custom.cap), "cap": cat.custom.cap]))
                            .font(.system(size: 12.5).monospacedDigit()).foregroundStyle(.dlInkQuiet)
                    }
                    if let error { Text(error).dlText(.footnote).foregroundStyle(.dlError).multilineTextAlignment(.center) }
                    HStack(spacing: 8) {
                        Button(t("stickers.cancel"), action: onBack).buttonStyle(DLButtonStyle(.grey, fullWidth: true)).disabled(busy)
                        Button(busy ? t("stickers.adding") : t("stickers.add")) {
                            busy = true
                            error = nil
                            Task {
                                let refusal = await store.add(shown, mime: shownMime, keywords: keywords)
                                busy = false
                                if let refusal { error = refusal } else { onDone() }
                            }
                        }
                        .buttonStyle(DLButtonStyle(.filled, fullWidth: true))
                        .disabled(busy || full)
                    }
                }
                .padding(20)
            }
            .navigationTitle(t("stickers.newSticker"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(busy)
        .task(id: outline) {
            guard outlinable, outline, outlined == nil else { return }
            outlined = withOutline(data)
        }
    }
}

/// FS-SK19: the white die-cut edge, in pixels of a 1024 px drawing (web files.ts OUTLINE_PX).
let outlinePx: CGFloat = 16

/// FS-SK19: a white edge around the shape — the shape filled white and stamped at 16 points on a
/// circle, then the picture on top (web files.ts withOutline). The width scales with the picture.
func withOutline(_ png: Data) -> Data? {
    guard let src = UIImage(data: png), let cg = src.cgImage else { return nil }
    let size = CGSize(width: cg.width, height: cg.height)
    let px = max(2, max(size.width, size.height) * outlinePx / 1024)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    // The shape in white: the picture, then white kept only where it has ink.
    let white = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
        let rect = CGRect(origin: .zero, size: size)
        UIImage(cgImage: cg).draw(in: rect)
        ctx.cgContext.setBlendMode(.sourceIn)
        ctx.cgContext.setFillColor(UIColor.white.cgColor)
        ctx.cgContext.fill(rect)
    }
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
        for i in 0 ..< 16 {
            let a = Double(i) / 16 * 2 * .pi
            white.draw(at: CGPoint(x: cos(a) * px, y: sin(a) * px))
        }
        UIImage(cgImage: cg).draw(at: .zero)
    }.pngData()
}

/// FS-SK20: the subject of a photo cut out on the phone (Vision, every subject together), cropped to
/// what is left with room for the outline, at most 640 px. Nil when nothing stands out.
func cutOut(_ raw: Data) async -> Data? {
    await Task.detached(priority: .userInitiated) { () -> Data? in
        guard let photo = UIImage(data: raw), let cg = photo.normalized().cgImage else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg)
        guard (try? handler.perform([request])) != nil,
              let result = request.results?.first,
              let buffer = try? result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
        else { return nil }
        let ci = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        guard let cut = context.createCGImage(ci, from: ci.extent) else { return nil }
        let w = CGFloat(cut.width), h = CGFloat(cut.height)
        let margin = (max(w, h) * 2.5 * outlinePx / 1024).rounded() + 2
        let k = min(1, 640 / (max(w, h) + margin * 2))
        let size = CGSize(width: ((w + margin * 2) * k).rounded(), height: ((h + margin * 2) * k).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: cut).draw(in: CGRect(x: margin * k, y: margin * k, width: w * k, height: h * k))
        }.pngData()
    }.value
}

/// FS-SK20 fallback: the photo's centre square at 512 px, no cut-out (JPEG keeps it well under 1 MB).
func wholePhoto(_ raw: Data) -> Data? {
    guard let photo = UIImage(data: raw)?.normalized() else { return nil }
    let side = min(photo.size.width, photo.size.height)
    guard side > 0 else { return nil }
    let k = 512 / side
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format).image { _ in
        photo.draw(in: CGRect(x: (side - photo.size.width) / 2 * k, y: (side - photo.size.height) / 2 * k, width: photo.size.width * k, height: photo.size.height * k))
    }.jpegData(compressionQuality: 0.9)
}

private extension UIImage {
    /// The photo upright (Vision reads the pixels as stored).
    func normalized() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(at: .zero) }
    }
}

/// One way in, with its hint (FS-SK18).
private func menuRow(_ title: String, _ hint: String?, symbol: String) -> some View {
    HStack(spacing: 14) {
        Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(.dlSeal).frame(width: 28)
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.dlInk)
            if let hint { Text(hint).font(.system(size: 13)).foregroundStyle(.dlInkQuiet) }
        }
    }
    .padding(.vertical, 4)
}
