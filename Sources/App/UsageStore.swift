import AppKit
import Combine
import ServiceManagement
import UsageCore

struct Preferences: Equatable {
    var interval = 5
    var showClaude = true
    var showCodex = true
    var showPercentInMenu = false
    var codexPath = ""
    var launchAtLogin = false

    static func load() -> Self {
        let defaults = UserDefaults.standard
        var value = Self()
        let interval = defaults.integer(forKey: "usage.refreshMinutes")
        value.interval = [5, 10, 15, 30].contains(interval) ? interval : 5
        value.showClaude = defaults.object(forKey: "usage.showClaude") as? Bool ?? true
        value.showCodex = defaults.object(forKey: "usage.showCodex") as? Bool ?? true
        value.showPercentInMenu = defaults.bool(forKey: "usage.menuPercent")
        value.codexPath = defaults.string(forKey: "usage.codexPath") ?? ""
        value.launchAtLogin = SMAppService.mainApp.status == .enabled
        return value
    }

    func persist() {
        let defaults = UserDefaults.standard
        defaults.set(interval, forKey: "usage.refreshMinutes")
        defaults.set(showClaude, forKey: "usage.showClaude")
        defaults.set(showCodex, forKey: "usage.showCodex")
        defaults.set(showPercentInMenu, forKey: "usage.menuPercent")
        defaults.set(codexPath, forKey: "usage.codexPath")
    }
}

struct ProviderState {
    var snapshot: UsageSnapshot?
    var error: String?
    var loading = false
    var nextAllowedRefresh = Date.distantPast
}

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var preferences: Preferences
    @Published private(set) var states: [Provider: ProviderState] = [.claude: ProviderState(), .codex: ProviderState()]
    private let claudeConnection = ClaudeConnection()
    private let settingsWindow = SettingsWindowController()
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private let preview: Bool
    private var requestIDs: [Provider: UUID] = [:]

    init(preview: Bool = false) {
        self.preview = preview
        preferences = preview ? Preferences() : Preferences.load()
        if preview {
            states[.claude]?.snapshot = UsageSnapshot(windows: [
                UsageWindow(id: "five_hour", title: "5-hour session", usedPercent: 34, resetsAt: Date().addingTimeInterval(7560)),
                UsageWindow(id: "seven_day", title: "Weekly · all models", usedPercent: 61, resetsAt: Date().addingTimeInterval(221400))
            ], plan: "Max")
            states[.codex]?.snapshot = UsageSnapshot(windows: [
                UsageWindow(id: "codex.primary", title: "5-hour session", usedPercent: 18, resetsAt: Date().addingTimeInterval(10800)),
                UsageWindow(id: "codex.secondary", title: "Weekly", usedPercent: 43, resetsAt: Date().addingTimeInterval(352800))
            ], plan: "Pro")
            return
        }
        timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshIfDue() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshIfDue() }
        }
        Task { await refreshAll() }
    }

    deinit {
        timer?.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    var visibleProviders: [Provider] {
        Provider.allCases.filter { $0 == .claude ? preferences.showClaude : preferences.showCodex }
    }
    var isLoading: Bool { visibleProviders.contains { states[$0]?.loading == true } }
    var hasErrors: Bool { visibleProviders.contains { states[$0]?.error != nil } }
    var menuTitle: String {
        guard preferences.showPercentInMenu else { return "" }
        return visibleProviders.map { provider in
            let value = states[provider]?.snapshot?.windows.first.map { "\(Int($0.usedPercent.rounded()))%" } ?? "—"
            return "\(provider == .claude ? "C" : "O") \(value)"
        }.joined(separator: "  ")
    }

    func save(_ draft: Preferences) async throws {
        guard draft.showClaude || draft.showCodex else { throw UsageError.message("Choose at least one provider.") }
        guard [5, 10, 15, 30].contains(draft.interval) else { throw UsageError.message("Choose a valid refresh interval.") }
        if !draft.codexPath.isEmpty, CodexLocator.find(override: draft.codexPath) == nil {
            throw UsageError.message("The selected Codex executable could not be found.")
        }
        if draft.launchAtLogin != preferences.launchAtLogin {
            if draft.launchAtLogin { try SMAppService.mainApp.register() }
            else { try await SMAppService.mainApp.unregister() }
        }
        let pathChanged = draft.codexPath != preferences.codexPath
        preferences = draft
        preferences.persist()
        if pathChanged {
            requestIDs[.codex] = UUID()
            states[.codex] = ProviderState()
        }
        Task { await refreshAll() }
    }

    func showSettings() {
        settingsWindow.show(store: self)
    }

    func connectClaude() {
        guard !preview else { return }
        claudeConnection.show { [weak self] snapshot in
            guard let self else { return }
            self.requestIDs[.claude] = UUID()
            self.states[.claude] = ProviderState(snapshot: snapshot, nextAllowedRefresh: Date().addingTimeInterval(60))
        }
    }

    func refreshAll() async {
        async let claude: Void = refresh(.claude)
        async let codex: Void = refresh(.codex)
        _ = await (claude, codex)
    }

    func refreshIfDue() async {
        for provider in visibleProviders {
            let last = states[provider]?.snapshot?.fetchedAt ?? .distantPast
            if Date().timeIntervalSince(last) >= Double(preferences.interval * 60) {
                Task { await refresh(provider) }
            }
        }
    }

    private func refresh(_ provider: Provider) async {
        guard !preview, visibleProviders.contains(provider), states[provider]?.loading != true,
              Date() >= (states[provider]?.nextAllowedRefresh ?? .distantPast) else { return }
        states[provider]?.loading = true
        let requestID = UUID()
        requestIDs[provider] = requestID
        // Avoid repeated clicks issuing bursts of account requests.
        states[provider]?.nextAllowedRefresh = Date().addingTimeInterval(60)
        let path = preferences.codexPath
        defer {
            if requestIDs[provider] == requestID { states[provider]?.loading = false }
        }
        do {
            let result: UsageSnapshot
            switch provider {
            case .claude:
                if claudeConnection.isConnected { result = try await claudeConnection.fetch() }
                else { result = try await ClaudeClient().fetch() }
            case .codex:
                guard let executable = CodexLocator.find(override: path) else {
                    throw UsageError.message("Codex wasn't found. Install Codex or choose its executable in Settings, then sign in with ChatGPT.")
                }
                result = try await CodexClient.fetch(executable: executable)
            }
            guard requestIDs[provider] == requestID else { return }
            states[provider]?.snapshot = result
            states[provider]?.error = nil
        } catch {
            guard requestIDs[provider] == requestID else { return }
            states[provider]?.error = (error as? UsageError)?.localizedDescription
                ?? (error is DecodingError ? "The usage response format changed. Open the provider's usage page to check your limits." : error.localizedDescription)
            states[provider]?.nextAllowedRefresh = Date().addingTimeInterval(Double(preferences.interval * 60))
            if case UsageError.throttled(let date) = error { states[provider]?.nextAllowedRefresh = date }
        }
    }
}
