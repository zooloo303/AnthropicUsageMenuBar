import SwiftUI

struct ContentView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var anthropicService: AnthropicService
    @ObservedObject var openAIService: OpenAIService

    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            anthropicSection
            if store.showOpenAI {
                openAISection
            }
            Divider()
            footer
            Button("Settings…") { showingSettings = true }
                .buttonStyle(.plain)
                .padding(.top, 4)
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 320)
        .onAppear {
            anthropicService.configure(store: store, intervalMinutes: store.refreshIntervalMinutes)
            openAIService.configure(store: store)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: store, anthropicService: anthropicService, openAIService: openAIService)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Usage Tracker")
                .font(.headline)
            if let updated = anthropicService.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var anthropicSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Anthropic")
                    .font(.subheadline).bold()
                Spacer()
                if anthropicService.isLoading { ProgressView().scaleEffect(0.6) }
            }
            if let usage = anthropicService.currentUsage {
                let limit = store.anthropicMonthlyLimitUSD
                let pct = min(1.0, usage.totalCostUSD / limit)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "$%.2f / $%.2f", usage.totalCostUSD, limit))
                        .font(.system(.body, design: .monospaced))
                    ProgressView(value: pct)
                        .tint(pct > 0.9 ? .red : .accentColor)
                    Text("\(usage.totalInputTokens + usage.totalOutputTokens) tokens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(store.anthropicAdminKey.isEmpty ? "No Admin API key configured" : "No data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let err = anthropicService.lastError {
                    Text(err).font(.caption2).foregroundStyle(.red)
                }
            }
        }
    }

    private var openAISection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("OpenAI / Codex")
                    .font(.subheadline).bold()
                Spacer()
            }
            if let usage = openAIService.currentUsage {
                let limit = store.openAIMonthlyLimitUSD
                let pct = min(1.0, usage.costUSD / limit)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "$%.2f / $%.2f", usage.costUSD, limit))
                        .font(.system(.body, design: .monospaced))
                    ProgressView(value: pct)
                        .tint(pct > 0.9 ? .red : .accentColor)
                    Text("\(usage.tokensUsed) tokens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No API key configured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        Text("Polls every \(store.refreshIntervalMinutes) min")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
