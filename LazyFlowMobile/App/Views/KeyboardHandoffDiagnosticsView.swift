#if DEBUG
import SwiftUI
import UIKit

struct KeyboardHandoffDiagnosticsView: View {
    @State private var events: [KeyboardHandoffDiagnosticEvent] = []
    @State private var copiedDiagnostics = false

    var body: some View {
        Section {
            if events.isEmpty {
                ContentUnavailableView(
                    "No notification attempts yet",
                    systemImage: "bell.badge",
                    description: Text("Request a session from the keyboard, then return here.")
                )
            } else {
                ForEach(events.prefix(10)) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(event.source.rawValue)
                                .font(.caption2.monospaced().weight(.semibold))
                                .foregroundStyle(.tint)
                            Spacer()
                            Text(event.timestamp, style: .time)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        Text(event.message)
                            .font(.footnote.weight(.medium))
                        if !event.details.isEmpty {
                            Text(event.details)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }

            Button {
                UIPasteboard.general.string = KeyboardHandoffDiagnostics.exportText()
                copiedDiagnostics = true
            } label: {
                Label(
                    copiedDiagnostics ? "Diagnostics copied" : "Copy diagnostics",
                    systemImage: copiedDiagnostics ? "checkmark" : "doc.on.doc"
                )
            }
            .disabled(events.isEmpty)

            if !events.isEmpty {
                Button("Clear diagnostics", role: .destructive) {
                    KeyboardHandoffDiagnostics.clear()
                    events = []
                    copiedDiagnostics = false
                }
            }
        } header: {
            Text("Keyboard notification diagnostics")
        } footer: {
            Text("Debug builds show the latest 10 events. Copy diagnostics includes up to 60.")
        }
        .task {
            while !Task.isCancelled {
                events = KeyboardHandoffDiagnostics.recentEvents()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
#endif
