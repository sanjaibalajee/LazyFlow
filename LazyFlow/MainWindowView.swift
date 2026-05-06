import SwiftUI

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
            case .dashboard, nil:
                DashboardView()
            case .history:
                HistoryView()
            case .profiles:
                ProfilesListView()
            case .knowledgeBase:
                KnowledgeBaseView()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: - Sidebar

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard    = "Dashboard"
    case history      = "History"
    case profiles     = "App Profiles"
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
            VStack(alignment: .leading, spacing: 24) {
                Text("Dashboard")
                    .font(.largeTitle).bold()

                // Stats row
                HStack(spacing: 16) {
                    StatCard(title: "Today", value: "\(todayCount)", subtitle: "transcriptions")
                    StatCard(title: "All time", value: "\(appState.history.count)", subtitle: "transcriptions")
                    StatCard(title: "Words", value: "\(totalWords)", subtitle: "processed")
                }

                // Recent
                if !appState.history.isEmpty {
                    Text("Recent")
                        .font(.headline)
                    ForEach(appState.history.prefix(5)) { entry in
                        TranscriptRow(entry: entry)
                    }
                } else {
                    ContentUnavailableView(
                        "No transcripts yet",
                        systemImage: "mic",
                        description: Text("Hold Fn or use the menu bar to start dictating.")
                    )
                }
            }
            .padding(24)
        }
    }

    private var todayCount: Int {
        let calendar = Calendar.current
        return appState.history.filter { calendar.isDateInToday($0.date) }.count
    }

    private var totalWords: Int {
        appState.history.reduce(0) { $0 + $1.text.split(separator: " ").count }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - History

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""

    var filteredHistory: [TranscriptEntry] {
        guard !searchText.isEmpty else { return appState.history }
        return appState.history.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("History")
                    .font(.largeTitle).bold()
                Spacer()
            }
            .padding(24)
            .padding(.bottom, 0)

            Divider()

            if appState.history.isEmpty {
                ContentUnavailableView(
                    "No history",
                    systemImage: "clock",
                    description: Text("Your transcripts will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredHistory) { entry in
                    TranscriptRow(entry: entry)
                }
                .searchable(text: $searchText, prompt: "Search transcripts")
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Placeholder views (filled in later phases)

struct ProfilesListView: View {
    var body: some View {
        ContentUnavailableView(
            "App Profiles",
            systemImage: "app.badge",
            description: Text("Per-app vocabulary and tone settings coming soon.")
        )
    }
}

struct KnowledgeBaseView: View {
    var body: some View {
        ContentUnavailableView(
            "Knowledge Base",
            systemImage: "brain",
            description: Text("Your personal info for smart form filling coming soon.")
        )
    }
}

// MARK: - Shared row

struct TranscriptRow: View {
    let entry: TranscriptEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.text)
                .lineLimit(2)
                .font(.body)
            HStack(spacing: 6) {
                if let app = entry.appName {
                    Text(app)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(entry.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
