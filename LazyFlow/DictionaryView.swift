import SwiftUI

struct DictionaryView: View {
    @Environment(AppState.self) private var appState

    @State private var searchText = ""
    @State private var filterScope = Scope.all.rawValue
    @State private var newScope = Scope.global.rawValue
    @State private var newHeard = ""
    @State private var newCorrect = ""
    @State private var editingEntry: CorrectionEntry?
    @State private var pendingDelete: CorrectionEntry?

    private enum Scope: String {
        case all = "__all__"
        case global = "__global__"
    }

    private var profiles: [AppProfile] {
        appState.profileStore.profiles.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private var filteredEntries: [CorrectionEntry] {
        appState.correctionStore.all
            .filter { entry in
                switch filterScope {
                case Scope.all.rawValue:
                    break
                case Scope.global.rawValue:
                    guard entry.bundleIdentifier == nil else { return false }
                default:
                    guard entry.bundleIdentifier == filterScope else { return false }
                }

                guard !searchText.isEmpty else { return true }
                let scopeName = entry.bundleIdentifier.map(appName) ?? "global"
                return entry.heard.localizedCaseInsensitiveContains(searchText)
                    || entry.correct.localizedCaseInsensitiveContains(searchText)
                    || scopeName.localizedCaseInsensitiveContains(searchText)
            }
            .sorted {
                if $0.frequency != $1.frequency { return $0.frequency > $1.frequency }
                return $0.heard.localizedCaseInsensitiveCompare($1.heard) == .orderedAscending
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if appState.correctionStore.all.isEmpty {
                ContentUnavailableView(
                    "Dictionary is empty",
                    systemImage: "text.book.closed",
                    description: Text("add a replacement or learn one by editing a transcript")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredEntries.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredEntries) { entry in
                            DictionaryRow(
                                entry: entry,
                                scopeName: entry.bundleIdentifier.map(appName) ?? "Global",
                                onEdit: { editingEntry = entry },
                                onDelete: { pendingDelete = entry }
                            )

                            if entry.id != filteredEntries.last?.id {
                                Divider().padding(.leading, 20)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search dictionary")
        .sheet(item: $editingEntry) { entry in
            DictionaryEditSheet(
                entry: entry,
                profiles: profiles,
                allEntries: appState.correctionStore.all
            ) { updated in
                appState.correctionStore.update(updated)
            }
        }
        .confirmationDialog(
            "Delete this replacement?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDelete {
                    appState.correctionStore.delete(pendingDelete.id)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dictionary")
                        .font(.largeTitle.bold())
                    Text("exact replacements applied before cleanup")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Scope", selection: $filterScope) {
                    Text("All scopes").tag(Scope.all.rawValue)
                    Text("Global").tag(Scope.global.rawValue)
                    Divider()
                    ForEach(profiles) { profile in
                        Text(profile.displayName).tag(profile.bundleIdentifier)
                    }
                }
                .frame(width: 170)
            }

            HStack(spacing: 8) {
                TextField("heard phrase", text: $newHeard)
                    .onSubmit(addEntry)

                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)

                TextField("replacement", text: $newCorrect)
                    .onSubmit(addEntry)

                Picker("Scope", selection: $newScope) {
                    Text("Global").tag(Scope.global.rawValue)
                    ForEach(profiles) { profile in
                        Text(profile.displayName).tag(profile.bundleIdentifier)
                    }
                }
                .labelsHidden()
                .frame(width: 150)

                Button("Add", action: addEntry)
                    .lazyFlowGlassButton(prominent: true)
                    .disabled(!canAdd)
            }
            .textFieldStyle(.roundedBorder)
            .padding(12)
            .lazyFlowGlass(in: RoundedRectangle(cornerRadius: 14), interactive: true)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var canAdd: Bool {
        !CorrectionEntry.normalizedPhrase(newHeard).isEmpty
            && !CorrectionEntry.normalizedPhrase(newCorrect).isEmpty
    }

    private func addEntry() {
        guard canAdd else { return }
        appState.correctionStore.add(CorrectionEntry(
            heard: newHeard,
            correct: newCorrect,
            bundleIdentifier: newScope == Scope.global.rawValue ? nil : newScope
        ))
        newHeard = ""
        newCorrect = ""
    }

    private func appName(for bundleIdentifier: String) -> String {
        appState.profileStore.profile(for: bundleIdentifier)?.displayName ?? bundleIdentifier
    }
}

private struct DictionaryRow: View {
    let entry: CorrectionEntry
    let scopeName: String
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.heard)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Text(entry.correct)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(scopeName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)

            Text(entry.frequency == 1 ? "1 use" : "\(entry.frequency) uses")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 54, alignment: .trailing)

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Edit replacement")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Delete replacement")
        }
        .padding(.vertical, 10)
    }
}

private struct DictionaryEditSheet: View {
    let entry: CorrectionEntry
    let profiles: [AppProfile]
    let allEntries: [CorrectionEntry]
    let onSave: (CorrectionEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var heard: String
    @State private var correct: String
    @State private var scope: String

    private let globalScope = "__global__"

    init(
        entry: CorrectionEntry,
        profiles: [AppProfile],
        allEntries: [CorrectionEntry],
        onSave: @escaping (CorrectionEntry) -> Void
    ) {
        self.entry = entry
        self.profiles = profiles
        self.allEntries = allEntries
        self.onSave = onSave
        _heard = State(initialValue: entry.heard)
        _correct = State(initialValue: entry.correct)
        _scope = State(initialValue: entry.bundleIdentifier ?? "__global__")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit replacement")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Heard")
                        .foregroundStyle(.secondary)
                    TextField("heard phrase", text: $heard)
                }
                GridRow {
                    Text("Replace with")
                        .foregroundStyle(.secondary)
                    TextField("replacement", text: $correct)
                }
                GridRow {
                    Text("Scope")
                        .foregroundStyle(.secondary)
                    Picker("", selection: $scope) {
                        Text("Global").tag(globalScope)
                        ForEach(profiles) { profile in
                            Text(profile.displayName).tag(profile.bundleIdentifier)
                        }
                        if let id = entry.bundleIdentifier,
                           !profiles.contains(where: { $0.bundleIdentifier == id }) {
                            Text(id).tag(id)
                        }
                    }
                    .labelsHidden()
                }
            }
            .textFieldStyle(.roundedBorder)

            if hasDuplicate {
                Label("an entry with this phrase and scope already exists", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("Save") { save() }
                    .lazyFlowGlassButton(prominent: true)
                    .disabled(!canSave || hasDuplicate)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private var normalizedHeard: String { CorrectionEntry.normalizedPhrase(heard) }
    private var normalizedCorrect: String { CorrectionEntry.normalizedPhrase(correct) }

    private var canSave: Bool {
        !normalizedHeard.isEmpty && !normalizedCorrect.isEmpty
    }

    private var hasDuplicate: Bool {
        let bundleID = scope == globalScope ? nil : scope
        return allEntries.contains {
            $0.id != entry.id
                && $0.bundleIdentifier == bundleID
                && $0.heard.caseInsensitiveCompare(normalizedHeard) == .orderedSame
        }
    }

    private func save() {
        guard canSave, !hasDuplicate else { return }
        var updated = entry
        updated.heard = normalizedHeard
        updated.correct = normalizedCorrect
        updated.bundleIdentifier = scope == globalScope ? nil : scope
        onSave(updated)
        dismiss()
    }
}
