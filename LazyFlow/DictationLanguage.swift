import Foundation

enum DictationLanguage: String, CaseIterable, Codable, Identifiable {
    case automatic
    case english
    case tamil
    case hindi
    case spanish
    case french
    case german
    case portuguese
    case japanese
    case korean
    case chinese
    case arabic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic:  "Automatic"
        case .english:    "English"
        case .tamil:      "Tamil"
        case .hindi:      "Hindi"
        case .spanish:    "Spanish"
        case .french:     "French"
        case .german:     "German"
        case .portuguese: "Portuguese"
        case .japanese:   "Japanese"
        case .korean:     "Korean"
        case .chinese:    "Chinese"
        case .arabic:     "Arabic"
        }
    }

    var apiCode: String? {
        switch self {
        case .automatic:  nil
        case .english:    "en"
        case .tamil:      "ta"
        case .hindi:      "hi"
        case .spanish:    "es"
        case .french:     "fr"
        case .german:     "de"
        case .portuguese: "pt"
        case .japanese:   "ja"
        case .korean:     "ko"
        case .chinese:    "zh"
        case .arabic:     "ar"
        }
    }
}
