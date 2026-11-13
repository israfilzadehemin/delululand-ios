import DLData
import DLDesignSystem
import DLI18n
import SwiftUI

public enum PIN {
    public static let length = 6
}

/// The iOS PIN keypad (canvas S-PIN): round 78 pt keys on the letter paper, SF digits, 26 pt apart;
/// bottom left the Face ID key when offered, bottom right backspace. Each key ticks (rule I-8). The
/// sixth digit calls `onComplete`; `digits` belongs to the caller so nothing outlives an attempt.
public struct DLPinPad: View {
    @Binding var digits: String
    let enabled: Bool
    let biometric: BiometricVault.Kind?
    let onBiometric: (() -> Void)?
    let onComplete: (String) -> Void
    @State private var ticks = 0

    public init(
        digits: Binding<String>,
        enabled: Bool = true,
        biometric: BiometricVault.Kind? = nil,
        onBiometric: (() -> Void)? = nil,
        onComplete: @escaping (String) -> Void
    ) {
        self._digits = digits
        self.enabled = enabled
        self.biometric = biometric
        self.onBiometric = onBiometric
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: 16) {
            ForEach(["123", "456", "789"], id: \.self) { row in
                HStack(spacing: 26) {
                    ForEach(Array(row), id: \.self) { d in key(d) }
                }
            }
            HStack(spacing: 26) {
                if let onBiometric, let biometric, biometric != .none {
                    Button(action: onBiometric) {
                        Image(systemName: biometric == .faceID ? "faceid" : "touchid")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.dlSeal)
                            .frame(width: 78, height: 78)
                            .contentShape(Circle())
                    }
                    .buttonStyle(DLPressStyle(scale: 0.9))
                    .accessibilityLabel(t(biometric == .faceID ? "pin.unlockWithFaceId" : "pin.unlockWithTouchId"))
                } else {
                    Color.clear.frame(width: 78, height: 78)
                }
                key("0")
                Button {
                    guard enabled, !digits.isEmpty else { return }
                    digits.removeLast()
                    ticks += 1
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(.dlInk)
                        .frame(width: 78, height: 78)
                        .contentShape(Circle())
                }
                .buttonStyle(DLPressStyle(scale: 0.9))
                .accessibilityLabel(t("common.backspace"))
            }
        }
        .disabled(!enabled)
        .sensoryFeedback(.selection, trigger: ticks)
        // L5: a keypad keeps its order in every language (1 2 3 left to right; backspace bottom right).
        .environment(\.layoutDirection, .leftToRight)
    }

    private func key(_ d: Character) -> some View {
        Button {
            guard enabled, digits.count < PIN.length else { return }
            digits.append(d)
            ticks += 1
            if digits.count == PIN.length { onComplete(digits) }
        } label: {
            Text(localDigits(String(d)))
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.dlInk)
                .frame(width: 78, height: 78)
                .background(.dlPaperLetter, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(DLPressStyle(scale: 0.9))
    }
}

/// The PIN layout shared by sign-in and the wizards' PIN step (canvas S-PIN, U-PIN): header (picture
/// and name, or who), the prompt (22/800), a hint or error line, the dots (a wrong PIN shakes them),
/// then the keypad.
public struct DLPinPanel<Header: View>: View {
    let prompt: String
    let hint: String?
    let error: String?
    @Binding var digits: String
    let busy: Bool
    let biometric: BiometricVault.Kind?
    let onBiometric: (() -> Void)?
    let onComplete: (String) -> Void
    let header: Header
    @State private var shakes = 0

    public init(
        prompt: String,
        hint: String? = nil,
        error: String?,
        digits: Binding<String>,
        busy: Bool,
        biometric: BiometricVault.Kind? = nil,
        onBiometric: (() -> Void)? = nil,
        onComplete: @escaping (String) -> Void,
        @ViewBuilder header: () -> Header
    ) {
        self.prompt = prompt
        self.hint = hint
        self.error = error
        self._digits = digits
        self.busy = busy
        self.biometric = biometric
        self.onBiometric = onBiometric
        self.onComplete = onComplete
        self.header = header()
    }

    public var body: some View {
        VStack(spacing: 26) {
            VStack(spacing: 10) {
                header
                Text(prompt)
                    .dlText(.title2)
                    .foregroundStyle(.dlInk)
                    .padding(.top, 8)
                Text(error ?? hint ?? " ")
                    .dlText(error != nil ? .footnoteStrong : .footnote)
                    .foregroundStyle(error != nil ? Color.dlError : Color.dlInkQuiet)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 20)
                    .id(error ?? hint ?? "")
                    .transition(.opacity)
            }
            .dlEnter(.rise, delay: 0.06)
            DLPinDots(entered: digits.count, error: error != nil)
                .phaseAnimator([0, -10, 10, -7, 7, -3, 0] as [CGFloat], trigger: shakes) { dots, x in
                    dots.offset(x: x)
                } animation: { _ in .linear(duration: 0.05) }
            DLPinPad(digits: $digits, enabled: !busy, biometric: biometric, onBiometric: onBiometric, onComplete: onComplete)
                .padding(.top, 14)
        }
        .padding(.horizontal, 16)
        .onChange(of: error) { _, new in
            if new != nil { shakes += 1 }
        }
        .sensoryFeedback(.error, trigger: shakes)
    }
}
