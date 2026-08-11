import SwiftUI

struct SnippetsView: View {
    @Environment(AppState.self) private var appState
    @State private var editingSnippet: VoiceSnippet?
    @State private var showingNewSnippet = false

    private var store: SnippetStore { appState.snippetStore }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                explainer

                if store.snippets.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(store.snippets) { snippet in
                            SnippetCard(snippet: snippet) {
                                editingSnippet = snippet
                            } onDelete: {
                                store.delete(snippet.id)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingNewSnippet) {
            SnippetEditorSheet(
                title: "New voice snippet",
                existing: nil,
                existingTriggers: Set(store.snippets.map { $0.trigger.lowercased() })
            ) { store.upsert($0) }
        }
        .sheet(item: $editingSnippet) { snippet in
            SnippetEditorSheet(
                title: "Edit voice snippet",
                existing: snippet,
                existingTriggers: Set(store.snippets
                    .filter { $0.id != snippet.id }
                    .map { $0.trigger.lowercased() })
            ) { store.upsert($0) }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Voice snippets")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Say a short trigger. LazyFlow inserts the saved text exactly as written.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showingNewSnippet = true
            } label: {
                Label("New snippet", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var explainer: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: "quote.bubble.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text("“my calendar link” → your full scheduling URL")
                    .font(.system(size: 13, weight: .semibold))
                Text("Triggers match whole phrases, ignore case, and expand after AI cleanup so formatting stays untouched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text("Save something you type often")
                .font(.title3.weight(.semibold))
            Text("Signatures, addresses, meeting links, support replies—anything can become a voice shortcut.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Create your first snippet") { showingNewSnippet = true }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 58)
        .background(Color.secondary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct SnippetCard: View {
    let snippet: VoiceSnippet
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onEdit) {
                HStack(alignment: .top, spacing: 14) {
                Text(snippet.trigger)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.1), in: Capsule())
                    .frame(width: 170, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 7)

                Text(snippet.expansion)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(hovered ? 1 : 0.25)
            .help("Delete snippet")
        }
        .padding(14)
        .background(
            hovered ? Color.primary.opacity(0.055) : Color.secondary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hovered = $0 }
    }
}

private struct SnippetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let existing: VoiceSnippet?
    let existingTriggers: Set<String>
    let onSave: (VoiceSnippet) -> Void

    @State private var trigger: String
    @State private var expansion: String

    init(
        title: String,
        existing: VoiceSnippet?,
        existingTriggers: Set<String>,
        onSave: @escaping (VoiceSnippet) -> Void
    ) {
        self.title = title
        self.existing = existing
        self.existingTriggers = existingTriggers
        self.onSave = onSave
        _trigger = State(initialValue: existing?.trigger ?? "")
        _expansion = State(initialValue: existing?.expansion ?? "")
    }

    private var trimmedTrigger: String {
        trigger.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedTrigger.isEmpty
            && !expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !existingTriggers.contains(trimmedTrigger.lowercased())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.bold))
                Text("The expansion is inserted verbatim, including capitalization and line breaks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Trigger phrase").font(.subheadline.weight(.semibold))
                TextField("my calendar link", text: $trigger)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Expansion").font(.subheadline.weight(.semibold))
                TextEditor(text: $expansion)
                    .font(.system(.body, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 130)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.08))
                    }
            }

            if existingTriggers.contains(trimmedTrigger.lowercased()) {
                Label("That trigger already exists.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save snippet") {
                    let snippet = VoiceSnippet(
                        id: existing?.id ?? UUID().uuidString,
                        trigger: trimmedTrigger,
                        expansion: expansion,
                        createdAt: existing?.createdAt ?? Date()
                    )
                    onSave(snippet)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
