import DLDesignSystem
import DLI18n
import DLNetwork
import DLUI
import SwiftUI
import UIKit

/// Email replies (doc "Delululand — Email Replies"; web emails/reply.tsx): the quote inside a bubble
/// (RE11) and the strip in the reply bar (RE9). The edge and the name wear the quoted sender's
/// signature, darkened so they read on either bubble tint (doc §1, "Colours").
struct QuoteColours {
    let edge: Color
    let name: Color

    static func of(_ who: Who, dark: Bool) -> QuoteColours {
        switch (who, dark) {
        case (.a, false): QuoteColours(edge: Color(uiColor: DLRGBA(0xC9785E).uiColor), name: Color(uiColor: DLRGBA(0x8E4730).uiColor))
        case (.b, false): QuoteColours(edge: Color(uiColor: DLRGBA(0x6E9C8E).uiColor), name: Color(uiColor: DLRGBA(0x35685A).uiColor))
        case (.a, true): QuoteColours(edge: Color(uiColor: DLRGBA(0xD99A82).uiColor), name: Color(uiColor: DLRGBA(0xEBB9A5).uiColor))
        case (.b, true): QuoteColours(edge: Color(uiColor: DLRGBA(0x9CBDB3).uiColor), name: Color(uiColor: DLRGBA(0xAED3C7).uiColor))
        }
    }
}

/// RE11: at the top inside the bubble; a tap jumps to the original (RE12).
struct BubbleQuote: View {
    let quote: EmailQuote
    let name: String
    let who: Who
    let onOpen: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colours = QuoteColours.of(who, dark: scheme == .dark)
        Button(action: onOpen) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(size: 12.5, weight: .heavy)).foregroundStyle(colours.name).lineLimit(1)
                    Text(quoteLine(quote)).font(.system(size: 13)).foregroundStyle(.dlInkQuiet).lineLimit(2).multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                QuoteThumb(quote: quote)
            }
            .padding(.leading, 11).padding(.trailing, 8).padding(.vertical, 5)
            .frame(minHeight: 44)
            .background(scheme == .dark ? Color.black.opacity(0.26) : Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .leading) { colours.edge.frame(width: 3).clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8)) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t("emails.goToOriginal", ["name": name]))
    }
}

/// RE9: above the counter line of the reply bar, with × to drop the target.
struct ReplyStrip: View {
    let quote: EmailQuote
    let name: String
    let who: Who
    let onCancel: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colours = QuoteColours.of(who, dark: scheme == .dark)
        let heading = t("emails.replyingTo", ["name": name])
        HStack(spacing: 8) {
            Image(systemName: "arrowshape.turn.up.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.dlInkQuiet)
                .flipsForRightToLeftLayoutDirection(true)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(heading).font(.system(size: 12.5, weight: .heavy)).foregroundStyle(colours.name).lineLimit(1)
                Text(quoteLine(quote)).font(.system(size: 13)).foregroundStyle(.dlInkQuiet).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            QuoteThumb(quote: quote)
            Button(action: onCancel) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.dlInkQuiet).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("emails.cancelReply"))
        }
        .padding(.leading, 13)
        .background(Color.dlPaperLetter, in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .leading) { colours.edge.frame(width: 3).clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(heading)
    }
}

private struct QuoteThumb: View {
    let quote: EmailQuote

    var body: some View {
        if let thumb = quote.thumbUrl {
            RemoteImage(thumb, contentMode: .fill, maxPixel: 120) { Color.dlPaperLetter }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)
        }
    }
}
