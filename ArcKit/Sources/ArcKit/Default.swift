import Foundation

// Arc's answers leave out fields that are empty or false, and may add new ones (the v1 promise:
// "ignore what you don't know"). `@Default` gives a missing or null field its usual value, so a
// model only needs optionals where "absent" means something.

public protocol DefaultValue {
    associatedtype Value: Codable & Sendable
    static var defaultValue: Value { get }
}

@propertyWrapper
public struct Default<D: DefaultValue>: Codable, Sendable {
    public var wrappedValue: D.Value

    public init() { wrappedValue = D.defaultValue }

    public init(wrappedValue: D.Value) { self.wrappedValue = wrappedValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = container.decodeNil() ? D.defaultValue : try container.decode(D.Value.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

extension Default: Equatable where D.Value: Equatable {}
extension Default: Hashable where D.Value: Hashable {}

extension KeyedDecodingContainer {
    public func decode<D>(_ type: Default<D>.Type, forKey key: Key) throws -> Default<D> {
        try decodeIfPresent(type, forKey: key) ?? Default()
    }
}

public enum Defaults {
    public enum False: DefaultValue { public static var defaultValue: Bool { false } }
    public enum True: DefaultValue { public static var defaultValue: Bool { true } }
    public enum Zero: DefaultValue { public static var defaultValue: Int { 0 } }
    public enum MinusOne: DefaultValue { public static var defaultValue: Int { -1 } }
    public enum Zero64: DefaultValue { public static var defaultValue: Int64 { 0 } }
    public enum ZeroDouble: DefaultValue { public static var defaultValue: Double { 0 } }
    public enum Empty: DefaultValue { public static var defaultValue: String { "" } }
    public enum List<T: Codable & Sendable>: DefaultValue { public static var defaultValue: [T] { [] } }
    public enum Dictionary<T: Codable & Sendable>: DefaultValue { public static var defaultValue: [String: T] { [:] } }
}

/// Any JSON value, for the parts of an answer the app passes on as they are (a custom row's filter).
public enum JSONValue: Codable, Sendable, Hashable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }

    /// As a query parameter for /items, or nil for something it doesn't take (false, null, lists).
    public var queryValue: String? {
        switch self {
        case .string(let s): return s
        case .bool(let b): return b ? "1" : nil
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        default: return nil
        }
    }
}
