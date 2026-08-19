import Foundation

struct DictationCommandResult: Equatable {
    var text: String
    var pressEnter: Bool
}

enum DictationCommands {
    private static let pressEnterPattern = try! NSRegularExpression(
        pattern: #"(?i)(?:[.!?]\s*)?\bpress\s+enter\b[.!?]?\s*$"#
    )
    private static let newParagraphPattern = try! NSRegularExpression(
        pattern: #"(?i)\bnew\s+paragraph\b[,.]?\s*"#
    )
    private static let newLinePattern = try! NSRegularExpression(
        pattern: #"(?i)\b(?:new|next)\s+line\b[,.]?\s*"#
    )

    static func prepare(_ text: String, pressEnterEnabled: Bool) -> DictationCommandResult {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var shouldPressEnter = false

        if pressEnterEnabled {
            let range = NSRange(result.startIndex..., in: result)
            if pressEnterPattern.firstMatch(in: result, range: range) != nil {
                result = pressEnterPattern.stringByReplacingMatches(
                    in: result,
                    range: range,
                    withTemplate: ""
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                shouldPressEnter = true
            }
        }

        result = replace(newParagraphPattern, in: result, with: "\n\n")
        result = replace(newLinePattern, in: result, with: "\n")
        return DictationCommandResult(text: result, pressEnter: shouldPressEnter)
    }

    static func removeTrailingPeriod(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("."), !trimmed.hasSuffix("..."), trimmed.count > 1 else {
            return trimmed
        }
        return String(trimmed.dropLast())
    }

    private static func replace(
        _ regex: NSRegularExpression,
        in text: String,
        with replacement: String
    ) -> String {
        regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: replacement
        )
    }
}
