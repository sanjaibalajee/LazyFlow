import SwiftUI
import AppKit
import Combine

struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @State private var selection: SidebarItem? = .activity
    @AppStorage("lazyflow_show_monitor") private var showMonitor = false
    @State private var monitor = SystemMonitor()

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationTitle("LazyFlow")
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MonitorToggleButton(isOn: $showMonitor)
            }
        } detail: {
            switch selection {
            case .activity, nil:  ActivityView()
            case .profiles:       ProfilesListView()
            case .snippets:       SnippetsView()
            case .knowledgeBase:  KnowledgeBaseView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        // The monitor is a safe-area inset rather than a sibling in a VStack. Wrapping the
        // split view in a stack detached it from the window chrome, and detail content then
        // scrolled up underneath the title bar instead of starting below it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showMonitor {
                SystemMonitorPanel()
                    .environment(monitor)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showMonitor)
        .environment(monitor)
        // The monitor polls IOKit and mach counters every 2s. It used to run for as long as
        // the window was open; now it only samples while the panel is actually visible.
        .task(id: showMonitor) {
            if showMonitor { monitor.start() } else { monitor.stop() }
        }
        .onDisappear { monitor.stop() }
        // Owned here rather than per-row so the menu bar can request a correction too.
        .sheet(item: $appState.pendingCorrection) { entry in
            CorrectionSheet(entry: entry,
                            correctionStore: appState.correctionStore,
                            transcriptStore: appState.transcriptStore)
        }
    }
}

// MARK: - Sidebar

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case activity      = "Activity"
    case profiles      = "App Profiles"
    case snippets      = "Voice Snippets"
    case knowledgeBase = "Knowledge Base"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .activity:      return "square.stack.3d.up"
        case .profiles:      return "app.badge"
        case .snippets:      return "text.badge.plus"
        case .knowledgeBase: return "brain"
        }
    }
}

// MARK: - Activity

struct ActivityView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText   = ""
    @State private var appFilter:   String?  // bundle identifier, nil = all apps
    @State private var showClearConfirm = false

    private var items: [TranscriptEntry] {
        appState.history.filter { entry in
            if let appFilter, entry.bundleIdentifier != appFilter { return false }
            guard !searchText.isEmpty else { return true }
            return entry.text.localizedCaseInsensitiveContains(searchText)
                || (entry.appName?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var grouped: [(key: String, items: [TranscriptEntry])] {
        ActivityView.group(items)
    }

    /// Distinct apps present in history, for the filter menu.
    private var knownApps: [(id: String, name: String)] {
        var seen = Set<String>()
        return appState.history.compactMap { entry -> (id: String, name: String)? in
            guard let id = entry.bundleIdentifier, seen.insert(id).inserted else { return nil }
            return (id: id, name: entry.appName ?? id)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let error = appState.errorMessage {
                    ErrorBanner(message: error) { appState.clearError() }
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                statsRow
                InferenceStatusCard()
                feedSection
            }
            .padding(24)
        }
        .confirmationDialog("Delete all transcripts?", isPresented: $showClearConfirm) {
            Button("Delete All", role: .destructive) { appState.transcriptStore.deleteAll() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes every transcript from your local history. It can't be undone.")
        }
    }

    // ── Header ────────────────────────────────────────────────────────────

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.largeTitle).bold()
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !appState.history.isEmpty {
                Menu {
                    Button("Delete All Transcripts…", role: .destructive) {
                        showClearConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }

    private var subtitle: String {
        let stats = self.stats
        guard stats.total > 0 else {
            return "Everything you dictate will show up here."
        }
        return stats.today > 0
            ? "\(stats.today) transcript\(stats.today == 1 ? "" : "s") today · \(stats.words.formatted()) words all time."
            : "Everything you've dictated, searchable in one place."
    }

    // ── Stats ─────────────────────────────────────────────────────────────

    private var statsRow: some View {
        let stats = self.stats
        return HStack(spacing: 12) {
            StatCard(icon: "mic.fill",   color: .blue,
                     value: "\(stats.today)",           label: "Today")
            StatCard(icon: "calendar",   color: .purple,
                     value: "\(stats.week)",            label: "This week")
            StatCard(icon: "doc.text",   color: .green,
                     value: "\(stats.total)",           label: "Transcripts")
            StatCard(icon: "textformat", color: .orange,
                     value: stats.words.formatted(),    label: "Words")
        }
    }

    // ── Feed ──────────────────────────────────────────────────────────────

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Transcripts")
                    .font(.headline)

                if items.count != appState.history.count {
                    Text("\(items.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary.opacity(0.6), in: Capsule())
                }

                Spacer()

                if !knownApps.isEmpty {
                    appFilterMenu
                }

                SearchField(text: $searchText)
                    .frame(maxWidth: 200)
            }

            if appState.history.isEmpty {
                emptyState
            } else if items.isEmpty {
                noResults
            } else {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(grouped, id: \.key) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Text(group.key)
                                    .font(.subheadline).bold()
                                    .foregroundStyle(.secondary)
                                Text("\(group.items.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            VStack(spacing: 0) {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, entry in
                                    if index != 0 {
                                        Divider().padding(.leading, 46)
                                    }
                                    TranscriptRow(entry: entry)
                                        .padding(.horizontal, 12)
                                }
                            }
                            .background(.background, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5))
                        }
                    }
                }
            }
        }
    }

    private var appFilterMenu: some View {
        Menu {
            Button {
                appFilter = nil
            } label: {
                if appFilter == nil { Label("All Apps", systemImage: "checkmark") }
                else                { Text("All Apps") }
            }
            Divider()
            ForEach(knownApps, id: \.id) { app in
                Button {
                    appFilter = app.id
                } label: {
                    if appFilter == app.id { Label(app.name, systemImage: "checkmark") }
                    else                   { Text(app.name) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 12))
                Text(appFilter.flatMap { id in knownApps.first { $0.id == id }?.name } ?? "All Apps")
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .foregroundStyle(appFilter == nil ? Color.secondary : Color.accentColor)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("No transcripts yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Hold Right ⌥ to dictate. Your transcripts will appear here.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var noResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text("No matches")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(appFilter == nil
                 ? "Try a different search."
                 : "Nothing here for this app. Try clearing the filter.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            if appFilter != nil || !searchText.isEmpty {
                Button("Clear filters") {
                    appFilter  = nil
                    searchText = ""
                }
                .buttonStyle(.link)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // ── Derived values ────────────────────────────────────────────────────

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 0..<12:  return "Good morning."
        case 12..<17: return "Good afternoon."
        default:      return "Good evening."
        }
    }

    struct Stats {
        var today = 0, week = 0, total = 0, words = 0
    }

    /// All four figures in one pass. These are read several times per render, and the old
    /// per-stat computed properties each walked the full history — the word count also
    /// allocated a substring array per entry, on every keystroke in the search field.
    private var stats: Stats {
        let cal       = Calendar.current
        let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? .distantPast
        var s = Stats()
        for entry in appState.history {
            s.total += 1
            s.words += ActivityView.wordCount(entry.text)
            if entry.date >= weekStart          { s.week  += 1 }
            if cal.isDateInToday(entry.date)    { s.today += 1 }
        }
        return s
    }

    private static func wordCount(_ text: String) -> Int {
        var count  = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                inWord = false
            } else if !inWord {
                inWord = true
                count += 1
            }
        }
        return count
    }

    // Groups items into Today / Yesterday / This Week / month-year buckets, newest first.
    static func group(_ items: [TranscriptEntry]) -> [(key: String, items: [TranscriptEntry])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: items) { item -> String in
            if cal.isDateInToday(item.date)     { return "Today" }
            if cal.isDateInYesterday(item.date)  { return "Yesterday" }
            let days = cal.dateComponents([.day], from: item.date, to: Date()).day ?? 0
            if days < 7                          { return "This Week" }
            return item.date.formatted(.dateTime.month(.wide).year())
        }
        let pinned = ["Today", "Yesterday", "This Week"]
        return groups.keys.sorted { a, b in
            let ai = pinned.firstIndex(of: a)
            let bi = pinned.firstIndex(of: b)
            switch (ai, bi) {
            case let (ai?, bi?): return ai < bi
            case (.some, nil):   return true
            case (nil, .some):   return false
            case (nil, nil):
                let da = groups[a]!.map(\.date).max() ?? .distantPast
                let db = groups[b]!.map(\.date).max() ?? .distantPast
                return da > db
            }
        }
        .map { key in (key: key, items: groups[key]!) }
    }
}

// MARK: - Search field

private struct SearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .overlay(
            Capsule().stroke(focused ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1.5)
        )
        .animation(.easeOut(duration: 0.12), value: focused)
        .onTapGesture { focused = true }
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
        .help(isOn ? "Hide the system monitor" : "Show GPU, CPU and memory usage")
    }
}

// MARK: - Inference Status Card

struct InferenceStatusCard: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Inference", systemImage: "cpu").font(.headline)
                Spacer()
                Button { openSettings() } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open Settings")
            }

            HStack(spacing: 0) {
                modelRow(icon: "waveform",
                         label: "STT",
                         backend: appState.sttBackend == .cloud ? nil
                             : LocalSTTService.isDownloaded(appState.localSTTModel) && appState.localSTTOpState == .idle
                                 ? appState.localSTTModel.displayName : nil,
                         cloudLabel: appState.sttModel.replacingOccurrences(of: "whisper-", with: ""),
                         isCloud: appState.sttBackend == .cloud,
                         opState: appState.localSTTOpState,
                         onDownload: { appState.loadLocalSTT(appState.localSTTModel) })

                Divider().frame(height: 32).padding(.horizontal, 12)

                modelRow(icon: "sparkles",
                         label: "LLM",
                         backend: appState.llmBackend == .cloud ? nil
                             : LocalLLMService.isDownloaded(appState.localLLMModel) && appState.localLLMOpState == .idle
                                 ? appState.localLLMModel.displayName : nil,
                         cloudLabel: String(appState.llmModel.split(separator: "-").prefix(3).joined(separator: "-")),
                         isCloud: appState.llmBackend == .cloud,
                         opState: appState.localLLMOpState,
                         onDownload: { appState.loadLocalLLM(appState.localLLMModel) })
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5))
    }

    @ViewBuilder
    private func modelRow(icon: String, label: String, backend: String?,
                          cloudLabel: String, isCloud: Bool,
                          opState: LocalOpState,
                          onDownload: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                if isCloud {
                    Text(cloudLabel).font(.system(size: 12)).foregroundStyle(.secondary)
                } else if case .busy(let p, let s) = opState {
                    VStack(alignment: .leading, spacing: 2) {
                        ProgressView(value: p).tint(.accentColor).frame(width: 80)
                        Text(s).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                } else if case .error(let message) = opState {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .help(message)
                } else if let name = backend, opState == .idle {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text(name).font(.system(size: 12))
                    }
                } else {
                    Button("Download") { onDownload() }
                        .buttonStyle(.bordered).controlSize(.mini)
                }
            }

            if isCloud {
                Image(systemName: "cloud")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let icon:  String
    let color: Color
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Spacer()
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.25), value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5))
    }
}

// MARK: - Knowledge Base

struct KnowledgeBaseView: View {
    @Environment(AppState.self) private var appState

    @State private var drafts: [KBField: String] = [:]

    private var store: KnowledgeStore { appState.knowledgeStore }

    private var filledCount: Int {
        KBField.allCases.filter { !(drafts[$0] ?? "").isEmpty }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Smart Fill Profile", systemImage: "person.text.rectangle")
                            .font(.headline)
                        Spacer()
                        statusPill
                    }
                    Text("Stored locally. Injected into every LLM call so the AI can fill fields and personalise output using your real information.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                VStack(spacing: 0) {
                    ForEach(KBField.allCases, id: \.rawValue) { field in
                        fieldRow(field)
                        if field != KBField.allCases.last {
                            Divider().padding(.leading, 32)
                        }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator, lineWidth: 0.5))

                if store.contextBlock == nil {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Fill in at least one field to activate Smart Fill.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
        }
        .onAppear { syncDrafts() }
    }

    private var statusPill: some View {
        let active = store.contextBlock != nil
        return HStack(spacing: 5) {
            Circle()
                .fill(active ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 6, height: 6)
            Text(active ? "Active · \(filledCount) field\(filledCount == 1 ? "" : "s")" : "Inactive")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(.quaternary.opacity(0.5), in: Capsule())
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
        .padding(.horizontal, 12)
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
    let entry: TranscriptEntry
    @Environment(AppState.self) private var appState
    @State private var copied    = false
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AppIcon(bundleIdentifier: entry.bundleIdentifier)
                .frame(width: 28, height: 28)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.text)
                    .font(.body)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

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
                        .help(entry.date.formatted(date: .abbreviated, time: .shortened))
                }
            }

            Spacer()

            // Row actions stay out of the way until the row is hovered — with a dense feed,
            // always-on buttons on every row read as noise.
            HStack(spacing: 2) {
                rowAction("pencil", help: "Correct this transcript") {
                    appState.pendingCorrection = entry
                }
                rowAction(copied ? "checkmark" : "doc.on.clipboard",
                          help: "Copy to clipboard",
                          tint: copied ? .green : nil) {
                    copy()
                }
                rowAction("trash", help: "Delete transcript") {
                    appState.transcriptStore.delete(entry.id)
                }
            }
            .opacity(isHovered || copied ? 1 : 0)
            // Opacity alone leaves the buttons clickable while invisible — with Delete in
            // the group that turns a stray click into silent data loss.
            .allowsHitTesting(isHovered || copied)
            .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Correct…") { appState.pendingCorrection = entry }
            Button("Copy")     { copy() }
            Divider()
            Button("Delete", role: .destructive) {
                appState.transcriptStore.delete(entry.id)
            }
        }
    }

    private func rowAction(_ symbol: String, help: String,
                           tint: Color? = nil,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
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

    private var trimmed: String {
        corrected.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canSave: Bool { !trimmed.isEmpty && trimmed != entry.text }

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
                    .textSelection(.enabled)
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
                Button(shouldLearn ? "Save & Learn" : "Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear { corrected = entry.text }
    }

    private func save() {
        guard canSave else { dismiss(); return }
        let trimmed = self.trimmed

        transcriptStore.update(entry.withText(trimmed))

        if shouldLearn {
            // Extract only the changed word regions — each becomes its own correction pair.
            // "I asked that guy to confirm" → "I asked Pranav to confirm"
            // stores: heard="that guy", correct="Pranav"  (not the full sentence)
            let pairs = WordDiff.extract(original: entry.text, corrected: trimmed)

            // If pairs is empty only punctuation/casing differs. Don't store a full-sentence
            // correction pair; those never match future transcripts phonetically and would
            // pollute the corrections dictionary.
            for pair in pairs where !pair.heard.isEmpty && !pair.correct.isEmpty {
                correctionStore.add(CorrectionEntry(
                    heard: pair.heard, correct: pair.correct,
                    bundleIdentifier: entry.bundleIdentifier
                ))
            }
        }
        dismiss()
    }
}
