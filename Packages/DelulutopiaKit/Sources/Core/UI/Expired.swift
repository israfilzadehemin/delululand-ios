import DLDesignSystem
import DLI18n
import SwiftUI

// Doc "Delululand — Attachment Retention" (canvas of the same name): what stands in for a file the
// retention job removed (AR6), the line under a media block that lost files (AR15), and the compose
// notice under every attachment strip (AR13, AR14).

/// AR6: the words a placeholder says, by kind.
public func expiredLabel(_ kind: String) -> String {
    switch kind {
    case "video": t("media.videoExpired")
    case "doodle": t("media.doodleExpired")
    default: t("media.photoExpired")
    }
}

/// The kind's symbol with a slash drawn across it (the canvas's crossed-out icons).
public struct ExpiredIcon: View {
    let kind: String
    let size: CGFloat

    public init(_ kind: String, size: CGFloat = 20) {
        self.kind = kind
        self.size = size
    }

    private var symbol: String {
        switch kind {
        case "video": "video"
        case "audio": "mic"
        case "doodle": "scribble"
        default: "photo"
        }
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.75, weight: .regular))
            .frame(width: size, height: size)
            .overlay {
                Path { p in
                    p.move(to: CGPoint(x: size * 0.15, y: size * 0.15))
                    p.addLine(to: CGPoint(x: size * 0.85, y: size * 0.85))
                }
                .stroke(style: StrokeStyle(lineWidth: max(1.4, size * 0.07), lineCap: .round))
            }
            .foregroundStyle(.dlInkQuiet)
            .accessibilityHidden(true)
    }
}

private struct ExpiredFrame: ViewModifier {
    let radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(scheme == .dark ? Color.black.opacity(0.22) : Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.dlInkQuiet.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

/// A thumbnail slot (64 pt prints, 36 pt quote thumbs): the crossed-out icon alone (AR6, AR9).
public struct ExpiredThumb: View {
    let kind: String
    let size: CGFloat

    public init(kind: String = "photo", size: CGFloat = 64) {
        self.kind = kind
        self.size = size
    }

    public var body: some View {
        ExpiredIcon(kind, size: size < 48 ? 16 : 18)
            .frame(width: size, height: size)
            .modifier(ExpiredFrame(radius: size < 48 ? 6 : 8))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(expiredLabel(kind))
            .accessibilityAddTraits(.isImage)
    }
}

/// A larger slot (the doodle, a video): icon and words (AR6).
public struct ExpiredBlock: View {
    let kind: String
    let minHeight: CGFloat

    public init(kind: String, minHeight: CGFloat = 96) {
        self.kind = kind
        self.minHeight = minHeight
    }

    public var body: some View {
        VStack(spacing: 4) {
            ExpiredIcon(kind)
            Text(expiredLabel(kind))
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(.dlInkQuiet)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .modifier(ExpiredFrame(radius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(expiredLabel(kind))
        .accessibilityAddTraits(.isImage)
    }
}

/// A voice note keeps its row and its length (AR6).
public struct ExpiredVoice: View {
    let durationMs: Int?

    public init(durationMs: Int?) {
        self.durationMs = durationMs
    }

    private var text: String {
        let s = max(0, (durationMs ?? 0) / 1000)
        return t("media.voiceExpired", ["time": "\(s / 60):\(String(format: "%02d", s % 60))"])
    }

    public var body: some View {
        HStack(spacing: 8) {
            ExpiredIcon("audio", size: 16)
                .frame(width: 32, height: 32)
                .modifier(ExpiredFrame(radius: 16))
            Text(text)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(.dlInkQuiet)
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isImage)
    }
}

/// AR13, AR14: "Attachments are kept for N days" under the strip, above the tier line. Nil days (an
/// older API): nothing.
public struct RetentionNotice: View {
    let days: Int?

    public init(days: Int?) {
        self.days = days
    }

    public var body: some View {
        if let days {
            HStack(spacing: 6) {
                Image(systemName: "hourglass").font(.system(size: 12, weight: .semibold))
                Text(tn("retention.kept", days)).dlText(.footnoteStrong)
            }
            .foregroundStyle(.dlInkQuiet)
        }
    }
}

/// AR15: under a media block that holds expired files.
public struct RetentionCaption: View {
    let days: Int?

    public init(days: Int?) {
        self.days = days
    }

    public var body: some View {
        if let days {
            HStack(spacing: 6) {
                Image(systemName: "hourglass").font(.system(size: 11, weight: .regular))
                Text(tn("retention.removed", days)).dlText(.footnote)
            }
            .foregroundStyle(.dlInkQuiet)
        }
    }
}
