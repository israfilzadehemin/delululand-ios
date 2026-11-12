import DLDesignSystem
import SwiftUI
import UIKit

/// One row of the time-zone picker (web `src/profile/zones.ts`).
public struct ZoneOption: Identifiable, Hashable, Sendable {
    public let zone: String
    public let city: String
    public let offset: String
    public let time: String

    public var id: String { zone }
}

/// The picker's data, with the web's rules: "Area/City" IANA names only, city search first,
/// accent-blind.
public enum Zones {
    public static let all: [String] = {
        let ids = TimeZone.knownTimeZoneIdentifiers.filter { $0.contains("/") && !$0.hasPrefix("Etc/") && !$0.hasPrefix("SystemV/") }
        return ids.isEmpty ? ["Europe/Warsaw", "Asia/Tehran", "Asia/Baku", "Europe/London", "America/New_York", "Asia/Tokyo"] : ids
    }()

    /// This device's zone; a device without an "Area/City" zone gets one the API accepts.
    public static var device: String {
        let id = TimeZone.current.identifier
        return id.contains("/") ? id : "Etc/UTC"
    }

    public static func city(_ zone: String) -> String {
        (zone.split(separator: "/").last.map(String.init) ?? zone).replacingOccurrences(of: "_", with: " ")
    }

    public static func option(_ zone: String, now: Date = Date()) -> ZoneOption {
        let tz = TimeZone(identifier: zone) ?? .gmt
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = tz
        f.dateFormat = "HH:mm"
        return ZoneOption(zone: zone, city: city(zone), offset: offsetWords(tz.secondsFromGMT(for: now)), time: f.string(from: now))
    }

    /// 3600 → "UTC+1", −12600 → "UTC−3:30", 0 → "UTC".
    public static func offsetWords(_ seconds: Int) -> String {
        if seconds == 0 { return "UTC" }
        let sign = seconds < 0 ? "−" : "+"
        let minutes = abs(seconds) / 60
        let h = minutes / 60
        let m = minutes % 60
        return "UTC\(sign)\(h)" + (m == 0 ? "" : String(format: ":%02d", m))
    }

    public static func match(_ query: String, in zones: [String] = all, limit: Int = 60) -> [String] {
        let q = fold(query.trimmingCharacters(in: .whitespaces))
        if q.isEmpty { return Array(zones.prefix(limit)) }
        var starts: [String] = []
        var contains: [String] = []
        for z in zones {
            if fold(city(z)).hasPrefix(q) {
                starts.append(z)
            } else if fold(z.replacingOccurrences(of: "_", with: " ")).contains(q) {
                contains.append(z)
            }
            if starts.count >= limit { break }
        }
        return Array((starts + contains).prefix(limit))
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
    }
}

/// The time-zone picker sheet (canvas F-Timezone): this device's zone first, then matches for a city
/// or zone name, each with its current time and UTC offset. Used by Create, Join and Profile.
public struct DLTimeZonePicker: View {
    let selected: String
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private let now = Date()

    public init(selected: String, onPick: @escaping (String) -> Void) {
        self.selected = selected
        self.onPick = onPick
    }

    private var device: String { Zones.device }

    public var body: some View {
        NavigationStack {
            List {
                if device.contains("/") && (query.isEmpty || !Zones.match(query, in: [device]).isEmpty) {
                    Section {
                        row(Zones.option(device, now: now))
                    } header: {
                        DLSectionLabel("This \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")")
                    }
                }
                let matches = Zones.match(query).filter { $0 != device }
                if matches.isEmpty && !query.isEmpty {
                    Text("No time zone matches “\(query)”.")
                        .dlText(.callout)
                        .foregroundStyle(.dlInkQuiet)
                        .dlListRow()
                } else {
                    Section {
                        ForEach(matches, id: \.self) { zone in row(Zones.option(zone, now: now)) }
                    } header: {
                        DLSectionLabel(query.isEmpty ? "All zones" : "Matches")
                    }
                }
            }
            .dlGroupedList()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search a city or zone")
            .navigationTitle("Time zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.large])
    }

    private func row(_ option: ZoneOption) -> some View {
        Button {
            onPick(option.zone)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.city).dlText(.callout).foregroundStyle(.dlInk)
                    Text("\(option.zone) · \(option.offset)").dlText(.footnote).foregroundStyle(.dlInkQuiet)
                }
                Spacer()
                Text(option.time).dlText(.callout).monospacedDigit().foregroundStyle(.dlInkQuiet)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.dlSeal)
                    .opacity(option.zone == selected ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dlListRow()
    }
}

/// The zone field used by the wizards and Profile: label, "City · Area/City", the time there, chevron.
public struct DLTimeZoneField: View {
    let zone: String
    let hint: String?
    @State private var picking = false
    let onPick: (String) -> Void

    public init(zone: String, hint: String? = nil, onPick: @escaping (String) -> Void) {
        self.zone = zone
        self.hint = hint
        self.onPick = onPick
    }

    public var body: some View {
        let option = Zones.option(zone)
        VStack(alignment: .leading, spacing: 6) {
            Text("Time zone")
                .dlText(.fieldLabel)
                .foregroundStyle(.dlInkQuiet)
                .padding(.horizontal, 4)
            Button { picking = true } label: {
                HStack(spacing: 8) {
                    Text("\(option.city) · \(zone)")
                        .dlText(.input)
                        .foregroundStyle(.dlInk)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(option.time).dlText(.callout).monospacedDigit().foregroundStyle(.dlInkQuiet)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.dlInkQuiet)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 50)
                .background(.dlCell, in: RoundedRectangle(cornerRadius: DLRadius.field, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let hint {
                Text(hint)
                    .dlText(.footnote)
                    .foregroundStyle(.dlInkQuiet)
                    .padding(.horizontal, 4)
            }
        }
        .sheet(isPresented: $picking) {
            DLTimeZonePicker(selected: zone, onPick: onPick)
        }
    }
}
