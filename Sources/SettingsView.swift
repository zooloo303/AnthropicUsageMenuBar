import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var anthropicService: AnthropicService
    @ObservedObject var openAIService: OpenAIService

    @Environment(\.dismiss) private var dismiss
    @State private var anthropicKey = ""
    @State private var openAIKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Anthropic") {
                    SecureField("Admin API Key (sk-ant-admin01-...)", text: $anthropicKey)
                    HStack {
                        Text("Monthly limit")
                        Spacer()
                        TextField("", value: $store.anthropicMonthlyLimitUSD, format: .currency(code: "USD"))
                            .frame(width: 120)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section("OpenAI / Codex") {
                    Toggle("Show OpenAI", isOn: $store.showOpenAI)
                    SecureField("API Key", text: $openAIKey)
                    HStack {
                        Text("Monthly limit")
                        Spacer()
                        TextField("", value: $store.openAIMonthlyLimitUSD, format: .currency(code: "USD"))
                            .frame(width: 120)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section("General") {
                    Picker("Refresh interval", selection: $store.refreshIntervalMinutes) {
                        Text("5 min").tag(5)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("60 min").tag(60)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.anthropicAdminKey = anthropicKey
                        store.openAIKey = openAIKey
                        // reconfigure services
                        // Note: services need store reference; in real app use injection
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            anthropicKey = store.anthropicAdminKey
            openAIKey = store.openAIKey
        }
        .frame(width: 420, height: 420)
    }
}
