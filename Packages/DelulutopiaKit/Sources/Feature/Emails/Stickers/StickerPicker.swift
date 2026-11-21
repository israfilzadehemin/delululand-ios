import DLData
import DLDesignSystem
import DLI18n
import DLNetwork
import DLUI
import SwiftUI

/// The sticker picker (doc "Delululand — Stickers" FS-SK1–SK5; web stickers/StickerPicker.tsx), in
/// place of the keyboard: search, Recent, Favourites, Ours (+ and N of cap), the packs, and a strip of
/// sections at the bottom. One tap sends (FS-SK6) and it stays open; at 0 credits the grid is dimmed
/// (FS-SK5). Long-press on one of Ours offers Delete (FS-SK25).
struct StickerPicker: View {
    let store: StickerStore
    let disabled: Bool
    let onPick: (Sticker) -> Void
    let onAdd: () -> Void
    let onDelete: (Sticker) -> Void

    @State private var query = ""
    @State private var active = "recent"
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)

    var body: some View {
        let cat = store.catalogue
        let all = cat.map(stickerSections) ?? []
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        let results = searching ? (cat?.stickers ?? []).filter { stickerMatches($0, query) } : []
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(.dlInkQuiet)
                TextField(t("stickers.search"), text: $query)
                    .font(.system(size: 15))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Color.dlPaperLetter, in: Capsule())
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
            ZStack {
                if cat == nil, store.failed {
                    Text(t("stickers.couldntLoad")).dlText(.footnote).foregroundStyle(.dlInkQuiet)
                } else if cat == nil {
                    ProgressView()
                } else if searching, results.isEmpty {
                    Text(t("stickers.nothingFound")).dlText(.footnote).foregroundStyle(.dlInkQuiet)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 4) {
                                if searching {
                                    ForEach(results) { s in tile(s, own: s.custom != nil) }
                                } else {
                                    ForEach(all) { sec in
                                        Section {
                                            if sec.add { addTile }
                                            ForEach(sec.items) { s in tile(s, own: sec.key == "ours") }
                                        } header: {
                                            header(sec, cat: cat)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 4)
                            .opacity(disabled ? 0.45 : 1)
                        }
                        .onChange(of: active) { _, key in
                            withAnimation(.snappy) { proxy.scrollTo("h-" + key, anchor: .top) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !searching, !all.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(all) { sec in
                            Button { active = sec.key } label: {
                                Group {
                                    switch sec.key {
                                    case "recent": Image(systemName: "clock")
                                    case "favourites": Image(systemName: "star")
                                    case "ours": Image(systemName: "heart")
                                    default:
                                        RemoteImage(sec.items.first?.url256, contentMode: .fit, maxPixel: 96) { Color.clear }
                                            .frame(width: 28, height: 28)
                                    }
                                }
                                .font(.system(size: 17))
                                .foregroundStyle(.dlInkQuiet)
                                .frame(width: 44, height: 40)
                                .background(active == sec.key ? Color.dlPaperLetter : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(sec.title)
                            .accessibilityAddTraits(active == sec.key ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                }
                .accessibilityLabel(t("stickers.sections"))
            }
        }
        .frame(height: 320)
    }

    private func header(_ sec: StickerSection, cat: StickerCatalogue?) -> some View {
        HStack {
            Text(sec.title).font(.system(size: 12.5, weight: .heavy)).foregroundStyle(.dlInkQuiet)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if sec.add, let cat {
                Text(t("stickers.usedOfCap", ["used": cat.custom.used, "cap": cat.custom.cap]))
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(.dlInkQuiet)
            }
        }
        .padding(.top, 10).padding(.bottom, 2)
        .id("h-" + sec.key)
    }

    private var addTile: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.dlInkQuiet)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.dlLine, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t("stickers.addSticker"))
    }

    private func tile(_ s: Sticker, own: Bool) -> some View {
        RemoteImage(s.url256, contentMode: .fit, maxPixel: 256) { Color.clear }
            .padding(4)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture { if !disabled { onPick(s) } }
            .onLongPressGesture {
                guard own else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onDelete(s)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stickerLabel(s))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: t("stickers.delete")) { if own { onDelete(s) } }
    }
}

/// Tapping a sticker in a thread (SK10; web stickers/StickerSheet.tsx): the sticker at 240 pt,
/// ★ Favourite, and "More from this pack" (8, a tap sends) — or who added one of Ours.
struct StickerSheet: View {
    let store: StickerStore
    let sticker: StickerRef
    let caption: String
    let canSend: Bool
    let addedBy: (Sticker) -> String
    let onSend: (Sticker) -> Void
    let onClose: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)

    var body: some View {
        let cat = store.catalogue
        let full = cat?.stickers.first { $0.id == sticker.id }
        let fav = store.isFavourite(sticker.id)
        let pack = full?.pack.flatMap { p in cat?.packs.first { $0.slug == p } }
        let more: [Sticker] = full?.pack.map { p in Array((cat?.stickers ?? []).filter { $0.pack == p && $0.id != sticker.id }.prefix(8)) } ?? []
        ScrollView {
            VStack(spacing: 10) {
                RemoteImage(sticker.url512, contentMode: .fit, maxPixel: 720) { Color.clear }
                    .frame(width: 240, height: 240)
                    .accessibilityLabel(full.map(stickerLabel) ?? t("stickers.label"))
                Text(full.flatMap { $0.custom != nil ? addedBy($0) : nil } ?? caption)
                    .font(.system(size: 12.5)).foregroundStyle(.dlInkQuiet)
                    .multilineTextAlignment(.center)
                if full != nil {
                    Button {
                        store.toggleFavourite(sticker.id)
                    } label: {
                        Label(fav ? t("stickers.removeFavourite") : t("stickers.addFavourite"), systemImage: fav ? "star.fill" : "star")
                    }
                    .buttonStyle(DLButtonStyle(.outline))
                }
                if let pack, !more.isEmpty {
                    HStack {
                        Text(t("stickers.morePack", ["pack": pack.name])).font(.system(size: 13, weight: .heavy))
                        Spacer()
                        if canSend { Text(t("stickers.tapToSend")).font(.system(size: 12)).foregroundStyle(.dlInkQuiet) }
                    }
                    .padding(.top, 6)
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(more) { s in
                            Button {
                                onSend(s)
                                onClose()
                            } label: {
                                RemoteImage(s.url256, contentMode: .fit, maxPixel: 256) { Color.clear }
                                    .padding(6)
                                    .aspectRatio(1, contentMode: .fit)
                            }
                            .buttonStyle(.plain)
                            .disabled(!canSend)
                            .accessibilityLabel(stickerLabel(s))
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 24)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
