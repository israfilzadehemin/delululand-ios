import Foundation

/// The letter format (Technical Design §4.3; web `src/text/richText.ts`; Android `RichText.kt`): a
/// ProseMirror document with exactly paragraphs, bullet lists, bold, italic and underline. The server
/// validates the same grammar.
public struct Doc: Codable, Sendable, Hashable {
    public var content: [DocBlock]

    public init(content: [DocBlock] = [.paragraph([])]) {
        self.content = content.isEmpty ? [.paragraph([])] : content
    }

    public static let empty = Doc()

    /// Plain paragraphs, one per string.
    public static func of(_ paragraphs: String...) -> Doc {
        Doc(content: paragraphs.map { DocBlock.paragraph($0.isEmpty ? [] : [TextRun($0)]) })
    }

    enum CodingKeys: String, CodingKey { case type, content }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let blocks = try c.decodeIfPresent([DocBlock].self, forKey: .content) ?? []
        self.init(content: blocks)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("doc", forKey: .type)
        try c.encode(content, forKey: .content)
    }

    /// FS-W11, AT-20: empty means no visible character anywhere (whitespace does not count).
    public var isEmpty: Bool {
        content.allSatisfy { block in block.texts.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    }

    /// The plain text, paragraphs joined by newlines (previews, the reply slip's first line).
    public var plainText: String {
        content.flatMap(\.texts).joined(separator: "\n")
    }
}

public enum DocBlock: Codable, Sendable, Hashable {
    case paragraph([TextRun])
    /// Each item holds paragraphs only (§4.3).
    case bulletList([[TextRun]])

    enum CodingKeys: String, CodingKey { case type, content }

    private struct ListItem: Codable {
        var type = "listItem"
        var content: [DocBlock]
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "bulletList":
            let items = try c.decodeIfPresent([ListItem].self, forKey: .content) ?? []
            self = .bulletList(items.map { item in
                item.content.flatMap { block -> [TextRun] in
                    if case let .paragraph(runs) = block { return runs }
                    return []
                }
            })
        default:
            self = .paragraph(try c.decodeIfPresent([TextRun].self, forKey: .content) ?? [])
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .paragraph(runs):
            try c.encode("paragraph", forKey: .type)
            if !runs.isEmpty {
                try c.encode(runs, forKey: .content)
            }
        case let .bulletList(items):
            try c.encode("bulletList", forKey: .type)
            try c.encode(items.map { ListItem(content: [.paragraph($0)]) }, forKey: .content)
        }
    }

    var texts: [String] {
        switch self {
        case let .paragraph(runs): [runs.map(\.text).joined()]
        case let .bulletList(items): items.map { $0.map(\.text).joined() }
        }
    }
}

/// A run of text with its marks (bold / italic / underline).
public struct TextRun: Codable, Sendable, Hashable {
    public var text: String
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool

    public init(_ text: String, bold: Bool = false, italic: Bool = false, underline: Bool = false) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.underline = underline
    }

    enum CodingKeys: String, CodingKey { case type, text, marks }

    private struct Mark: Codable {
        let type: String
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        let marks = Set((try c.decodeIfPresent([Mark].self, forKey: .marks) ?? []).map(\.type))
        bold = marks.contains("bold")
        italic = marks.contains("italic")
        underline = marks.contains("underline")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("text", forKey: .type)
        try c.encode(text, forKey: .text)
        var marks: [Mark] = []
        if bold { marks.append(Mark(type: "bold")) }
        if italic { marks.append(Mark(type: "italic")) }
        if underline { marks.append(Mark(type: "underline")) }
        if !marks.isEmpty {
            try c.encode(marks, forKey: .marks)
        }
    }

    public var sameMarks: (Bool, Bool, Bool) { (bold, italic, underline) }
}
