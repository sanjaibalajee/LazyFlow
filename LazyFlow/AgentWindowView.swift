import SwiftUI

// MARK: - Root shell

struct AgentWindowView: View {
    @Environment(AgentState.self) private var agent

    var body: some View {
        content
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.primary.opacity(0.08), lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private var content: some View {
        switch agent.phase {
        case .idle:          Color.clear.frame(height: 0)
        case .enteringGoal:  GoalInputView()
        case .running:       AgentRunnerView()
        case .done(let s):   DoneView(summary: s, isError: false)
        case .failed(let s): DoneView(summary: s, isError: true)
        }
    }
}

// MARK: - Goal input

struct GoalInputView: View {
    @Environment(AgentState.self) private var agent
    @Environment(AppState.self)   private var appState
    @FocusState private var focused: Bool

    private var empty: Bool { agent.goal.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        @Bindable var agent = agent
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.purple)
                }
                .padding(.leading, 14)

                // Text field
                TextField("What should I do?", text: $agent.goal, axis: .vertical)
                    .font(.system(size: 14))
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .focused($focused)
                    .onSubmit { go() }

                // Mic
                Button {
                    if appState.isRecording {
                        appState.stopRecording()
                    } else {
                        appState.onGoalTranscribed = { [agent] t in
                            if !t.isEmpty { agent.goal = t }
                        }
                        appState.startGoalRecording()
                    }
                } label: {
                    Image(systemName: appState.isRecording ? "waveform" : "mic")
                        .font(.system(size: 13))
                        .foregroundStyle(appState.isRecording ? Color.red : Color.secondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(appState.isRecording ? Color.red.opacity(0.1) : Color.primary.opacity(0.06)))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)

                // Send
                Button(action: go) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(empty ? Color.secondary.opacity(0.2) : Color.purple)
                }
                .buttonStyle(.plain)
                .disabled(empty)

                // Close
                CloseBtn { agent.onCancel?() }
            }
            .padding(.vertical, 13)
        }
        .task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            focused = true
        }
    }

    private func go() {
        guard !empty else { return }
        agent.onApprove?()
    }
}

// MARK: - Agent runner

struct AgentRunnerView: View {
    @Environment(AgentState.self) private var agent

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.2)
            stepList
            if agent.pendingApprovalAction != nil || agent.pendingClarificationQuestion != nil {
                Divider().opacity(0.2)
                actionCard
            }
        }
    }

    // ── Header ───────────────────────────────────────────────────────────

    private var header: some View {
        HStack(spacing: 10) {
            // Animated running indicator
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.purple)
            }
            .padding(.leading, 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(agent.goal)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("Running…")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if agent.turnCount > 0 {
                TurnBadge(turn: agent.turnCount, max: 40)
                    .padding(.trailing, 4)
            }

            CloseBtn { agent.onCancel?() }
        }
        .frame(minHeight: 52)
        .padding(.vertical, 6)
    }

    // ── Step list ─────────────────────────────────────────────────────────

    private var stepList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(agent.steps) { step in
                        StepRow(step: step).id(step.id)
                        if step.id != agent.steps.last?.id {
                            Divider()
                                .padding(.leading, 52)
                                .opacity(0.12)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 340)
            .onChange(of: agent.steps.count) { _, _ in
                if let last = agent.steps.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // ── Approval / clarification card ─────────────────────────────────────

    @ViewBuilder
    private var actionCard: some View {
        if let action = agent.pendingApprovalAction {
            ApprovalCard(action: action)
        } else if let question = agent.pendingClarificationQuestion {
            ClarificationCard(question: question)
        }
    }
}

// MARK: - Turn badge

private struct TurnBadge: View {
    let turn: Int
    let max:  Int

    private var isWarning: Bool { turn > max * 2 / 3 }

    var body: some View {
        Text("\(turn) / \(max)")
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(isWarning ? Color.orange : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(isWarning ? Color.orange.opacity(0.1) : Color.primary.opacity(0.06))
            )
    }
}

// MARK: - Step row

struct StepRow: View {
    let step: AgentStep
    @State private var expanded = false

    private var hasThought: Bool { step.thought != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Main row — tappable if there's a thought to expand
            Button {
                guard hasThought else { return }
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 0) {
                    iconView.frame(width: 52)

                    Text(step.description)
                        .font(.system(size: 13))
                        .foregroundStyle(labelColor)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Timing
                    if case .done(let t) = step.status, t > 0.05 {
                        Text(String(format: "%.1fs", t))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.quaternary)
                            .padding(.trailing, hasThought ? 4 : 16)
                    }

                    // Expand chevron — only when thought exists
                    if hasThought {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.quaternary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                            .padding(.trailing, 16)
                    }
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasThought)

            // Thought panel — shown when expanded
            if expanded, let thought = step.thought {
                HStack(alignment: .top, spacing: 8) {
                    Rectangle()
                        .fill(Color.purple.opacity(0.3))
                        .frame(width: 2)
                        .padding(.leading, 26)
                        .padding(.vertical, 2)

                    Text(thought)
                        .font(.system(size: 12).italic())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 16)
                        .padding(.vertical, 8)
                }
                .background(Color.purple.opacity(0.03))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var iconView: some View {
        switch step.status {
        case .running:
            ProgressView().controlSize(.small).tint(.purple)
        case .done:
            Image(systemName: step.systemImage)
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.red)
        case .waitingApproval:
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 14))
                .foregroundStyle(.orange)
        case .waitingClarification:
            Image(systemName: "questionmark.bubble.fill")
                .font(.system(size: 14))
                .foregroundStyle(.blue)
        }
    }

    private var labelColor: Color {
        switch step.status {
        case .done:   return .secondary
        case .failed: return .red
        default:      return .primary
        }
    }
}

// MARK: - Approval card

struct ApprovalCard: View {
    let action: String
    @Environment(AgentState.self) private var agent

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 14))
                .foregroundStyle(.orange)
                .frame(width: 52)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 8) {
                Text("Approval needed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)

                Text(action)
                    .font(.system(size: 13))
                    .lineLimit(3)

                HStack(spacing: 8) {
                    Spacer()
                    ActionBtn("Skip", primary: false)  { agent.onReject?()  }
                    ActionBtn("Go ahead", primary: true) { agent.onApprove?() }
                }
            }
            .padding(.trailing, 16)
        }
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.07))
    }
}

// MARK: - Clarification card

struct ClarificationCard: View {
    let question: String
    @Environment(AgentState.self) private var agent
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var agent = agent
        HStack(alignment: .top, spacing: 0) {
            Image(systemName: "questionmark.bubble.fill")
                .font(.system(size: 14))
                .foregroundStyle(.blue)
                .frame(width: 52)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 8) {
                Text("Question")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)

                Text(question)
                    .font(.system(size: 13))
                    .lineLimit(4)

                HStack(spacing: 8) {
                    TextField("Answer…", text: $agent.clarificationDraft)
                        .font(.system(size: 13))
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .onSubmit { answer() }

                    ActionBtn("Send", primary: true) { answer() }
                        .disabled(agent.clarificationDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.trailing, 16)
        }
        .padding(.vertical, 12)
        .background(Color.blue.opacity(0.05))
        .onAppear { focused = true }
    }

    private func answer() {
        let t = agent.clarificationDraft.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        agent.onAnswerClarification?(t)
    }
}

// MARK: - Done / error view

struct DoneView: View {
    let summary: String
    let isError: Bool
    @Environment(AgentState.self) private var agent

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ZStack {
                Circle()
                    .fill(isError ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                    .frame(width: 32, height: 32)
                Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(isError ? Color.red : Color.green)
            }
            .frame(width: 52)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(isError ? "Failed" : "Done")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isError ? Color.red : Color.green)

                Text(summary)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.trailing, 8)

            Spacer(minLength: 0)

            CloseBtn { agent.onCancel?() }
        }
        .padding(.vertical, 14)
    }
}

// MARK: - Shared close button

private struct CloseBtn: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .padding(.trailing, 14)
    }
}

// MARK: - Shared pill button

private struct ActionBtn: View {
    let label:   String
    let primary: Bool
    let action:  () -> Void

    init(_ label: String, primary: Bool, action: @escaping () -> Void) {
        self.label   = label
        self.primary = primary
        self.action  = action
    }

    var body: some View {
        Button(label, action: action)
            .font(.system(size: 12, weight: .medium))
            .buttonStyle(PillButtonStyle(primary: primary))
    }
}

private struct PillButtonStyle: ButtonStyle {
    let primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(primary ? Color.purple : Color.primary.opacity(0.08)))
            .foregroundStyle(primary ? Color.white : Color.primary)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
