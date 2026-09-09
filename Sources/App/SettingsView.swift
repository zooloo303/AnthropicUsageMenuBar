import SwiftUI
import UsageCore

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    private let onClose: () -> Void
    @State private var draft: Preferences
    @State private var error: String?
    @State private var saving = false

    init(store: UsageStore, onClose: @escaping () -> Void) {
        self.store = store
        self.onClose = onClose
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
                    Text("Save a Claude web connection to keep your subscription sign-in between app restarts. Codex uses your local Codex sign-in with ChatGPT.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Connect Claude…") { store.connectClaude() }
                    HStack {
                        TextField("Codex executable", text: $draft.codexPath,
                                  prompt: Text("Find automatically"))
                        Button("Choose…") { chooseExecutable() }
                    }
                    Text("Leave blank to find an installed copy of Codex automatically, including copies installed by Zed or VS Code.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let path = CodexLocator.find(override: draft.codexPath) {
                        Text("Found: \(path.path)").font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(2).truncationMode(.middle).help(path.path)
                    }
                    Text("Refresh never opens a Claude password dialog. Manage your saved sign-in with Connect Claude.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            if let error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("Cancel", action: onClose).keyboardShortcut(.cancelAction)
                Button("Save") {
                    saving = true
                    Task {
                        do { try await store.save(draft); onClose() }
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

/// Settings must outlive the transient MenuBarExtra popup, including when a
/// picker, file dialog, or connection window takes focus.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(store: UsageStore) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 650),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Usage Menu Bar Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(store: store) { [weak self] in
            self?.window?.close()
        })
        self.window = window
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Release the draft so the next opening starts from saved preferences.
        window?.contentView = nil
        window = nil
    }
}
