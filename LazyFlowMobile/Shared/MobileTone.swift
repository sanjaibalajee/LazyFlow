import SwiftUI

enum MobileTone: String, CaseIterable, Codable, Identifiable, Sendable {
    case clean
    case casual
    case veryCasual
    case formal
    case verbatim

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clean: "Clean"
        case .casual: "Casual"
        case .veryCasual: "Very casual"
        case .formal: "Formal"
        case .verbatim: "Verbatim"
        }
    }

    var compactTitle: String {
        switch self {
        case .veryCasual: "Chill"
        case .verbatim: "Raw"
        default: title
        }
    }

    var subtitle: String {
        switch self {
        case .clean: "Clear and natural"
        case .casual: "Warm and conversational"
        case .veryCasual: "Relaxed, like a quick text"
        case .formal: "Polished and professional"
        case .verbatim: "Your exact words"
        }
    }

    var symbol: String {
        switch self {
        case .clean: "wand.and.sparkles"
        case .casual: "bubble.left.and.bubble.right"
        case .veryCasual: "face.smiling"
        case .formal: "briefcase"
        case .verbatim: "quote.bubble"
        }
    }

    var tint: Color {
        switch self {
        case .clean: Color(red: 0.16, green: 0.46, blue: 0.98)
        case .casual: Color(red: 0.45, green: 0.28, blue: 0.96)
        case .veryCasual: Color(red: 0.94, green: 0.34, blue: 0.48)
        case .formal: Color(red: 0.08, green: 0.50, blue: 0.45)
        case .verbatim: Color.secondary
        }
    }

    var editingInstructions: String {
        let shared = """
        Return only the rewritten text. Preserve the speaker's meaning, facts, names, numbers, links, and language. Never invent information, emoji, or formatting. Remove filler words and false starts only when the chosen tone permits it. Do not answer the speaker or comment on the request.
        """

        switch self {
        case .clean:
            return shared + " Make it concise, clear, grammatical, and natural while retaining the speaker's voice."
        case .casual:
            return shared + " Use a friendly conversational voice, natural contractions, and uncomplicated sentences."
        case .veryCasual:
            return shared + " Make it feel like a relaxed message to a friend. Prefer short sentences and contractions. Avoid unnecessary trailing punctuation, but do not force slang or lowercase names."
        case .formal:
            return shared + " Use polished professional language, complete sentences, precise wording, and restrained punctuation."
        case .verbatim:
            return "Return the transcript unchanged."
        }
    }
}
