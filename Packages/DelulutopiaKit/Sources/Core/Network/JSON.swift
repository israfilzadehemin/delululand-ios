import Foundation

/// A value the API sends beside a refusal (`{code, message, …extra}`) or anywhere the shape is open.
public enum JSONValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case let .bool(b): try c.encode(b)
        case let .number(n): try c.encode(n)
        case let .string(s): try c.encode(s)
        case let .array(a): try c.encode(a)
        case let .object(o): try c.encode(o)
        }
    }

    public var string: String? {
        if case let .string(s) = self { return s }
        return nil
    }

    public var int: Int? {
        if case let .number(n) = self { return Int(n) }
        return nil
    }

    /// Decodes this value as `T` (a `board` beside `BOARD_CHANGED`, say).
    public func decode<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Defaults for missing keys

/// A default for a key the API may leave out (Kotlin's `= emptyList()`, `= false`, `= 0`).
public protocol DefaultValueProvider {
    associatedtype Value: Codable & Sendable & Hashable
    static var defaultValue: Value { get }
}

/// A Codable field that decodes to `P.defaultValue` when the key is missing or null.
@propertyWrapper
public struct Default<P: DefaultValueProvider>: Codable, Sendable, Hashable {
    public var wrappedValue: P.Value

    public init(wrappedValue: P.Value = P.defaultValue) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        wrappedValue = c.decodeNil() ? P.defaultValue : try c.decode(P.Value.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(wrappedValue)
    }
}

public extension KeyedDecodingContainer {
    func decode<P>(_ type: Default<P>.Type, forKey key: Key) throws -> Default<P> {
        try decodeIfPresent(type, forKey: key) ?? Default()
    }
}

public enum False: DefaultValueProvider {
    public static var defaultValue: Bool { false }
}

public enum True: DefaultValueProvider {
    public static var defaultValue: Bool { true }
}

public enum Zero: DefaultValueProvider {
    public static var defaultValue: Int { 0 }
}

public enum EmptyString: DefaultValueProvider {
    public static var defaultValue: String { "" }
}

public enum EmptyList<Element: Codable & Sendable & Hashable>: DefaultValueProvider {
    public static var defaultValue: [Element] { [] }
}

/// Coders shared by the client: the API's field names are already camelCase.
enum Coders {
    static func decoder() -> JSONDecoder { JSONDecoder() }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }
}
