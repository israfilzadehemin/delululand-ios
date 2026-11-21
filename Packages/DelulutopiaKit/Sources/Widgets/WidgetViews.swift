import DLDesignSystem
import DLI18n
import SwiftUI
import UIKit
import WidgetKit

// The widget faces (iOS canvas Y-Widgets, Y-Widget-sizes; Selfies canvas W-iOS, W-States). Plain
// views of `WidgetData` at a date, so the screenshot target can draw every size and state (WG13).

/// Which size a face is drawn at; the widgets map `WidgetFamily` onto it.
public enum WidgetSize: String, CaseIterable, Sendable {
    case small, medium, large, rectangular

    public init(_ family: WidgetFamily) {
        switch family {
        case .systemMedium: self = .medium
        case .systemLarge, .systemExtraLarge: self = .large
        case .accessoryRectangular, .accessoryInline, .accessoryCircular: self = .rectangular
        default: self = .small
        }
    }
}

// MARK: - Board (WG12)

public struct BoardWidgetView: View {
    let data: WidgetData
    let date: Date
    let size: WidgetSize

    public init(data: WidgetData, date: Date, size: WidgetSize) {
        self.data = data
        self.date = date
        self.size = size
    }

    public var body: some View {
        if !data.signedIn {
            SignedOutFace(line: t("widget.signedOut"))
        } else {
            VStack(alignment: .leading, spacing: size == .large ? 10 : 6) {
                whiteboard
                caption
            }
            .widgetURL(WidgetLink.board)
        }
    }

    private var whiteboard: some View {
        ZStack(alignment: .topLeading) {
            Color.dlBoardSurface
            if let bytes = data.board?.image, let image = UIImage(data: bytes) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .privacySensitive()
            } else if data.board == nil {
                Text(t("board.theBoardIsEmpty"))
                    .dlText(.footnote)
                    .foregroundStyle(.dlInkQuiet)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if size == .large, data.board?.isNew == true {
                NewChip()
                    .padding(8)
            }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .padding(EdgeInsets(top: 5, leading: 5, bottom: size == .large ? 11 : 8, trailing: 5))
        .background(alignment: .bottom) {
            Capsule().fill(.dlBoardTray).frame(height: 4).padding(.horizontal, 16).padding(.bottom, 3)
        }
        .background(.dlBoardFrame, in: RoundedRectangle(cornerRadius: 6))
        .frame(maxWidth: .infinity)
    }

    private var caption: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(t("board.board"))
                    .font(.custom(DLFontName.manropeExtraBold.name, size: 13, relativeTo: .footnote))
                    .foregroundStyle(.dlInk)
                    .widgetAccentable()
                if let board = data.board {
                    Text(size == .large
                        ? WidgetTimeline.byline(board, friend: data.friendName, now: date)
                        : "\(board.mine ? t("board.you") : board.authorName) · \(WidgetTimeline.age(board.createdAt, now: date))")
                        .font(.custom(DLFontName.manropeMedium.name, size: 11, relativeTo: .caption2))
                        .foregroundStyle(.dlInkQuiet)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if size != .large, data.board?.isNew == true { NewChip() }
        }
    }
}

// MARK: - Selfies (DS12)

public struct SelfiesWidgetView: View {
    let data: WidgetData
    let date: Date
    let size: WidgetSize

    public init(data: WidgetData, date: Date, size: WidgetSize) {
        self.data = data
        self.date = date
        self.size = size
    }

    public var body: some View {
        let now = data.at(date)
        switch now.selfies {
        case .signedOut:
            SignedOutFace(line: t("widget.selfiesSignedOut"))
        case .none:
            empty
        default:
            if size == .medium {
                HStack(spacing: 14) {
                    frame(now.mine, mine: true, name: now.me?.name ?? "", tilt: -3)
                    frame(now.theirs, mine: false, name: now.friendName, tilt: 2.5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Cork())
                .widgetURL(WidgetLink.selfies)
            } else {
                // Small: the friend's when there is one (locked or not), else mine.
                let theirs = !now.theirs.isEmpty
                frame(theirs ? now.theirs : now.mine, mine: !theirs, name: theirs ? now.friendName : (now.me?.name ?? ""), tilt: theirs ? 2.5 : -3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Cork())
                    .widgetURL(now.mine.isEmpty ? WidgetLink.selfieCamera : WidgetLink.selfies)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Text(data.brand)
                .font(.custom(DLFontName.manropeExtraBold.name, size: 13, relativeTo: .footnote))
                .foregroundStyle(.dlInk)
                .widgetAccentable()
            Spacer(minLength: 0)
            Image(systemName: "camera")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.dlInkQuiet)
            Text(size == .medium ? t("widget.noSelfiesToday") : t("selfie.strip.none"))
                .dlText(.footnote)
                .foregroundStyle(.dlInkQuiet)
                .multilineTextAlignment(.center)
            Text(size == .medium ? t("widget.takeTodays") : t("widget.takeOne"))
                .font(.custom(DLFontName.manropeBold.name, size: 13, relativeTo: .footnote))
                .foregroundStyle(.dlSeal)
                .widgetAccentable()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(WidgetLink.selfieCamera)
    }

    @ViewBuilder
    private func frame(_ slot: SelfieSlot, mine: Bool, name: String, tilt: Double) -> some View {
        let side: CGFloat = size == .medium ? 92 : 96
        VStack(spacing: 3) {
            ZStack {
                switch slot {
                case let .photo(bytes, _, _):
                    if let image = UIImage(data: bytes) {
                        Image(uiImage: image).resizable().scaledToFill().privacySensitive()
                    }
                case let .locked(blur, _, _):
                    if let blur, let image = UIImage(data: blur) {
                        Image(uiImage: image).resizable().scaledToFill().blur(radius: 6).privacySensitive()
                    } else {
                        Color.dlLine
                    }
                    Text(t("selfie.addYoursToSeeIt"))
                        .font(.custom(DLFontName.manropeBold.name, size: 10, relativeTo: .caption2))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .padding(6)
                case .none:
                    Color.dlPaper
                    VStack(spacing: 2) {
                        Image(systemName: "camera").font(.system(size: 16, weight: .semibold))
                        Text(mine ? t("widget.takeYours") : name)
                            .font(.custom(DLFontName.manropeBold.name, size: 10, relativeTo: .caption2))
                    }
                    .foregroundStyle(mine ? Color.dlSeal : Color.dlInkQuiet)
                }
            }
            .frame(width: side, height: side)
            .clipped()
            HStack {
                Text(name)
                Spacer(minLength: 2)
                if let at = slot.takenAt { Text(at, style: .time) }
            }
            .font(.custom(DLFontName.caveatSemiBold.name, size: 15, relativeTo: .caption))
            .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.23))
            .lineLimit(1)
            .frame(width: side)
        }
        .padding(EdgeInsets(top: 6, leading: 6, bottom: 3, trailing: 6))
        .background(Color(red: 0.984, green: 0.973, blue: 0.953))
        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
        .rotationEffect(.degrees(tilt))
    }
}

/// The cork board in its wood frame (DS2), quietened for a widget.
private struct Cork: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        Rectangle()
            .fill(dark ? Color(red: 0.353, green: 0.275, blue: 0.204) : Color(red: 0.78, green: 0.612, blue: 0.42))
            .overlay(Rectangle().strokeBorder(dark ? Color(red: 0.42, green: 0.329, blue: 0.251) : Color(red: 0.788, green: 0.647, blue: 0.478), lineWidth: 5))
    }
}

// MARK: - Clocks and moods

public struct ClocksWidgetView: View {
    let data: WidgetData
    let date: Date
    let size: WidgetSize

    public init(data: WidgetData, date: Date, size: WidgetSize) {
        self.data = data
        self.date = date
        self.size = size
    }

    public var body: some View {
        if !data.signedIn {
            SignedOutFace(line: t("widget.signedOut"))
        } else if size == .rectangular {
            rectangular
        } else {
            HStack(spacing: 0) {
                if let me = data.me { half(me) }
                if let friend = data.friend {
                    Rectangle().fill(.dlLine).frame(width: 0.5).padding(.vertical, 8)
                    half(friend)
                }
            }
            .widgetURL(WidgetLink.home)
        }
    }

    private func half(_ c: WidgetCitizen) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(c.name) · \(c.city)")
                .font(.custom(DLFontName.manropeBold.name, size: 12, relativeTo: .caption))
                .foregroundStyle(.dlInkQuiet)
                .lineLimit(1)
            Text(date, style: .time)
                .font(.custom(DLFontName.manropeExtraBold.name, size: 30, relativeTo: .title))
                .monospacedDigit()
                .foregroundStyle(.dlInk)
                .widgetAccentable()
                .environment(\.timeZone, TimeZone(identifier: c.zone) ?? .current)
            if let mood = c.mood {
                Text(mood)
                    .font(.custom(DLFontName.manropeMedium.name, size: 13, relativeTo: .footnote))
                    .foregroundStyle(.dlInk)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    /// Lock Screen (WG5): names, times and the friend's mood only; no pictures.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(data.brand).font(.headline).widgetAccentable().lineLimit(1)
            HStack(spacing: 10) {
                if let me = data.me { initialTime(me) }
                if let friend = data.friend { initialTime(friend) }
            }
            .font(.system(.body, design: .rounded).weight(.semibold))
            if let friend = data.friend {
                Text([friend.name, friend.mood].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(WidgetLink.home)
    }

    private func initialTime(_ c: WidgetCitizen) -> some View {
        HStack(spacing: 3) {
            Text(String(c.name.prefix(1)).uppercased())
            Text(date, style: .time)
                .environment(\.timeZone, TimeZone(identifier: c.zone) ?? .current)
        }
    }
}

// MARK: - Shared

/// WG7: no session on this device.
struct SignedOutFace: View {
    let line: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "envelope")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.dlInkQuiet)
            Text(line)
                .dlText(.footnote)
                .foregroundStyle(.dlInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(WidgetLink.home)
    }
}

private struct NewChip: View {
    var body: some View {
        Text(t("board.new"))
            .font(.custom(DLFontName.manropeExtraBold.name, size: 10, relativeTo: .caption2))
            .tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(Color.dlSeal, in: Capsule())
            .widgetAccentable()
    }
}
