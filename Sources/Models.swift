import Foundation

struct AnthropicUsagePoint: Codable, Identifiable {
    let id = UUID()
    let startTime: String
    let endTime: String
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationTokens: Int?
    let cacheReadTokens: Int?
    let costUSD: Double?
}

struct AnthropicUsageResponse: Codable {
    let data: [AnthropicUsageItem]
    let hasMore: Bool?

    struct AnthropicUsageItem: Codable {
        let startTime: String
        let endTime: String
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheCreationTokens: Int?
        let cacheReadTokens: Int?
        let cost: Double?
    }
}

struct OpenAIUsageSnapshot {
    let tokensUsed: Int
    let costUSD: Double
    let periodStart: Date
    let periodEnd: Date
}
