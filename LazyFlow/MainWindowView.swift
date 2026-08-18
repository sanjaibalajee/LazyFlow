import SwiftUI
import AppKit
import Combine

struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @State private var selection: SidebarItem? = .dashboard
    @AppStorage("lazyflow_show_monitor") private var showMonitor = false
    @State private var monitor = SystemMonitor()

    var body: some View {
        Group {
            if appState.hasRequiredPermissions {
                mainContent
            } else {
                PermissionsSetupView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.hasRequiredPermissions)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshPermissions()
        }
        .onAppear {
            appState.refreshPermissions()
            monitor.start()
        }
        .onDisappear { monitor.stop() }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                List(SidebarItem.allCases, selection: $selection) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item)
                }
                .listStyle(.sidebar)
                .navigationTitle("LazyFlow")
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    MonitorToggleButton(isOn: $showMonitor)
                }
            } detail: {
                switch selection {
                case .dashboard, nil: DashboardView()
                case .history:        HistoryView()
                case .profiles:       ProfilesListView()
                case .dictionary:     DictionaryView()
                case .knowledgeBase:  KnowledgeBaseView()
                }
            }
            .navigationSplitViewStyle(.balanced)

            if showMonitor {
                SystemMonitorPanel()
                    .environment(monitor)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showMonitor)
        .environment(monitor)
    }
}

// MARK: - Sidebar

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard     = "Home"
    case history       = "History"
    case profiles      = "Profiles"
    case dictionary    = "Dictionary"
    case knowledgeBase = "Personal Context"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard:     return "house"
        case .history:       return "clock"
        case .profiles:      return "slider.horizontal.3"
        case .dictionary:    return "text.book.closed"
        case .knowledgeBase: return "person.text.rectangle"
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                metrics
                Divider()
                PipelineStatusView()
                Divider()

                if appState.history.isEmpty {
                    emptyState
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent")
                            .font(.headline)

                        ForEach(appState.history.prefix(8)) { entry in
                            TranscriptRow(entry: entry)
                                .padding(.vertical, 4)
                            if entry.id != appState.history.prefix(8).last?.id {
                                Divider().padding(.leading, 40)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .frame(maxWidth: 920, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(statusTitle)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                Text(statusSubtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                if appState.isRecording {
                    appState.stopRecording()
                } else if appState.recordingMode != .processing {
                    appState.startRecording()
                }
            } label: {
                Label(
                    appState.isRecording ? "Stop" : "Dictate",
                    systemImage: appState.isRecording ? "stop.fill" : "mic.fill"
                )
                .font(.system(size: 14, weight: .semibold))
                .frame(minWidth: 92)
            }
            .lazyFlowGlassButton(prominent: !appState.isRecording)
            .controlSize(.large)
            .tint(appState.isRecording ? .red : .accentColor)
            .disabled(appState.recordingMode == .processing)
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }

    private var metrics: some View {
        HStack(spacing: 0) {
            Metric(value: "\(todayCount)", label: "today")
            metricDivider
            Metric(value: "\(weekCount)", label: "this week")
            metricDivider
            Metric(value: "\(appState.history.count)", label: "transcripts")
            metricDivider
            Metric(value: totalWords.formatted(), label: "words")
        }
        .padding(.vertical, 4)
    }

    private var metricDivider: some View {
        Divider()
            .frame(height: 28)
            .padding(.horizontal, 22)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.circle")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No transcripts yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("hold right ⌥ anywhere to start dictating")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var statusTitle: String {
        switch appState.recordingMode {
        case .recording:  return "listening"
        case .processing: return "processing"
        case .idle:       return "ready"
        }
    }

    private var statusSubtitle: String {
        switch appState.recordingMode {
        case .recording:  return "release right ⌥ or stop when done"
        case .processing: return "transcribing and applying the active profile"
        case .idle:       return "hold right ⌥ to dictate in any app"
        }
    }

    private var todayCount: Int {
        appState.history.filter { Calendar.current.isDateInToday($0.date) }.count
    }

    private var weekCount: Int {
        appState.history.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .weekOfYear) }.count
    }

    private var totalWords: Int {
        appState.history.reduce(0) { $0 + $1.text.split(separator: " ").count }
    }
}

private struct Metric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Monitor Toggle Button

private struct MonitorToggleButton: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isOn ? "chart.bar.fill" : "chart.bar")
                    .font(.system(size: 12))
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                Text("Monitor")
                    .font(.system(size: 13))
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                Spacer()
                if isOn {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.background)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Pipeline Status

struct PipelineStatusView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 16) {
            Label("Pipeline", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)

            Spacer(minLength: 8)

            modelStatus(
                label: "speech",
                value: appState.sttBackend == .cloud
                    ? appState.sttModel.replacingOccurrences(of: "whisper-", with: "")
                    : appState.localSTTModel.displayName,
                isCloud: appState.sttBackend == .cloud
            )

            Divider().frame(height: 24)

            modelStatus(
                label: "cleanup",
                value: appState.llmBackend == .cloud
                    ? String(appState.llmModel.split(separator: "-").prefix(3).joined(separator: "-"))
                    : appState.localLLMModel.displayName,
                isCloud: appState.llmBackend == .cloud
            )

            Button { openSettings() } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open Settings")
        }
        .padding(.vertical, 2)
    }

    private func modelStatus(label: String, value: String, isCloud: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            HStack(spacing: 5) {
                Image(systemName: isCloud ? "cloud" : "apple.silicon")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .frame(width: 150, alignment: .leading)
    }
}

// MARK: - History

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText   = ""
    @State private var filterApp:   String? = nil

    private var allApps: [String] {
        Array(Set(appState.history.compactMap(\.appName))).sorted()
    }

    private var filtered: [TranscriptEntry] {
        appState.history.filter { entry in
            let matchesSearch = searchText.isEmpty
                || entry.text.localizedCaseInsensitiveContains(searchText)
            let matchesApp = filterApp == nil || entry.appName == filterApp
            return matchesSearch && matchesApp
        }
    }

    private var grouped: [(key: String, entries: [TranscriptEntry])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: filtered) { entry -> String in
            if cal.isDateInToday(entry.date)    { return "Today" }
            if cal.isDateInYesterday(entry.date) { return "Yesterday" }
            let days = cal.dateComponents([.day], from: entry.date, to: Date()).day ?? 0
            if days < 7                          { return "This Week" }
            return entry.date.formatted(.dateTime.month(.wide).year())
        }
        let pinnedOrder = ["Today", "Yesterday", "This Week"]
        // Representative date per section: most-recent entry in that section.
        // Pinned labels always sort before month/year buckets via their index.
        return groups.keys.sorted { a, b in
            let ai = pinnedOrder.firstIndex(of: a)
            let bi = pinnedOrder.firstIndex(of: b)
            switch (ai, bi) {
            case let (ai?, bi?): return ai < bi          // both pinned: preserve fixed order
            case (.some, nil):   return true              // a is pinned, b is not
            case (nil, .some):   return false             // b is pinned, a is not
            case (nil, nil):                              // both are month/year: sort by most-recent entry date
                let da = groups[a]!.map(\.date).max() ?? .distantPast
                let db = groups[b]!.map(\.date).max() ?? .distantPast
                return da > db
            }
        }
        .map { key in (key: key, entries: groups[key]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Text("History")
                    .font(.largeTitle).bold()
                Spacer()
                if !allApps.isEmpty {
                    Picker("App", selection: $filterApp) {
                        Text("All Apps").tag(String?.none)
                        Divider()
                        ForEach(allApps, id: \.self) { app in
                            Text(app).tag(String?.some(app))
                        }
                    }
                    .frame(width: 140)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)

            Divider()

            if appState.history.isEmpty {
                ContentUnavailableView(
                    "No history yet",
                    systemImage: "clock",
                    description: Text("Your transcripts will appear here after your first dictation.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                ContentUnavailableView(
                    "No results",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search term or app filter.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(grouped, id: \.key) { group in
                        Section(group.key) {
                            ForEach(group.entries) { entry in
                                TranscriptRow(entry: entry)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $searchText, prompt: "Search transcripts")
    }
}

// MARK: - Knowledge Base

struct KnowledgeBaseView: View {
    @Environment(AppState.self) private var appState

    @State private var drafts: [KBField: String] = [:]

    private var store: KnowledgeStore { appState.knowledgeStore }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Smart Fill Profile", systemImage: "person.text.rectangle")
                    .font(.headline)
                Text("Stored locally. Injected into every LLM call so the AI can fill fields and personalise output using your real information.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            Divider().padding(.horizontal, 20)

            VStack(spacing: 0) {
                ForEach(KBField.allCases, id: \.rawValue) { field in
                    fieldRow(field)
                    if field != KBField.allCases.last {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .padding(.horizontal, 20)

            if store.contextBlock == nil {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Fill in at least one field to activate Smart Fill.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }

            Spacer(minLength: 0)
        }
        .onAppear { syncDrafts() }
    }

    @ViewBuilder
    private func fieldRow(_ field: KBField) -> some View {
        HStack(spacing: 12) {
            Image(systemName: field.icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)

            Text(field.displayName)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .frame(width: 88, alignment: .leading)

            TextField(field.placeholder, text: binding(for: field))
                .font(.system(size: 13))
                .textFieldStyle(.plain)
                .onChange(of: drafts[field] ?? "") { _, newValue in
                    store.set(field: field, value: newValue)
                }
        }
        .padding(.vertical, 9)
    }

    private func binding(for field: KBField) -> Binding<String> {
        Binding(
            get: { drafts[field] ?? "" },
            set: { drafts[field] = $0 }
        )
    }

    private func syncDrafts() {
        for field in KBField.allCases {
            drafts[field] = store.value(for: field)
        }
    }
}

// MARK: - Transcript Row (shared)

struct TranscriptRow: View {
    let entry:           TranscriptEntry
    @Environment(AppState.self) private var appState
    @State private var copied         = false
    @State private var showCorrection = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AppBundleIcon(bundleIdentifier: entry.bundleIdentifier)
                .frame(width: 28, height: 28)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.text)
                    .font(.body)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    if let app = entry.appName {
                        Text(app)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text(entry.date.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Correct button
            Button { showCorrection = true } label: {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .help("Correct this transcript")

            // Copy button
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.clipboard")
                    .font(.caption)
                    .foregroundStyle(copied ? .green : .secondary)
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .help("Copy to clipboard")
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showCorrection) {
            CorrectionSheet(entry: entry,
                            correctionStore: appState.correctionStore,
                            transcriptStore: appState.transcriptStore)
        }
    }
}

// MARK: - App icon helper
// Icon is resolved once on first appear and cached — NSWorkspace lookups hit the filesystem
// and should not run on every SwiftUI render.

struct AppBundleIcon: View {
    let bundleIdentifier: String?
    @State private var cachedIcon: NSImage?

    var body: some View {
        Image(nsImage: cachedIcon ?? placeholder)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .task(id: bundleIdentifier) { cachedIcon = resolveIcon() }
    }

    private func resolveIcon() -> NSImage {
        guard let id = bundleIdentifier else { return placeholder }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first,
           let icon = running.icon { return icon }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return placeholder
    }

    private var placeholder: NSImage {
        NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    }
}

// MARK: - Correction Sheet

struct CorrectionSheet: View {
    let entry:            TranscriptEntry
    let correctionStore:  CorrectionStore
    let transcriptStore:  TranscriptStore

    @Environment(\.dismiss) private var dismiss
    @State private var corrected  = ""
    @State private var shouldLearn = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Correct Transcript")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Original")
                    .font(.caption).foregroundStyle(.secondary)
                Text(entry.text)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Corrected")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $corrected)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            }

            Toggle(isOn: $shouldLearn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Learn from this correction")
                        .font(.body)
                    Text("Saves only the changed word pairs from this correction (not the full sentence)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("Save & Learn") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(corrected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || corrected == entry.text)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear { corrected = entry.text }
    }

    private func save() {
        let trimmed = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != entry.text else { dismiss(); return }

        transcriptStore.update(entry.withText(trimmed))

        if shouldLearn {
            // Extract only the changed word regions — each becomes its own correction pair.
            // "I asked that guy to confirm" → "I asked Pranav to confirm"
            // stores: heard="that guy", correct="Pranav"  (not the full sentence)
            let pairs = WordDiff.extract(original: entry.text, corrected: trimmed)

            if pairs.isEmpty {
                // No word changes detected — only punctuation/casing differs. Don't store a
                // full-sentence correction pair; those never match future transcripts phonetically
                // and would pollute the corrections dictionary.
            } else {
                for pair in pairs where !pair.heard.isEmpty && !pair.correct.isEmpty {
                    correctionStore.add(CorrectionEntry(
                        heard: pair.heard, correct: pair.correct,
                        bundleIdentifier: entry.bundleIdentifier
                    ))
                }
            }
        }
        dismiss()
    }
}
