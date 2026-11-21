import DLDesignSystem
import DLI18n
import SwiftUI
import WidgetKit

/// One moment of the widgets' data.
public struct DLWidgetEntry: TimelineEntry, Sendable {
    public let date: Date
    public let data: WidgetData

    public init(date: Date, data: WidgetData) {
        self.date = date
        self.data = data
    }
}

/// Loads once per timeline: an entry now, one at each selfie's expiry, and a reload in 30 min (WG3).
/// The app also reloads the timelines when Home changes, and the Notification Service Extension
/// when a push it handles arrives.
public struct DLWidgetProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> DLWidgetEntry {
        DLWidgetEntry(date: Date(), data: .sample())
    }

    public func getSnapshot(in context: Context, completion: @escaping (DLWidgetEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        // WidgetKit calls back on any thread; the closure is only ever called once, from the task.
        nonisolated(unsafe) let done = completion
        Task {
            done(DLWidgetEntry(date: Date(), data: await WidgetLoader.load()))
        }
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<DLWidgetEntry>) -> Void) {
        nonisolated(unsafe) let done = completion
        Task {
            let now = Date()
            let data = await WidgetLoader.load()
            let entries = WidgetTimeline.dates(data, now: now).map { DLWidgetEntry(date: $0, data: data.at($0)) }
            done(Timeline(entries: entries, policy: .after(now.addingTimeInterval(WidgetTimeline.refresh))))
        }
    }
}

/// The faces' common setting: fonts, the citizen's language and direction, the paper background.
private struct WidgetFace<Content: View>: View {
    let entry: DLWidgetEntry
    @ViewBuilder let content: () -> Content

    var body: some View {
        let lang = Lang(rawValue: entry.data.lang) ?? .en
        content()
            .environment(\.layoutDirection, lang.rtl ? .rightToLeft : .leftToRight)
            .environment(\.locale, lang.locale)
            .containerBackground(for: .widget) { Color.dlPaper }
    }
}

/// Board · small and large (iOS design §6).
public struct DLBoardWidget: Widget {
    public init() { DLFonts.register() }

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: "board", provider: DLWidgetProvider()) { entry in
            BoardFace(entry: entry)
        }
        .configurationDisplayName(t("board.board"))
        .description(t("widget.board.description"))
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}

private struct BoardFace: View {
    let entry: DLWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        WidgetFace(entry: entry) {
            BoardWidgetView(data: entry.data, date: entry.date, size: WidgetSize(family))
        }
    }
}

/// Selfies · small and medium (Selfies DS12).
public struct DLSelfiesWidget: Widget {
    public init() { DLFonts.register() }

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: "selfies", provider: DLWidgetProvider()) { entry in
            SelfiesFace(entry: entry)
        }
        .configurationDisplayName(t("selfie.selfies"))
        .description(t("widget.selfies.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private struct SelfiesFace: View {
    let entry: DLWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        WidgetFace(entry: entry) {
            SelfiesWidgetView(data: entry.data, date: entry.date, size: WidgetSize(family))
        }
    }
}

/// Clocks and moods · medium, and the Lock Screen's rectangular one (iOS design §6).
public struct DLClocksWidget: Widget {
    public init() { DLFonts.register() }

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: "clocks", provider: DLWidgetProvider()) { entry in
            ClocksFace(entry: entry)
        }
        .configurationDisplayName(t("widget.clocks.name"))
        .description(t("widget.clocks.description"))
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}

private struct ClocksFace: View {
    let entry: DLWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        WidgetFace(entry: entry) {
            ClocksWidgetView(data: entry.data, date: entry.date, size: WidgetSize(family))
        }
    }
}
