import Foundation

public struct Memory: Codable, Sendable, Equatable {
    public let id: String
    public let content: String
    public let metadata: [String: AnyCodable]?
    public let createdAt: Date?
}

public struct SearchHit: Codable, Sendable, Equatable {
    public let id: String
    public let content: String
    public let score: Double
    public let metadata: [String: AnyCodable]?
}

public struct SearchResponse: Codable, Sendable, Equatable {
    public let hits: [SearchHit]
}

public struct ListResponse: Codable, Sendable, Equatable {
    public let data: [Memory]
    public let nextCursor: String?
}

public enum MnemoError: Error, Equatable, Sendable {
    case missingApiKey
    case missingWorkspaceId
    case invalidURL
    case http(status: Int, body: String)
    case decoding(String)
}

/// Minimal type-erased Codable wrapper so metadata can hold arbitrary JSON.
public struct AnyCodable: Codable, Sendable, Equatable {
    public let value: Sendable

    public init(_ value: Sendable) { self.value = value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = NSNull()
        } else if let b = try? container.decode(Bool.self) {
            self.value = b
        } else if let i = try? container.decode(Int.self) {
            self.value = i
        } else if let d = try? container.decode(Double.self) {
            self.value = d
        } else if let s = try? container.decode(String.self) {
            self.value = s
        } else if let a = try? container.decode([AnyCodable].self) {
            self.value = a
        } else if let o = try? container.decode([String: AnyCodable].self) {
            self.value = o
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case is NSNull: try c.encodeNil()
        case let b as Bool: try c.encode(b)
        case let i as Int: try c.encode(i)
        case let d as Double: try c.encode(d)
        case let s as String: try c.encode(s)
        case let a as [AnyCodable]: try c.encode(a)
        case let o as [String: AnyCodable]: try c.encode(o)
        default:
            throw EncodingError.invalidValue(value, .init(codingPath: c.codingPath, debugDescription: "unsupported"))
        }
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case (is NSNull, is NSNull): return true
        case let (l as Bool, r as Bool): return l == r
        case let (l as Int, r as Int): return l == r
        case let (l as Double, r as Double): return l == r
        case let (l as String, r as String): return l == r
        case let (l as [AnyCodable], r as [AnyCodable]): return l == r
        case let (l as [String: AnyCodable], r as [String: AnyCodable]): return l == r
        default: return false
        }
    }
}
