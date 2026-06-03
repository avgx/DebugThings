import Foundation

public enum JSONPrinter {

    public static func stringify<T: Encodable>(
        _ value: T,
        sortedKeys: Bool = false
    ) throws -> String {

        let encoder = JSONEncoder()

        var formatting: JSONEncoder.OutputFormatting = [.prettyPrinted, .withoutEscapingSlashes]

        if sortedKeys {
            formatting.insert(.sortedKeys)
        }

        encoder.outputFormatting = formatting

        let data = try encoder.encode(value)

        return String(decoding: data, as: UTF8.self)
    }
}
