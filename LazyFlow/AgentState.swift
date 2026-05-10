import Foundation

@Observable
@MainActor
final class AgentState {

    enum Phase {
        case idle
        case enteringGoal
        case running
        case done(String)
        case failed(String)
    }

    // MARK: - Observable

    var phase:     Phase  = .idle
    var goal:      String = ""
    var steps:     [AgentStep] = []
    var turnCount: Int = 0

    private var pendingThought: String? = nil

    var pendingApprovalAction:        String? = nil
    var pendingClarificationQuestion: String? = nil
    var clarificationDraft:           String  = ""

    // MARK: - Callbacks wired to ComputerUseService

    var onApprove:              (() -> Void)?
    var onReject:               (() -> Void)?
    var onAnswerClarification:  ((String) -> Void)?
    var onCancel:               (() -> Void)?

    // MARK: - Mutations called by ComputerUseService via AgentState.apply(_:)

    func apply(_ event: AgentEvent) {
        switch event {

        case .stepStarted(var step):
            step.thought = pendingThought
            pendingThought = nil
            steps.append(step)

        case .stepUpdated(let id, let status):
            if let i = steps.firstIndex(where: { $0.id == id }) {
                steps[i].status = status
                // Clear blocking-state flags if the step moved on
                switch status {
                case .done, .failed:
                    pendingApprovalAction        = nil
                    pendingClarificationQuestion = nil
                default: break
                }
            }

        case .approvalRequired(let id, let action):
            if let i = steps.firstIndex(where: { $0.id == id }) {
                steps[i].status = .waitingApproval
            }
            pendingApprovalAction = action

        case .clarificationRequired(let id, let question):
            if let i = steps.firstIndex(where: { $0.id == id }) {
                steps[i].status = .waitingClarification
            }
            pendingClarificationQuestion = question
            clarificationDraft = ""

        case .thought(let text):
            pendingThought = text

        case .turnCount(let n):
            turnCount = n

        case .done(let summary):
            phase = .done(summary)

        case .failed(let message):
            phase = .failed(message)

        case .cancelled:
            phase = .idle
        }
    }

    // MARK: - Helpers

    func reset() {
        phase                        = .idle
        goal                         = ""
        steps                        = []
        turnCount                    = 0
        pendingThought               = nil
        pendingApprovalAction        = nil
        pendingClarificationQuestion = nil
        clarificationDraft           = ""
        onApprove             = nil
        onReject              = nil
        onAnswerClarification = nil
        onCancel              = nil
    }

    var isBlocked: Bool {
        pendingApprovalAction != nil || pendingClarificationQuestion != nil
    }
}
