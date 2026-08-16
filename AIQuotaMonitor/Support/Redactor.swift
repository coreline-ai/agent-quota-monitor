import Foundation

enum Redactor {
    private static let replacement = "<redacted>"

    static func redact(_ input: String) -> String {
        var result = input
        let patterns = [
            #"(?i)bearer\s+[A-Za-z0-9._~+/=-]+"#,
            #"(?i)(api[_-]?key|access[_-]?token|authorization)\s*[:=]\s*[^\s,;]+"#,
            #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            #"/Users/[^/\s]+"#,
            #"/home/[^/\s]+"#
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }
}
