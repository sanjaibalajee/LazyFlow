import SwiftUI
import AppKit

struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @State private var selection: SidebarItem? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationTitle("LazyFlow")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selection {
            case .dashboard, nil: DashboardView()
            case .history:        HistoryView()
            case .profiles:       ProfilesListView()
            case .knowledgeBase:  KnowledgeBaseView()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: - Sidebar

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard     = "Dashboard"
    case history       = "History"
    case profiles      = "App Profiles"
    case knowledgeBase = "Knowledge Base"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard:     return "square.grid.2x2"
        case .history:       return "clock"
        case .profiles:      return "app.badge"
        case .knowledgeBase: return "brain"
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                // Greeting
                VStack(alignment: .leading, spacing: 4) {
                    Text(greeting)
                        .font(.largeTitle).bold()
                    Text("Here's what you've been dictating.")
                        .foregroundStyle(.secondary)
                }

                // Stats
                HStack(spacing: 12) {
                    StatCard(icon: "mic.fill",    color: .blue,
                             value: "\(todayCount)",        label: "Today")
                    StatCard(icon: "calendar",    color: .purple,
                             value: "\(weekCount)",         label: "This week")
                    StatCard(icon: "doc.text",    color: .green,
                             value: "\(appState.history.count)", label: "All time")
                    StatCard(icon: "textformat",  color: .orange,
                             value: "\(totalWords)",        label: "Words")
                }

                // Recent
                if appState.history.isEmpty {
                    emptyState
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Recent").font(.headline)
                            Spacer()
                        }
                        VStack(spacing: 0) {
                            ForEach(appState.history.prefix(8)) { entry in
                                TranscriptRow(entry: entry)
                                if entry.id != appState.history.prefix(8).last?.id {
                                    Divider().padding(.leading, 44)
                                }
                            }
                        }
                        .background(.background, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator, lineWidth: 0.5))
                    }
                }
            }
            .padding(24)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.circle")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No transcripts yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Hold Right ⌥ anywhere to start dictating.\nYour transcripts will appear here.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 0..<12:  return "Good morning."
        case 12..<17: return "Good afternoon."
        default:      return "Good evening."
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

// MARK: - Knowledge Base placeholder

struct KnowledgeBaseView: View {
    var body: some View {
        ContentUnavailableView(
            "Knowledge Base",
            systemImage: "brain",
            description: Text("Personal info for smart form filling — coming in Phase 4.")
        )
    }
}

// MARK: - Transcript Row (shared)

struct TranscriptRow: View {
    let entry: TranscriptEntry
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // App icon
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
    }
}

// MARK: - App icon helper

struct AppBundleIcon: View {
    let bundleIdentifier: String?

    private var icon: NSImage {
        guard let id = bundleIdentifier else { return placeholder }
        // Running app gives the most direct icon access
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first,
           let icon = running.icon {
            return icon
        }
        // Fall back to installed-app file lookup
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return placeholder
    }

    private var placeholder: NSImage {
        NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    }

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
