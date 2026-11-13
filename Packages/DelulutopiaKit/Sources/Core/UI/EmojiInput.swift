import SwiftUI
import UIKit

/// A tile that opens the system emoji keyboard and keeps the one emoji typed last (mood form, the
/// reaction "every emoji" picker). iOS has no public emoji picker; the emoji keyboard is the
/// platform's own (canvas "emoji sheet").
public struct EmojiInput<Label: View>: View {
    @Binding var emoji: String
    @Binding var isEditing: Bool
    let label: Label

    public init(emoji: Binding<String>, isEditing: Binding<Bool>, @ViewBuilder label: () -> Label) {
        _emoji = emoji
        _isEditing = isEditing
        self.label = label()
    }

    public var body: some View {
        label
            .background(EmojiField(emoji: $emoji, isEditing: $isEditing).frame(width: 1, height: 1).opacity(0.01))
            .contentShape(Rectangle())
            .onTapGesture { isEditing = true }
    }
}

/// The last emoji typed into `text`, if any.
public func firstEmoji(_ text: String) -> String? {
    for c in text.reversed() where c.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x238C) }) {
        return String(c)
    }
    return nil
}

private struct EmojiField: UIViewRepresentable {
    @Binding var emoji: String
    @Binding var isEditing: Bool

    func makeUIView(context: Context) -> EmojiTextField {
        let field = EmojiTextField()
        field.delegate = context.coordinator
        field.tintColor = .clear
        field.textColor = .clear
        field.autocorrectionType = .no
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: EmojiTextField, context: Context) {
        context.coordinator.parent = self
        if isEditing, !field.isFirstResponder {
            DispatchQueue.main.async { field.becomeFirstResponder() }
        } else if !isEditing, field.isFirstResponder {
            DispatchQueue.main.async { field.resignFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: EmojiField

        init(_ parent: EmojiField) {
            self.parent = parent
        }

        @objc func changed(_ field: UITextField) {
            if let picked = firstEmoji(field.text ?? "") {
                parent.emoji = picked
                parent.isEditing = false
            }
            field.text = ""
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if parent.isEditing { parent.isEditing = false }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.isEditing = false
            return true
        }
    }
}

/// A text field that asks for the emoji keyboard.
final class EmojiTextField: UITextField {
    override var textInputContextIdentifier: String? { "" }

    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }
}
