import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var apiKeyVisible = false

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section("API") {
                HStack {
                    Group {
                        if apiKeyVisible {
                            TextField("Groq API Key", text: $appState.apiKey)
                        } else {
                            SecureField("Groq API Key", text: $appState.apiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    Button {
                        apiKeyVisible.toggle()
                    } label: {
                        Image(systemName: apiKeyVisible ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }
                Text("Get a free key at [groq.com](https://groq.com)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}
