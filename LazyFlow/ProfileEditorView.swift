import SwiftUI
import AppKit

// MARK: - Profiles Page

struct ProfilesListView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedID:  String?
    @State private var showAddSheet = false
    @State private var searchText = ""

    private var store: AppProfileStore { appState.profileStore }
    private var sorted: [AppProfile] {
        store.profiles.values
            .filter {
                searchText.isEmpty
                    || $0.displayName.localizedCaseInsensitiveContains(searchText)
                    || $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .onAppear {
            if selectedID == nil { selectedID = sorted.first?.bundleIdentifier }
        }
        .onChange(of: store.lastCreatedBundleIdentifier) { (_: String?, id: String?) in
            if let id { selectedID = id }
        }
        .sheet(isPresented: $showAddSheet) {
            AddProfileSheet(
                isPresented: $showAddSheet,
                existingIDs: Set(store.profiles.keys)
            ) { bundleID, name in
                let p = AppProfile(bundleIdentifier: bundleID, displayName: name,
                                   tone: AppProfile.defaultTone(for: bundleID))
                store.upsert(p)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Profiles")
                    .font(.headline)
                Spacer()
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
                .lazyFlowGlassButton()
                .controlSize(.small)
                .help("Add profile")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 10)
                .padding(.bottom, 9)

            Divider()

            if sorted.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "app.badge")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No profiles yet")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Text("profiles are created when you dictate in an app")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding(.horizontal, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sorted) { profile in
                            ProfileSidebarRow(
                                profile: profile,
                                isSelected: selectedID == profile.bundleIdentifier
                            ) {
                                selectedID = profile.bundleIdentifier
                            }
                            .contextMenu {
                                Button("Delete Profile", role: .destructive) {
                                    deleteProfile(profile.bundleIdentifier)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 210)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selectedID, let profile = store.profile(for: id) {
            ProfileDetailView(
                profile: Binding(
                    get: { store.profile(for: id) ?? profile },
                    set: { store.upsert($0) }
                ),
                onDelete: { deleteProfile(id) }
            )
        } else {
            ContentUnavailableView(
                "No Profile Selected",
                systemImage: "app.badge",
                description: Text("select an app or add a profile")
            )
        }
    }

    private func deleteProfile(_ id: String) {
        store.delete(bundleIdentifier: id)
        if selectedID == id {
            selectedID = sorted.first(where: { $0.bundleIdentifier != id })?.bundleIdentifier
        }
    }
}

// MARK: - Sidebar Row

struct ProfileSidebarRow: View {
    let profile:    AppProfile
    let isSelected: Bool
    let onTap:      () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                AppIconView(bundleIdentifier: profile.bundleIdentifier)
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(profile.postProcessingEnabled ? profile.tone.displayName : "Minimal")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - App Icon
// Cached like AppBundleIcon — NSWorkspace filesystem lookups must not run on every render.

struct AppIconView: View {
    let bundleIdentifier: String
    @State private var cachedIcon: NSImage?

    var body: some View {
        Image(nsImage: cachedIcon ?? placeholder)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .task(id: bundleIdentifier) { cachedIcon = resolveIcon() }
    }

    private func resolveIcon() -> NSImage {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
           let icon = running.icon { return icon }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return placeholder
    }

    private var placeholder: NSImage {
        NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    }
}

// MARK: - Profile Detail

struct ProfileDetailView: View {
    @Binding var profile: AppProfile
    let onDelete: () -> Void

    @State private var pendingInstructions = ""
    @State private var instructionsDirty   = false
    @State private var drafts:             [String: String] = [:]
    @State private var newVocabWord        = ""
    @FocusState private var vocabFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if profile.postProcessingEnabled {
                    toneSection
                    formattingSection
                    vocabularySection
                    instructionsSection
                }
                Spacer(minLength: 16)
            }
            .padding(24)
        }
        .onAppear { pendingInstructions = drafts[profile.id] ?? profile.customInstructions
                    instructionsDirty   = drafts[profile.id].map { $0 != profile.customInstructions } ?? false }
        .onChange(of: profile.id) { oldID, _ in
            // Preserve unsaved edit for the profile we're leaving
            if instructionsDirty { drafts[oldID] = pendingInstructions }
            // Restore draft (if any) for the newly selected profile
            let draft           = drafts[profile.id]
            pendingInstructions = draft ?? profile.customInstructions
            instructionsDirty   = draft.map { $0 != profile.customInstructions } ?? false
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            AppIconView(bundleIdentifier: profile.bundleIdentifier)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayName).font(.title2.bold())
                Text(profile.bundleIdentifier).font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Toggle("Cleanup", isOn: Binding(
                get: { profile.postProcessingEnabled },
                set: { on in
                    profile.postProcessingEnabled = on
                    if on && profile.tone == .minimal { profile.tone = .formal }
                }
            ))
            .toggleStyle(.switch)

            Button(role: .destructive) { onDelete() } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Delete this profile")
        }
    }

    // MARK: Tone

    private var toneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tone")
                .font(.headline)

            Picker("Tone", selection: $profile.tone) {
                ForEach(TonePreset.allCases) { preset in
                    Label(preset.displayName, systemImage: preset.icon)
                        .tag(preset)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .onChange(of: profile.tone) { _, tone in
                profile.postProcessingEnabled = tone != .minimal
            }

            Text(profile.tone.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    // MARK: Formatting Toggles

    private var formattingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Formatting")
                .font(.headline)

            if profile.tone == .code || profile.tone == .technical {
                Text("Lowercase and filler-word options are not compatible with \(profile.tone.displayName) tone.")
                    .font(.caption2).foregroundStyle(.orange)
            }
            if profile.tone == .formal {
                Text("Keep filler words is not compatible with Formal tone.")
                    .font(.caption2).foregroundStyle(.orange)
            }

            VStack(spacing: 0) {
                FormattingToggleRow("Preserve line breaks",  "Keep paragraph structure",         isOn: $profile.formattingOptions.preserveLineBreaks)
                Divider().padding(.leading, 12)
                FormattingToggleRow("Bulletize",             "Convert items to a bulleted list",  isOn: $profile.formattingOptions.bulletize)
                Divider().padding(.leading, 12)
                FormattingToggleRow("Lowercase",             "Output everything in lowercase",    isOn: $profile.formattingOptions.lowercase)
                    .disabled(profile.tone == .code || profile.tone == .technical)
                Divider().padding(.leading, 12)
                FormattingToggleRow("Stronger punctuation",  "Add commas, em-dashes, semicolons", isOn: $profile.formattingOptions.strongerPunctuation)
                Divider().padding(.leading, 12)
                FormattingToggleRow("Keep filler words",     "Preserve um, uh, like, you know",   isOn: $profile.formattingOptions.keepFillerWords)
                    .disabled(profile.tone == .formal || profile.tone == .code || profile.tone == .technical)
            }
        }
    }

    // MARK: Vocabulary

    private var vocabularySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Protected terms")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("preserved exactly in transcription and cleanup")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("Add term…", text: $newVocabWord)
                        .textFieldStyle(.roundedBorder)
                        .focused($vocabFocused)
                        .onSubmit { addWord() }
                    Button("Add", action: addWord)
                        .disabled(newVocabWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !profile.vocabulary.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(profile.vocabulary.sorted(by: {
                            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                        }), id: \.self) { word in
                            VocabChip(word: word) { profile.vocabulary.removeAll { $0 == word } }
                        }
                    }
                }
            }
        }
    }

    // MARK: Custom Instructions

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Instructions")
                .font(.headline)
            Text("applied after tone and formatting")
                .font(.caption).foregroundStyle(.secondary)

            TextEditor(text: $pendingInstructions)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                .onChange(of: pendingInstructions) { _, val in
                    instructionsDirty = val != profile.customInstructions
                }

            if instructionsDirty {
                HStack {
                    Spacer()
                    Button("Revert") {
                        pendingInstructions = profile.customInstructions
                        drafts.removeValue(forKey: profile.id)
                        instructionsDirty   = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Save") {
                        profile.customInstructions = pendingInstructions
                        drafts.removeValue(forKey: profile.id)
                        instructionsDirty          = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    private func addWord() {
        let w = newVocabWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty,
              !profile.vocabulary.contains(where: {
                  $0.caseInsensitiveCompare(w) == .orderedSame
              }) else { return }
        profile.vocabulary.append(w)
        newVocabWord = ""
    }
}

// MARK: - Formatting Toggle Row

struct FormattingToggleRow: View {
    let label:  String
    let detail: String
    @Binding var isOn: Bool

    init(_ label: String, _ detail: String, isOn: Binding<Bool>) {
        self.label  = label
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.body)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Vocab Chip

struct VocabChip: View {
    let word:     String
    let onRemove: () -> Void
    var body: some View {
        HStack(spacing: 4) {
            Text(word).font(.caption)
            Button(action: onRemove) { Image(systemName: "xmark").font(.caption2) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, curRowWidth: CGFloat = 0, maxRowWidth: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 {
                maxRowWidth = max(maxRowWidth, curRowWidth - spacing)
                x = 0; y += rowH + spacing; rowH = 0; curRowWidth = 0
            }
            rowH = max(rowH, s.height)
            x += s.width + spacing
            curRowWidth += s.width + spacing
        }
        maxRowWidth = max(maxRowWidth, curRowWidth - spacing)
        return CGSize(width: proposal.width ?? maxRowWidth, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            rowH = max(rowH, s.height); x += s.width + spacing
        }
    }
}

// MARK: - Add Profile Sheet

struct AddProfileSheet: View {
    @Binding var isPresented: Bool
    let existingIDs: Set<String>
    let onAdd: (String, String) -> Void

    enum InputMode { case picker, manual }

    @State private var inputMode:    InputMode = .picker
    @State private var selectedApp:  RunningAppInfo?
    @State private var bundleID = ""
    @State private var name     = ""

    private var runningApps: [RunningAppInfo] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningAppInfo? in
                guard let bid  = app.bundleIdentifier,
                      let name = app.localizedName else { return nil }
                return RunningAppInfo(bundleIdentifier: bid, displayName: name, icon: app.icon)
            }
            .filter { !existingIDs.contains($0.bundleIdentifier) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var trimmedID:   String { bundleID.trimmingCharacters(in: .whitespaces) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var isDuplicate: Bool   { existingIDs.contains(trimmedID) }

    private var canAdd: Bool {
        switch inputMode {
        case .picker: return selectedApp != nil
        case .manual: return !trimmedID.isEmpty && !trimmedName.isEmpty && !isDuplicate
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add App Profile").font(.headline)

            Picker("", selection: $inputMode) {
                Text("Running Apps").tag(InputMode.picker)
                Text("Manual Entry").tag(InputMode.manual)
            }
            .pickerStyle(.segmented)

            if inputMode == .picker {
                pickerContent
            } else {
                manualContent
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Add") {
                    switch inputMode {
                    case .picker:
                        if let app = selectedApp { onAdd(app.bundleIdentifier, app.displayName) }
                    case .manual:
                        onAdd(trimmedID, trimmedName)
                    }
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdd)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    @ViewBuilder
    private var pickerContent: some View {
        if runningApps.isEmpty {
            Text("No eligible apps currently running.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 32)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(runningApps) { app in
                        RunningAppRow(
                            app: app,
                            isSelected: selectedApp?.bundleIdentifier == app.bundleIdentifier
                        ) { selectedApp = app }
                        if app.id != runningApps.last?.id {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
            }
            .frame(maxHeight: 260)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 0.5))
        }
    }

    @ViewBuilder
    private var manualContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("App name (e.g. Notion)", text: $name)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Bundle ID (e.g. notion.id.Notion)", text: $bundleID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                if isDuplicate {
                    Label("A profile for this bundle ID already exists.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Text("Find the bundle ID in Terminal:\n`osascript -e 'id of app \"AppName\"'`")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Running App Models

struct RunningAppInfo: Identifiable {
    let bundleIdentifier: String
    let displayName:      String
    let icon:             NSImage?
    var id: String { bundleIdentifier }
}

struct RunningAppRow: View {
    let app:        RunningAppInfo
    let isSelected: Bool
    let onTap:      () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Group {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "app.dashed")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 1) {
                    Text(app.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(app.bundleIdentifier)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
