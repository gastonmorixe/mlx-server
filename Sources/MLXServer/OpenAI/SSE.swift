import Foundation

enum SSE {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static func encode<T: Encodable & Sendable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return "data: \(String(data: data, encoding: .utf8)!)\n\n"
    }

    static let done = "data: [DONE]\n\n"
}
