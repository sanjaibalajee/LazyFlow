import Foundation
import CoreGraphics

// MARK: - Agent Step (one row in the streaming log)

struct AgentStep: Identifiable, Sendable {
    enum Status: Sendable {
        case running
        case done(TimeInterval)
        case failed(String)
        case waitingApproval
        case waitingClarification
    }

    var id           = UUID()
    var tool:        String
    var description: String
    var status:      Status = .running
    var thought:     String? = nil   // LLM reasoning that preceded this step
    let startedAt    = Date()

    nonisolated var systemImage: String {
        switch tool {
        case "see":               return "camera.viewfinder"
        case "open_app":          return "app.badge"
        case "click":             return "cursorarrow.click"
        case "double_click":      return "cursorarrow.click.2"
        case "click_coords":      return "cursorarrow.click"
        case "type":              return "keyboard"
        case "press_key":         return "return"
        case "scroll":            return "arrow.up.arrow.down"
        case "wait":              return "clock"
        case "ask_clarification": return "questionmark.bubble"
        case "done":              return "checkmark.circle.fill"
        default:                  return "bolt"
        }
    }
}

// MARK: - Events emitted by ComputerUseService → AgentState

enum AgentEvent: Sendable {
    case stepStarted(AgentStep)
    case stepUpdated(id: UUID, status: AgentStep.Status)
    case approvalRequired(id: UUID, action: String)
    case clarificationRequired(id: UUID, question: String)
    case thought(String)          // LLM reasoning text before tool calls
    case turnCount(Int)           // current iteration number
    case done(String)
    case failed(String)
    case cancelled
}

// MARK: - Detected UI element from AX snapshot

struct DetectedElement: Codable, Sendable {
    let id:        String   // "elem_0", "elem_1", …
    let type:      String   // "button", "textField", "link", …
    let label:     String?
    let value:     String?
    let bounds:    CGRect
    let isEnabled: Bool

    nonisolated var requiresApproval: Bool {
        guard type == "button" else { return false }
        let l = (label ?? "").lowercased()
        return ["submit","send","delete","remove","confirm","pay","purchase",
                "publish","sign out","log out","buy","post","commit"].contains { l.contains($0) }
    }

    nonisolated var elementDescription: String {
        var parts = ["[\(type)]"]
        if let l = label, !l.isEmpty { parts.append("\"\(l)\"") }
        if let v = value, !v.isEmpty, type == "textField" { parts.append("value=\"\(v)\"") }
        parts.append("(\(Int(bounds.minX)),\(Int(bounds.minY)) \(Int(bounds.width))×\(Int(bounds.height)))")
        if !isEnabled { parts.append("disabled") }
        return parts.joined(separator: " ")
    }
}

// MARK: - Parsed Groq tool call

struct AgentToolCall: Sendable {
    let id:        String
    let name:      String
    let arguments: [String: String]

    nonisolated func arg(_ key: String) -> String? { arguments[key] }
}
