import Foundation

public enum PlaceholderExpansion {
    public static func expand(
        template: String,
        row: String,
        delimiter: String? = nil,
        query: String = "",
        lines: Int = 20
    ) -> String {
        var output = template
        output = output.replacingOccurrences(of: "{}", with: shellEscaped(row))
        output = output.replacingOccurrences(of: "{q}", with: shellEscaped(query))

        let fields = splitFields(row: row, delimiter: delimiter)
        if !fields.isEmpty {
            for fieldIndex in 1...fields.count {
                output = output.replacingOccurrences(
                    of: "{\(fieldIndex)}",
                    with: shellEscaped(fields[fieldIndex - 1])
                )
            }
        }
        output = output.replacingOccurrences(of: "$LINES", with: String(lines))
        return output
    }

    public static func splitFields(row: String, delimiter: String?) -> [String] {
        guard let delimiter, !delimiter.isEmpty else {
            return row.split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)
        }

        return row.components(separatedBy: delimiter)
    }

    public static func shellEscaped(_ value: String) -> String {
        if value.isEmpty {
            return "''"
        }

        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:-")
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }

        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
