import DLDesignSystem
import DLI18n
import DLNetwork
import Observation
import SwiftUI
import UIKit

/*
 * The letter editor (web editor/RichEditor.tsx; Technical Design §6.4): paragraphs, bullet lists,
 * bold, italic and underline in Literata 17 on 28 pt lines. A UITextView underneath; the document
 * is ProseMirror JSON (`Doc`) both ways. A bullet item is a paragraph that starts with "• ".
 */

private let bulletPrefix = "• "

enum RichFaces {
    static func face(bold: Bool, italic: Bool) -> DLFontName {
        switch (bold, italic) {
        case (true, true): .literataBoldItalic
        case (true, false): .literataBold
        case (false, true): .literataItalic
        case (false, false): .literataRegular
        }
    }

    static func traits(of font: UIFont?) -> (bold: Bool, italic: Bool) {
        let name = font?.fontName ?? ""
        return (name.contains("Bold"), name.contains("Italic"))
    }
}

@MainActor
public enum RichText {
    static func font(bold: Bool, italic: Bool, size: CGFloat) -> UIFont {
        UIFont(name: RichFaces.face(bold: bold, italic: italic).rawValue, size: size) ?? .systemFont(ofSize: size)
    }

    static func paragraphStyle(size: CGFloat, lineHeight: CGFloat, bullet: Bool) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = lineHeight
        p.maximumLineHeight = lineHeight
        if bullet {
            let indent = ceil(NSString(string: bulletPrefix).size(withAttributes: [.font: font(bold: false, italic: false, size: size)]).width)
            p.headIndent = indent
        }
        return p
    }

    public static func attributed(_ doc: Doc, size: CGFloat, lineHeight: CGFloat, color: UIColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        func base(bullet: Bool) -> [NSAttributedString.Key: Any] {
            [.font: font(bold: false, italic: false, size: size), .foregroundColor: color,
             .paragraphStyle: paragraphStyle(size: size, lineHeight: lineHeight, bullet: bullet)]
        }
        func append(_ runs: [TextRun], bullet: Bool) {
            if out.length > 0 { out.append(NSAttributedString(string: "\n", attributes: base(bullet: bullet))) }
            if bullet { out.append(NSAttributedString(string: bulletPrefix, attributes: base(bullet: true))) }
            for run in runs {
                var attrs = base(bullet: bullet)
                attrs[.font] = font(bold: run.bold, italic: run.italic, size: size)
                if run.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                out.append(NSAttributedString(string: run.text, attributes: attrs))
            }
        }
        for block in doc.content {
            switch block {
            case let .paragraph(runs): append(runs, bullet: false)
            case let .bulletList(items): items.forEach { append($0, bullet: true) }
            }
        }
        return out
    }

    public static func doc(_ text: NSAttributedString) -> Doc {
        var blocks: [DocBlock] = []
        var list: [[TextRun]] = []
        let ns = text.string as NSString
        var location = 0
        func flushList() {
            if !list.isEmpty { blocks.append(.bulletList(list)) }
            list = []
        }
        repeat {
            let range = ns.lineRange(for: NSRange(location: location, length: 0))
            var content = range
            if content.length > 0, ns.substring(with: NSRange(location: NSMaxRange(content) - 1, length: 1)) == "\n" {
                content.length -= 1
            }
            let line = ns.substring(with: content)
            let bullet = line.hasPrefix(bulletPrefix)
            if bullet {
                content.location += (bulletPrefix as NSString).length
                content.length -= (bulletPrefix as NSString).length
            }
            var runs: [TextRun] = []
            if content.length > 0 {
                text.enumerateAttributes(in: content) { attrs, r, _ in
                    let (bold, italic) = RichFaces.traits(of: attrs[.font] as? UIFont)
                    let underline = (attrs[.underlineStyle] as? Int ?? 0) != 0
                    let piece = ns.substring(with: r)
                    if let last = runs.last, last.bold == bold, last.italic == italic, last.underline == underline {
                        runs[runs.count - 1].text += piece
                    } else {
                        runs.append(TextRun(piece, bold: bold, italic: italic, underline: underline))
                    }
                }
            }
            if bullet {
                list.append(runs)
            } else {
                flushList()
                blocks.append(.paragraph(runs))
            }
            location = NSMaxRange(range)
        } while location < ns.length
        if ns.length > 0, ns.hasSuffix("\n") {
            flushList()
            blocks.append(.paragraph([]))
        }
        flushList()
        // Trailing empty paragraphs carry nothing.
        while case let .paragraph(runs)? = blocks.last, runs.isEmpty, blocks.count > 1 { blocks.removeLast() }
        return Doc(content: blocks)
    }
}

/// What the format bar shows and toggles; the editor writes the document out through `onChange`.
@MainActor
@Observable
public final class RichEditorState {
    public internal(set) var bold = false
    public internal(set) var italic = false
    public internal(set) var underline = false
    public internal(set) var bullet = false
    public internal(set) var focused = false
    @ObservationIgnored weak var textView: UITextView?
    @ObservationIgnored var pending: Doc?
    @ObservationIgnored var size: CGFloat = 17
    @ObservationIgnored var lineHeight: CGFloat = 28
    @ObservationIgnored var changed: ((Doc) -> Void)?

    public init() {}

    /// Puts the caret in the editor (a tap on the empty sheet).
    public func focus() {
        textView?.becomeFirstResponder()
    }

    /// Replace the content (Load, a newer draft).
    public func set(_ doc: Doc) {
        guard let textView else {
            pending = doc
            return
        }
        textView.attributedText = RichText.attributed(doc, size: size, lineHeight: lineHeight, color: UIColor(Color.dlLetterInk))
        syncFromSelection()
    }

    public func toggleBold() { toggle(\.bold) }
    public func toggleItalic() { toggle(\.italic) }
    public func toggleUnderline() { toggle(\.underline) }

    private func toggle(_ key: ReferenceWritableKeyPath<RichEditorState, Bool>) {
        guard let tv = textView else { return }
        self[keyPath: key].toggle()
        let range = tv.selectedRange
        if range.length > 0 {
            let storage = tv.textStorage
            storage.beginEditing()
            storage.enumerateAttributes(in: range) { attrs, r, _ in
                var (b, i) = RichFaces.traits(of: attrs[.font] as? UIFont)
                if key == \RichEditorState.bold { b = bold }
                if key == \RichEditorState.italic { i = italic }
                storage.addAttribute(.font, value: RichText.font(bold: b, italic: i, size: size), range: r)
                if key == \RichEditorState.underline {
                    if underline { storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r) } else { storage.removeAttribute(.underlineStyle, range: r) }
                }
            }
            storage.endEditing()
            emit()
        }
        applyTyping()
    }

    /// Bullets on or off for the paragraphs under the selection.
    public func toggleBullet() {
        guard let tv = textView else { return }
        let ns = tv.textStorage.string as NSString
        let lines = ns.paragraphRange(for: tv.selectedRange)
        var starts: [Int] = []
        ns.enumerateSubstrings(in: lines, options: [.byParagraphs, .substringNotRequired]) { _, r, _, _ in starts.append(r.location) }
        if starts.isEmpty { starts = [lines.location] }
        let on = !bullet
        let storage = tv.textStorage
        let prefix = bulletPrefix as NSString
        var shift = 0
        var selection = tv.selectedRange
        storage.beginEditing()
        for start in starts {
            let at = start + shift
            let has = storage.length >= at + prefix.length && (storage.string as NSString).substring(with: NSRange(location: at, length: prefix.length)) == bulletPrefix
            if on, !has {
                storage.insert(NSAttributedString(string: bulletPrefix, attributes: typingAttributes(bullet: true)), at: at)
                shift += prefix.length
                if at <= selection.location { selection.location += prefix.length } else { selection.length += prefix.length }
            } else if !on, has {
                storage.deleteCharacters(in: NSRange(location: at, length: prefix.length))
                shift -= prefix.length
                if at < selection.location { selection.location = max(at, selection.location - prefix.length) } else { selection.length = max(0, selection.length - prefix.length) }
            }
            let para = (storage.string as NSString).paragraphRange(for: NSRange(location: min(at, storage.length), length: 0))
            storage.addAttribute(.paragraphStyle, value: RichText.paragraphStyle(size: size, lineHeight: lineHeight, bullet: on), range: para)
        }
        storage.endEditing()
        tv.selectedRange = NSRange(location: min(selection.location, storage.length), length: min(selection.length, storage.length - min(selection.location, storage.length)))
        bullet = on
        applyTyping()
        emit()
    }

    func typingAttributes(bullet: Bool) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: RichText.font(bold: bold, italic: italic, size: size),
            .foregroundColor: UIColor(Color.dlLetterInk),
            .paragraphStyle: RichText.paragraphStyle(size: size, lineHeight: lineHeight, bullet: bullet),
        ]
        if underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        return attrs
    }

    func applyTyping() {
        textView?.typingAttributes = typingAttributes(bullet: bullet)
    }

    func syncFromSelection() {
        guard let tv = textView else { return }
        let storage = tv.textStorage
        let at = max(0, min(tv.selectedRange.location, storage.length) - (tv.selectedRange.length == 0 ? 1 : 0))
        if storage.length > 0 {
            let attrs = storage.attributes(at: min(at, storage.length - 1), effectiveRange: nil)
            let (b, i) = RichFaces.traits(of: attrs[.font] as? UIFont)
            bold = b
            italic = i
            underline = (attrs[.underlineStyle] as? Int ?? 0) != 0
        }
        let ns = storage.string as NSString
        let para = ns.paragraphRange(for: NSRange(location: min(tv.selectedRange.location, ns.length), length: 0))
        bullet = ns.substring(with: para).hasPrefix(bulletPrefix)
        applyTyping()
    }

    func emit() {
        guard let tv = textView else { return }
        changed?(RichText.doc(tv.attributedText))
    }
}

/// The editor view. `onChange` receives the document after each edit.
public struct RichEditor: UIViewRepresentable {
    let state: RichEditorState
    let initial: Doc
    let enabled: Bool
    let placeholder: String
    let onChange: (Doc) -> Void

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    public init(_ state: RichEditorState, initial: Doc, enabled: Bool = true, placeholder: String = "", onChange: @escaping (Doc) -> Void) {
        self.state = state
        self.initial = initial
        self.enabled = enabled
        self.placeholder = placeholder
        self.onChange = onChange
    }

    public func makeUIView(context: Context) -> UITextView {
        let tv = GrowingTextView()
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = context.coordinator
        tv.tintColor = UIColor(Color.dlSeal)
        tv.adjustsFontForContentSizeCategory = false
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        state.size = 17 * scale
        state.lineHeight = 28 * scale
        state.textView = tv
        state.changed = onChange
        tv.attributedText = RichText.attributed(state.pending ?? initial, size: state.size, lineHeight: state.lineHeight, color: UIColor(Color.dlLetterInk))
        state.pending = nil
        state.applyTyping()
        tv.placeholder = placeholder
        tv.accessibilityLabel = placeholder.isEmpty ? t("letters.letter") : placeholder
        let bar = UIHostingController(rootView: FormatBar(state: state).environment(\.colorScheme, tv.traitCollection.userInterfaceStyle == .dark ? .dark : .light))
        bar.view.backgroundColor = .clear
        bar.view.frame = CGRect(x: 0, y: 0, width: 320, height: 52)
        bar.view.autoresizingMask = [.flexibleWidth]
        tv.inputAccessoryView = bar.view
        context.coordinator.bar = bar
        return tv
    }

    public func updateUIView(_ tv: UITextView, context: Context) {
        tv.isEditable = enabled
        state.changed = onChange
        (tv as? GrowingTextView)?.placeholder = placeholder
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(fit.height, state.lineHeight))
    }

    public func makeCoordinator() -> Coordinator { Coordinator(state) }

    @MainActor
    public final class Coordinator: NSObject, UITextViewDelegate {
        let state: RichEditorState
        var bar: UIViewController?

        init(_ state: RichEditorState) {
            self.state = state
        }

        public func textViewDidChange(_ textView: UITextView) {
            (textView as? GrowingTextView)?.updatePlaceholder()
            textView.invalidateIntrinsicContentSize()
            state.emit()
        }

        public func textViewDidChangeSelection(_ textView: UITextView) {
            state.syncFromSelection()
        }

        public func textViewDidBeginEditing(_ textView: UITextView) { state.focused = true }
        public func textViewDidEndEditing(_ textView: UITextView) { state.focused = false }

        /// Return in a bullet item continues the list; on an empty item it ends the list.
        public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n", state.bullet else { return true }
            let ns = textView.textStorage.string as NSString
            let para = ns.paragraphRange(for: NSRange(location: range.location, length: 0))
            let line = ns.substring(with: para).trimmingCharacters(in: .newlines)
            if line == bulletPrefix.trimmingCharacters(in: .whitespaces) || line == bulletPrefix {
                state.toggleBullet()
                return false
            }
            let insert = NSAttributedString(string: "\n" + bulletPrefix, attributes: state.typingAttributes(bullet: true))
            textView.textStorage.replaceCharacters(in: range, with: insert)
            textView.selectedRange = NSRange(location: range.location + insert.length, length: 0)
            textViewDidChange(textView)
            return false
        }
    }
}

/// A text view that grows with its text and shows a placeholder while empty.
final class GrowingTextView: UITextView {
    private let placeholderLabel = UILabel()

    var placeholder: String = "" {
        didSet {
            placeholderLabel.text = placeholder
            updatePlaceholder()
        }
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholderLabel.font = UIFont(name: DLFontName.literataRegular.rawValue, size: 17)
        placeholderLabel.textColor = UIColor(Color.dlInkQuiet)
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var attributedText: NSAttributedString! {
        didSet { updatePlaceholder() }
    }

    func updatePlaceholder() {
        placeholderLabel.isHidden = !text.isEmpty
    }

    override var intrinsicContentSize: CGSize {
        let fit = sizeThatFits(CGSize(width: bounds.width > 0 ? bounds.width : 320, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: fit.height)
    }
}

/// The format bar that rides on the keyboard (I-3): bold, italic, underline, bullets, and Done.
struct FormatBar: View {
    let state: RichEditorState

    var body: some View {
        HStack(spacing: 4) {
            button("bold", t("editor.bold"), on: state.bold, action: state.toggleBold)
            button("italic", t("editor.italic"), on: state.italic, action: state.toggleItalic)
            button("underline", t("editor.underline"), on: state.underline, action: state.toggleUnderline)
            button("list.bullet", t("editor.bulletList"), on: state.bullet, action: state.toggleBullet)
            Spacer()
            Button {
                state.textView?.resignFirstResponder()
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.dlInk)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(t("editor.hideKeyboard"))
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .background(.bar)
    }

    private func button(_ symbol: String, _ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(on ? Color.dlSeal : Color.dlInk)
                .frame(width: 44, height: 40)
                .background(on ? Color.dlSeal.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
