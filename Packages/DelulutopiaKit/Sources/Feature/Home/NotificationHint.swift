import DLData
import DLDesignSystem
import DLI18n
import SwiftUI
import UIKit

/// Home's "notifications off" line (FS-A15; iOS design A-Home, notifications off): shown while this
/// device can't show notifications. Never asked: Turn on brings up the system prompt. Blocked: only
/// iOS Settings can change it, so the button opens them. Hidden once notifications are on.
struct NotificationHint: View {
    @Environment(Backend.self) private var backend
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let permission = backend.push.permission
        Group {
            if permission == .notAsked || permission == .blocked {
                HStack(spacing: 10) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.dlSeal)
                    Text(permission == .blocked ? t("settings.device.blockedSubIos") : t("notify.hintOff"))
                        .dlText(.footnote)
                        .foregroundStyle(.dlInk)
                    Spacer(minLength: 0)
                    Button(permission == .blocked ? t("settings.settings") : t("notify.turnOn")) { turnOn(permission) }
                        .buttonStyle(DLButtonStyle(.tint))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.dlSealTint, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.dlSealTintLine))
                .accessibilityElement(children: .combine)
                .dlEnter(.drop)
            }
        }
        // Back from iOS Settings: read the switch again.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await backend.push.refreshPermission() } }
        }
    }

    private func turnOn(_ permission: PushStore.Permission) {
        if permission == .blocked {
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
        } else {
            Task { await backend.push.requestPermission() }
        }
    }
}
