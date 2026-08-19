import SwiftUI

struct PermissionsSetupView: View {
    @Environment(AppState.self) private var appState
    private var permissions: PermissionsService { appState.permissions }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()

            Image(systemName: "waveform.and.mic")
                .font(.system(size: 42, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 8) {
                Text("set up lazyflow")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Text("two macos permissions are required for system-wide dictation.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            PermissionStatusList()

            HStack(spacing: 12) {
                Button("setup permissions") {
                    NotificationCenter.default.post(name: .lazyflowOpenSetup, object: nil)
                }
                .lazyFlowGlassButton(prominent: true)
                .controlSize(.large)

                Button("open privacy settings") {
                    permissions.openSettings(permissions.microphone ? .accessibility : .microphone)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Text("after granting accessibility, return to lazyflow. the right-option shortcut activates automatically.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding(.horizontal, 52)
        .frame(maxWidth: 680, maxHeight: .infinity, alignment: .leading)
        .task { permissions.refresh() }
    }
}

struct PermissionsSettingsSection: View {
    @Environment(AppState.self) private var appState
    private var permissions: PermissionsService { appState.permissions }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Permissions", systemImage: "lock.shield")
                    .font(.headline)

                Spacer()

                if permissions.coreReady {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            PermissionStatusList(compact: true)

            if !permissions.coreReady {
                Button("Setup Permissions") {
                    NotificationCenter.default.post(name: .lazyflowOpenSetup, object: nil)
                }
                .lazyFlowGlassButton(prominent: true)
                .controlSize(.small)
            }
        }
        .padding(20)
        .task { permissions.refresh() }
    }
}

private struct PermissionStatusList: View {
    @Environment(AppState.self) private var appState
    var compact = false
    private var permissions: PermissionsService { appState.permissions }

    var body: some View {
        VStack(spacing: 0) {
            PermissionStatusRow(
                icon: "mic",
                title: "microphone",
                detail: "capture speech for transcription",
                isGranted: permissions.microphone,
                compact: compact
            )

            Divider().padding(.leading, 36)

            PermissionStatusRow(
                icon: "keyboard",
                title: "accessibility",
                detail: "detect right option and insert text",
                isGranted: permissions.accessibility,
                compact: compact
            )
        }
    }
}

private struct PermissionStatusRow: View {
    let icon: String
    let title: String
    let detail: String
    let isGranted: Bool
    let compact: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: compact ? 12 : 14, weight: .medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label(isGranted ? "granted" : "required",
                  systemImage: isGranted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.caption)
                .foregroundStyle(isGranted ? Color.green : Color.orange)
        }
        .padding(.vertical, compact ? 7 : 12)
    }
}
