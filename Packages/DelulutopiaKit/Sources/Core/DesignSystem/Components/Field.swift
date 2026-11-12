import SwiftUI

/// A labelled text field (canvas Components › Fields): label above, a 50 pt rounded field, a hint or
/// an error under it in the error colour with a 1.5 pt ring.
public struct DLField: View {
    public enum Kind: Sendable {
        case text
        /// Entry keys: monospaced, centred, capitals, no autocorrection.
        case key
    }

    let label: String
    @Binding var text: String
    let prompt: String
    let hint: String?
    let error: String?
    let kind: Kind

    public init(
        _ label: String,
        text: Binding<String>,
        prompt: String = "",
        hint: String? = nil,
        error: String? = nil,
        kind: Kind = .text
    ) {
        self.label = label
        self._text = text
        self.prompt = prompt
        self.hint = hint
        self.error = error
        self.kind = kind
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .dlText(.fieldLabel)
                .foregroundStyle(.dlInkQuiet)
                .padding(.horizontal, 4)

            TextField(label, text: $text, prompt: Text(prompt).foregroundStyle(.dlInkDisabled))
                .dlText(kind == .key ? .key : .input)
                .foregroundStyle(.dlInk)
                .multilineTextAlignment(kind == .key ? .center : .leading)
                .textInputAutocapitalization(kind == .key ? .characters : .sentences)
                .autocorrectionDisabled(kind == .key)
                .padding(.horizontal, 16)
                .frame(minHeight: 50)
                .background(.dlCell, in: RoundedRectangle(cornerRadius: DLRadius.field, style: .continuous))
                .overlay {
                    if error != nil {
                        RoundedRectangle(cornerRadius: DLRadius.field, style: .continuous)
                            .strokeBorder(.dlError, lineWidth: 1.5)
                    }
                }

            if let error {
                Text(error)
                    .dlText(.footnoteStrong)
                    .foregroundStyle(.dlError)
                    .padding(.horizontal, 4)
            } else if let hint {
                Text(hint)
                    .dlText(.footnote)
                    .foregroundStyle(.dlInkQuiet)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// A caps section label ("FROM LEYLA"; web `.dl-section-label`).
public struct DLSectionLabel: View {
    let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .dlText(.label)
            .foregroundStyle(.dlInkQuiet)
            .accessibilityAddTraits(.isHeader)
    }
}
