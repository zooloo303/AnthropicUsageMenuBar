import Foundation

@MainActor
final class AnthropicService: ObservableObject {
    @Published var currentUsage: AnthropicUsageSummary? = nil
    @Published var isLoading = false
    @Published var lastError: String? = nil
    @Published var lastUpdated: Date? = nil

    private var timer: Timer?
    private var store: SettingsStore?

    init(store: SettingsStore? = nil) {
        self.store = store
    }

    func configure(store: SettingsStore, intervalMinutes: Int) {
        self.store = store
        startTimer(intervalMinutes: intervalMinutes)
        Task { await fetchUsage() }
    }
        startTimer(intervalMinutes: intervalMinutes)
        Task { await fetchUsage() }
    }

    func refresh() async {
        await fetchUsage()
    }

    private func startTimer(intervalMinutes: Int) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(intervalMinutes * 60), repeats: true) { [weak self] _ in
            Task { await self?.fetchUsage() }
        }
    }

    private func fetchUsage() async {
        guard let store = store, !store.anthropicAdminKey.isEmpty else {
            self.currentUsage = nil
            return
        }
        isLoading = true
        defer { isLoading = false }

        let now = Date()
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: startOfMonth)!

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let startingAt = iso.string(from: startOfMonth)
        let endingAt = iso.string(from: endOfMonth)

        var components = URLComponents(string: "https://api.anthropic.com/v1/organizations/usage_report/messages")!
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: startingAt),
            URLQueryItem(name: "ending_at", value: endingAt),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "group_by[]", value: "model")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue(store.anthropicAdminKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("AnthropicUsageMenuBar/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                lastError = "HTTP \(code)"
                return
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let decoded = try decoder.decode(AnthropicUsageResponse.self, from: data)
            let totalCost = decoded.data.compactMap { $0.cost }.reduce(0, +)
            let totalInput = decoded.data.compactMap { $0.inputTokens }.reduce(0, +)
            let totalOutput = decoded.data.compactMap { $0.outputTokens }.reduce(0, +)
            currentUsage = AnthropicUsageSummary(
                periodStart: startOfMonth,
                periodEnd: endOfMonth,
                totalCostUSD: totalCost,
                totalInputTokens: totalInput,
                totalOutputTokens: totalOutput,
                items: decoded.data
            )
            lastUpdated = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

struct AnthropicUsageSummary {
    let periodStart: Date
    let periodEnd: Date
    let totalCostUSD: Double
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let items: [AnthropicUsageResponse.AnthropicUsageItem]
}
