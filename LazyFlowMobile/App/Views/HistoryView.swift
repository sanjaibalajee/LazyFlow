import SwiftUI
import UIKit

struct HistoryView: View {
    @ObservedObject var store: HistoryStore

    @State private var query = ""
    @State private var selectedEntry: MobileHistoryEntry?
    @State private var showingClearConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    ContentUnavailableView(
                        "No dictations yet",
                        systemImage: "text.bubble",
                        description: Text("Finished dictations will appear here, privately on this iPhone.")
                    )
                } else if filteredEntries.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List {
                        ForEach(filteredEntries) { entry in
                            Button {
                                selectedEntry = entry
                            } label: {
                                HistoryRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.delete(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    UIPasteboard.general.string = entry.finalText
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("History")
            .modifier(HistorySearchModifier(enabled: !store.entries.isEmpty, query: $query))
            .toolbar {
                if !store.entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Clear history", systemImage: "trash", role: .destructive) {
                                showingClearConfirmation = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .confirmationDialog(
                "Clear all history?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear history", role: .destructive) { store.clear() }
            } message: {
                Text("This permanently removes every saved dictation from this iPhone.")
            }
            .sheet(item: $selectedEntry) { entry in
                HistoryDetailView(entry: entry)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var filteredEntries: [MobileHistoryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return store.entries }
        return store.entries.filter {
            $0.finalText.localizedCaseInsensitiveContains(trimmed)
                || $0.transcript.localizedCaseInsensitiveContains(trimmed)
        }
    }
}

private struct HistorySearchModifier: ViewModifier {
    var enabled: Bool
    @Binding var query: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $query, prompt: "Search dictations")
        } else {
            content
        }
    }
}

private struct HistoryRow: View {
    let entry: MobileHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.finalText)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(3)

            HStack(spacing: 7) {
                Text(entry.createdAt, format: .relative(presentation: .named))
                Text("·")
                Label(entry.tone.compactTitle, systemImage: entry.tone.symbol)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

private struct HistoryDetailView: View {
    let entry: MobileHistoryEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    detailSection("Final text", text: entry.finalText)
                    if entry.transcript != entry.finalText {
                        detailSection("Original transcript", text: entry.transcript)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pipeline").font(.headline)
                        Label(entry.transcriptionLabel, systemImage: "waveform")
                        Label(entry.rewriteLabel, systemImage: "wand.and.sparkles")
                        Label(entry.tone.title, systemImage: entry.tone.symbol)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .padding(.bottom, 24)
            }
            .navigationTitle(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Copy", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = entry.finalText
                    }
                }
            }
        }
    }

    private func detailSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
