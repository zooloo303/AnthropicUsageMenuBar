import Foundation

@MainActor
final class OpenAIService: ObservableObject {
    @Published var currentUsage: OpenAIUsageSnapshot? = nil
    @Published var isLoading = false
    @Published var lastError: String? = nil
    @Published var lastUpdated: Date? = nil

    private var store: SettingsStore?

    init(store: SettingsStore? = nil) {
        self.store = store
    }

    func configure(store: SettingsStore) {
        self.store = store
        // OpenAI does not provide a public usage report endpoint for API keys without organization.
        // We provide a manual placeholder and optional stub for future endpoint.
        if store.openAIKey.isEmpty {
            currentUsage = nil
        } else {
            // Placeholder: assume zero until user implements
            let now = Date()
            let cal = Calendar.current
            let start = cal.date(from: cal.dateComponents([.year, .month], from: now))!
            currentUsage = OpenAIUsageSnapshot(tokensUsed: 0, costUSD: 0, periodStart: start, periodEnd: now)
        }
    }

    func refresh() async {
        guard store?.openAIKey != nil else { return }
        isLoading = true
        defer { isLoading = false }
        // TODO: integrate OpenAI usage API if available
        lastUpdated = Date()
    }
}
