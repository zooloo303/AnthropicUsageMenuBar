import SwiftUI
import UsageCore

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Preferences
    @State private var error: String?
    @State private var saving = false

    init(store: UsageStore) {
        self.store = store
        _draft = State(initialValue: store.preferences)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings").font(.title2.bold())
            Form {
                Section("Show usage for") {
                    Toggle("Claude", isOn: $draft.showClaude)
                    Toggle("Codex", isOn: $draft.showCodex)
                }
                Section("Menu bar") {
                    Picker("Refresh every", selection: $draft.interval) {
                        ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) minutes").tag($0) }
                    }
                    Toggle("Show session percentages beside the icon", isOn: $draft.showPercentInMenu)
                    Toggle("Launch at login", isOn: $draft.launchAtLogin)
                }
                Section("Connections") {
                    Text("Claude uses your Claude Code sign-in. Codex uses your local Codex sign-in with ChatGPT.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("Codex executable (automatic)", text: $draft.codexPath)
                        Button("Choose…") { chooseExecutable() }
                    }
                    if let path = CodexLocator.find(override: draft.codexPath) {
                        Text("Found: \(path.path)").font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(2).truncationMode(.middle).help(path.path)
                    }
                    Text("After signing in again, click Refresh. Keys and passwords are never copied into this app.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            if let error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    saving = true
                    Task {
                        do { try await store.save(draft); dismiss() }
                        catch { self.error = error.localizedDescription; saving = false }
                    }
                }
                .keyboardShortcut(.defaultAction).disabled(saving)
            }
        }
        .padding(20)
        .frame(width: 450, height: 650)
        .background(.regularMaterial)
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.showsHiddenFiles = true
        panel.message = "Choose the Codex executable"
        if panel.runModal() == .OK, let url = panel.url { draft.codexPath = url.path }
    }
}
