import SwiftUI

@main
struct AnthropicUsageMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = SettingsStore()
    @StateObject private var anthropicService = AnthropicService()
    @StateObject private var openAIService = OpenAIService()

    var body: some Scene {
        MenuBarExtra {
            ContentView(
                store: store,
                anthropicService: anthropicService,
                openAIService: openAIService
            )
        } label: {
            Label("Usage", systemImage: iconForCurrentState)
        }
        .menuBarExtraStyle(.menu)
    }

    private var iconForCurrentState: String {
        let a = anthropicService.currentUsage
        let o = openAIService.currentUsage
        if a != nil || o != nil { return "bolt.fill" }
        return "bolt"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
