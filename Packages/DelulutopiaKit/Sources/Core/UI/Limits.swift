import DLData
import DLI18n
import DLNetwork
import Foundation

/// What a composer may still add and what it must say (doc "Delululand — Subscription Tiers"
/// CM-1–CM-8, ST6, ST8, ST13, ST16; web src/plan/limits.ts). `photos` counts every photo in the
/// message (the per-message limit); `newPhotos` those that spend today's allowance at send (an edit
/// spends only what it adds, ST6); `videos` those that spend at send.
public struct MessageMedia: Equatable, Sendable {
    public var photos: Int
    public var newPhotos: Int
    public var videos: Int

    public init(photos: Int, newPhotos: Int? = nil, videos: Int = 0) {
        self.photos = photos
        self.newPhotos = newPhotos ?? photos
        self.videos = videos
    }
}

public enum LimitLine: Equatable, Sendable {
    case perMessage(Int)
    case photosLeft(Int)
    case noPhotos
    case noMorePhotos
    case videosLeft(Int)
    case noVideos
}

public enum LimitBlock: Equatable, Sendable {
    case overMessage(n: Int, remove: Int)
    case photosOver(left: Int, remove: Int)
    case videosOver
}

public struct StripLimits: Equatable, Sendable {
    public var photoRoom: Int
    public var videoRoom: Bool
    public var photosPerMessage: Int
    public var lines: [LimitLine]
    public var block: LimitBlock?
    public var renewsAt: String

    private var time: String { DLTime.time(renewsAt) }

    /// CM-5: one footer line joined by " · ", per-message first, "renews at" once for the daily parts.
    public var line: String? {
        guard !lines.isEmpty else { return nil }
        var parts = lines.map { l -> String in
            switch l {
            case let .perMessage(n): t("limits.photosPerMessage", ["n": n])
            case let .photosLeft(n): tn("limits.photosLeft", n)
            case let .videosLeft(n): tn("limits.videosLeft", n)
            case .noPhotos: t("limits.noPhotos")
            case .noMorePhotos: t("limits.noMorePhotos")
            case .noVideos: t("limits.noVideos")
            }
        }
        if lines.contains(where: { if case .perMessage = $0 { false } else { true } }) {
            parts.append(t("limits.renews", ["time": time]))
        }
        return parts.joined(separator: " · ")
    }

    public var lineIsZero: Bool { lines.contains(.noPhotos) || lines.contains(.noVideos) }

    /// CM-7, CM-8: the banner above Send; Send stays off while it shows (ST13).
    public var blockText: String? {
        guard let block else { return nil }
        return switch block {
        case let .overMessage(n, remove): t("limits.overMessage", ["n": n, "remove": remove])
        case let .photosOver(left, remove):
            left == 0 ? t("limits.photosNone", ["time": time]) : tn("limits.photosOver", left, ["remove": remove, "time": time])
        case .videosOver: t("limits.videosNone", ["time": time])
        }
    }

    /// CM-2: "Added 3 of 5 · 5 photos per message".
    public func addedNotice(added: Int, picked: Int, inMessage: Int) -> String {
        let why = inMessage + added >= photosPerMessage ? t("limits.photosPerMessage", ["n": photosPerMessage]) : t("limits.noMorePhotos")
        return t("limits.added", ["added": added, "picked": picked]) + " · " + why
    }
}

public enum PlanLimitsRule {
    public static let low = 2
}

public func stripLimits(_ plan: Plan?, _ media: MessageMedia) -> StripLimits? {
    guard let plan else { return nil }
    let limits = plan.limits
    let left = plan.left
    let photosAfter = left.photos - media.newPhotos
    var lines: [LimitLine] = []
    if media.photos == limits.photosPerMessage { lines.append(.perMessage(limits.photosPerMessage)) }
    if left.photos == 0, media.newPhotos == 0 {
        lines.append(.noPhotos)
    } else if photosAfter == 0 {
        lines.append(.noMorePhotos)
    } else if photosAfter > 0, photosAfter <= PlanLimitsRule.low {
        lines.append(.photosLeft(photosAfter))
    }
    var block: LimitBlock?
    if media.photos > limits.photosPerMessage {
        block = .overMessage(n: limits.photosPerMessage, remove: media.photos - limits.photosPerMessage)
    } else if media.newPhotos > left.photos {
        block = .photosOver(left: left.photos, remove: media.newPhotos - left.photos)
    }
    if media.videos > left.videos {
        if block == nil { block = .videosOver }
    } else if media.videos == 0, left.videos == 0 {
        lines.append(.noVideos)
    } else if media.videos == 0, left.videos <= PlanLimitsRule.low {
        lines.append(.videosLeft(left.videos))
    }
    return StripLimits(
        photoRoom: max(0, min(limits.photosPerMessage - media.photos, photosAfter)),
        videoRoom: left.videos - media.videos > 0,
        photosPerMessage: limits.photosPerMessage,
        lines: lines,
        block: block,
        renewsAt: plan.renewsAt
    )
}

/// What a strip's items carry; `original` names attachments the message already had (an edit spends none of them).
@MainActor
public func mediaOf(_ items: [Attachments.Item], original: Set<String> = []) -> MessageMedia {
    var photos = 0
    var newPhotos = 0
    var videos = 0
    for item in items {
        switch item.kind {
        case "photo":
            photos += 1
            if let id = item.att?.id, original.contains(id) {} else { newPhotos += 1 }
        case "video":
            videos += 1
        default:
            break
        }
    }
    return MessageMedia(photos: photos, newPhotos: newPhotos, videos: videos)
}
