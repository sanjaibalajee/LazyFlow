import Foundation

/// Repairs the distinctive failure mode where a cleanup model returns every word in Title Case
/// or ALL CAPS. Normal output is returned byte-for-byte unchanged.
enum OutputCapitalization {
    private static let wordPattern = try! NSRegularExpression(
        pattern: #"\p{L}[\p{L}\p{M}'’\-]*"#
    )

    static func sanitize(
        _ output: String,
        reference: String,
        forceLowercase: Bool,
        allowTitleCase: Bool,
        protectedTerms: [String]
    ) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if forceLowercase { return trimmed.lowercased() }
        guard !allowTitleCase, hasAccidentalGlobalCapitalization(trimmed) else { return trimmed }

        let referenceIsSuspicious = hasAccidentalGlobalCapitalization(reference)
        let referenceCasing = referenceIsSuspicious ? [:] : casingMap(for: reference)
        let protectedCasing = Dictionary(
            protectedTerms.map { ($0.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var result = ""
        var cursor = trimmed.startIndex
        var startsSentence = true
        let range = NSRange(trimmed.startIndex..., in: trimmed)

        for match in wordPattern.matches(in: trimmed, range: range) {
            guard let wordRange = Range(match.range, in: trimmed) else { continue }
            let separator = String(trimmed[cursor..<wordRange.lowerBound])
            result += separator
            if separator.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?\n")) != nil {
                startsSentence = true
            }

            let word = String(trimmed[wordRange])
            let key = word.lowercased()
            var replacement: String

            if let protected = protectedCasing[key] {
                replacement = protected
            } else if let source = referenceCasing[key] {
                replacement = source
            } else if hasMeaningfulInternalCapitalization(word) {
                replacement = word
            } else if key == "i" {
                replacement = "I"
            } else {
                replacement = word.lowercased()
            }

            if startsSentence {
                replacement = uppercaseFirstLetter(in: replacement)
            }
            result += replacement
            startsSentence = false
            cursor = wordRange.upperBound
        }

        result += trimmed[cursor...]
        print("[LazyFlow] ⚠️ Repaired accidental global capitalization from cleanup output")
        return result
    }

    private static func hasAccidentalGlobalCapitalization(_ text: String) -> Bool {
        let words = wordStrings(in: text).filter { casedLetters(in: $0).count >= 2 }
        guard words.count >= 6 else { return false }

        let suspicious = words.filter { word in
            let letters = casedLetters(in: word)
            guard let first = letters.first else { return false }
            let titleCased = first.isUppercase && letters.dropFirst().allSatisfy(\.isLowercase)
            let allCaps = letters.allSatisfy(\.isUppercase)
            return titleCased || allCaps
        }.count

        return Double(suspicious) / Double(words.count) >= 0.8
    }

    private static func casingMap(for text: String) -> [String: String] {
        var counts: [String: [String: Int]] = [:]
        for word in wordStrings(in: text) {
            counts[word.lowercased(), default: [:]][word, default: 0] += 1
        }
        return counts.mapValues { variants in
            variants.max { lhs, rhs in lhs.value < rhs.value }?.key ?? ""
        }
    }

    private static func wordStrings(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return wordPattern.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    private static func casedLetters(in word: String) -> [Character] {
        word.filter { $0.isLetter && ($0.isUppercase || $0.isLowercase) }
    }

    private static func hasMeaningfulInternalCapitalization(_ word: String) -> Bool {
        let letters = casedLetters(in: word)
        guard letters.count > 1 else { return false }
        return letters.dropFirst().contains(where: \.isUppercase)
            && letters.contains(where: \.isLowercase)
    }

    private static func uppercaseFirstLetter(in word: String) -> String {
        guard let index = word.firstIndex(where: \.isLetter) else { return word }
        var result = word
        result.replaceSubrange(index...index, with: String(result[index]).uppercased())
        return result
    }
}
