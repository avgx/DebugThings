import Foundation

public enum YAMLPrinter {

    public static func stringify<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)

        let object = try JSONSerialization.jsonObject(
            with: data,
            options: []
        )

        return yaml(from: object)
    }

    private static func yaml(
        from object: Any,
        indentLevel: Int = 0
    ) -> String {
        let indent = String(repeating: "  ", count: indentLevel)

        switch object {

        case let dict as [String: Any]:
            return dict
                .sorted(by: { $0.key < $1.key })
                .map { key, value in
                    if value is [String: Any] || value is [Any] {
                        return "\(indent)\(key):\n" +
                               yaml(from: value, indentLevel: indentLevel + 1)
                    } else {
                        return "\(indent)\(key): \(format(value))\n"
                    }
                }
                .joined()

        case let array as [Any]:
            return array.map { item in
                if item is [String: Any] || item is [Any] {
                    return "\(indent)-\n" +
                           yaml(from: item, indentLevel: indentLevel + 1)
                } else {
                    return "\(indent)- \(format(item))\n"
                }
            }
            .joined()

        default:
            return "\(indent)\(format(object))\n"
        }
    }

    private static func format(_ value: Any) -> String {

        switch value {

        case let string as String:
            return "\"\(string)\""

        case let bool as Bool:
            return bool ? "true" : "false"

        case let number as NSNumber:
            return "\(number)"

        case is NSNull:
            return "null"

        default:
            return "\"\(value)\""
        }
    }
}
