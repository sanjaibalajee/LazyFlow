import Foundation

// MARK: - Word-level diff
//
// Extracts only the changed word regions between two strings using LCS.
// Example: "I asked that guy to confirm" → "I asked Pranav to confirm"
//          produces [(heard: "that guy", correct: "Pranav")]
// Multiple changed regions → multiple pairs, each stored separately.

enum WordDiff {

    struct Pair { let heard: String; let correct: String }

    static func extract(original: String, corrected: String) -> [Pair] {
        let orig = words(original)
        let corr = words(corrected)
        guard orig != corr else { return [] }

        let changes = diff(orig, corr)

        // Group contiguous changed words into single pairs
        var pairs: [Pair] = []
        var i = 0
        while i < changes.count {
            if case .changed(let h, let c) = changes[i] {
                var heardWords   = [h]
                var correctWords = [c]
                var j = i + 1
                while j < changes.count, case .changed(let h2, let c2) = changes[j] {
                    heardWords.append(h2); correctWords.append(c2); j += 1
                }
                let heard   = heardWords.compactMap   { $0 }.joined(separator: " ")
                let correct = correctWords.compactMap { $0 }.joined(separator: " ")
                if !heard.isEmpty || !correct.isEmpty {
                    pairs.append(Pair(heard: heard, correct: correct))
                }
                i = j
            } else {
                i += 1
            }
        }
        return pairs
    }

    // MARK: Private

    private enum Change { case same; case changed(String?, String?) }

    private static func words(_ s: String) -> [String] {
        s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    }

    private static func diff(_ a: [String], _ b: [String]) -> [Change] {
        // Build LCS table
        var t = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 1...max(a.count, 1) where i <= a.count {
            for j in 1...max(b.count, 1) where j <= b.count {
                t[i][j] = a[i-1].lowercased() == b[j-1].lowercased()
                    ? t[i-1][j-1] + 1
                    : max(t[i-1][j], t[i][j-1])
            }
        }

        // Iterative backtrack (avoids recursion limit on long transcripts)
        var changes: [Change] = []
        var i = a.count, j = b.count
        while i > 0 || j > 0 {
            if i > 0, j > 0, a[i-1].lowercased() == b[j-1].lowercased() {
                changes.append(.same); i -= 1; j -= 1
            } else if j > 0, (i == 0 || t[i][j-1] >= t[i-1][j]) {
                changes.append(.changed(nil, b[j-1])); j -= 1
            } else {
                changes.append(.changed(a[i-1], nil)); i -= 1
            }
        }
        return changes.reversed()
    }
}

// MARK: - Lightweight two-stage relevance filter — no dependencies.
//
// Stage 1 (fast): token prefix overlap — if any token in `heard` shares
//   its first 3 chars with any token in the transcript, it's a candidate.
// Stage 2 (accurate): Levenshtein distance ≤ 2 on matching token pairs.
//
// Used to filter the full corrections dictionary down to only the pairs
// relevant to the current transcript before sending to the LLM.

enum PhoneticMatcher {

    static func isRelevant(heard: String, to transcript: String) -> Bool {
        let hTokens = tokens(heard)
        let tTokens = tokens(transcript)
        guard !hTokens.isEmpty, !tTokens.isEmpty else { return false }

        // Stage 1: at least one heard-token shares a 3-char prefix with a transcript-token
        let candidates = hTokens.filter { h in
            tTokens.contains { t in
                let len = min(h.count, t.count, 3)
                return len >= 2 && h.prefix(len) == t.prefix(len)
            }
        }
        guard !candidates.isEmpty else { return false }

        // Stage 2: at least one candidate is within edit-distance 2
        return candidates.contains { h in
            tTokens.contains { t in editDistance(h, t) <= 2 }
        }
    }

    // MARK: - Helpers

    private static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.filter { $0.isLetter || $0.isNumber } }
            .filter { $0.count >= 3 }  // ≥3 chars reduces false positives on short tokens
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                curr[j] = a[i-1] == b[j-1]
                    ? prev[j-1]
                    : 1 + min(prev[j-1], prev[j], curr[j-1])
            }
            prev = curr
        }
        return prev[n]
    }
}
