import SwiftUI

@main
struct UsageMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = UsageStore(preview: CommandLine.arguments.contains("--preview"))

    var body: some Scene {
        MenuBarExtra {
            ContentView(store: store)
        } label: {
            Image(systemName: store.hasErrors ? "chart.bar.xaxis" : "chart.bar.fill")
            if !store.menuTitle.isEmpty { Text(store.menuTitle) }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var previewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--preview") {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 370, height: 440),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Usage Menu Bar · Preview (sample data)"
            let previewStore = UsageStore(preview: true)
            if CommandLine.arguments.contains("--settings-preview") {
                window.contentView = NSHostingView(rootView: SettingsView(store: previewStore) { [weak window] in
                    window?.close()
                })
            } else {
                window.contentView = NSHostingView(rootView: ContentView(store: previewStore))
            }
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            previewWindow = window
            if let flag = CommandLine.arguments.firstIndex(of: "--snapshot"),
               CommandLine.arguments.indices.contains(flag + 1) {
                let destination = CommandLine.arguments[flag + 1]
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    guard let view = window.contentView,
                          let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: destination))
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
