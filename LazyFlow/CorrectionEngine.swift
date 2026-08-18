import Foundation

enum CorrectionEngine {
    /// Applies non-overlapping replacements against the original transcript. Immutable
    /// ranges prevent cascading `a → b → c` corrections and keep usage counts exact.
    static func apply(
        _ text: String,
        corrections: [CorrectionEntry]
    ) -> (text: String, appliedIDs: Set<String>) {
        struct Match {
            let range: NSRange
            let replacement: String
            let correctionID: String
        }

        let fullRange = NSRange(text.startIndex..., in: text)
        var matches: [Match] = []

        for correction in corrections {
            let heard = CorrectionEntry.normalizedPhrase(correction.heard)
            guard !heard.isEmpty else { continue }
            let escaped = NSRegularExpression.escapedPattern(for: heard)
            let pattern = "(?i)(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }

            for result in regex.matches(in: text, range: fullRange) {
                matches.append(Match(
                    range: result.range,
                    replacement: correction.correct,
                    correctionID: correction.id
                ))
            }
        }

        matches.sort {
            if $0.range.location != $1.range.location {
                return $0.range.location < $1.range.location
            }
            return $0.range.length > $1.range.length
        }

        var accepted: [Match] = []
        for match in matches {
            guard !accepted.contains(where: {
                NSIntersectionRange($0.range, match.range).length > 0
            }) else { continue }
            accepted.append(match)
        }

        let result = NSMutableString(string: text)
        for match in accepted.sorted(by: { $0.range.location > $1.range.location }) {
            result.replaceCharacters(in: match.range, with: match.replacement)
        }

        return (result as String, Set(accepted.map(\.correctionID)))
    }
}
