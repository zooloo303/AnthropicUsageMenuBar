import SwiftUI
import UsageCore

struct ContentView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Usage").font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("Your subscription limits, together")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await store.refreshAll() } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.borderless).disabled(store.isLoading)
                .help("Refresh usage (requests are at least one minute apart)")
                .accessibilityLabel("Refresh usage")
            }
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(store.visibleProviders) { provider in
                        ProviderCard(provider: provider, state: store.states[provider] ?? ProviderState(),
                                     interval: store.preferences.interval, connectClaude: { store.connectClaude() })
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 460)
            HStack {
                Text("Updates every \(store.preferences.interval) min")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button { store.showSettings() } label: { Image(systemName: "gearshape") }
                    .help("Settings").accessibilityLabel("Settings")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help("Quit Usage Menu Bar").accessibilityLabel("Quit Usage Menu Bar")
            }
            .buttonStyle(.borderless)
        }
        .padding(20)
        .frame(width: 370)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial)
        .task { await store.refreshIfDue() }
    }
}

private struct ProviderCard: View {
    let provider: Provider
    let state: ProviderState
    let interval: Int
    let connectClaude: () -> Void
    private var accent: Color { provider == .claude ? Color(red: 0.77, green: 0.43, blue: 0.31) : Color(red: 0.18, green: 0.61, blue: 0.48) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: provider == .claude ? "sun.max.fill" : "terminal.fill")
                    .foregroundStyle(accent)
                Text(provider.title).font(.system(size: 15, weight: .semibold))
                if let plan = state.snapshot?.planDisplayName {
                    Text(plan).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                        .help("Reported plan: \(state.snapshot?.plan ?? plan)")
                }
                Spacer()
                if state.loading { ProgressView().controlSize(.small) }
                Link(destination: provider.usageURL) { Image(systemName: "arrow.up.right") }
                    .foregroundStyle(.secondary).help("Open \(provider.title) usage page")
            }
            if provider == .claude && state.error != nil {
                Button("Connect Claude…", action: connectClaude).font(.caption)
            }
            if let snapshot = state.snapshot {
                ForEach(snapshot.windows) { window in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(window.title).font(.caption)
                            Spacer()
                            Text("\(window.usedPercent, specifier: "%.0f")% used")
                                .font(.system(.caption, design: .monospaced).weight(.medium))
                        }
                        ProgressView(value: window.fraction)
                            .tint(window.usedPercent >= 90 ? .red : window.usedPercent >= 75 ? .orange : accent)
                            .accessibilityLabel(window.title)
                            .accessibilityValue("\(Int(window.usedPercent)) percent used")
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            Text(resetText(window.resetsAt, now: context.date))
                                .font(.caption2).foregroundStyle(.secondary)
                                .help(window.resetsAt?.formatted(date: .complete, time: .shortened) ?? "Reset time not provided")
                        }
                    }
                }
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let stale = state.error != nil || context.date.timeIntervalSince(snapshot.fetchedAt) > Double(interval * 120)
                    Text("\(stale ? "Last reading" : "Updated") \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))\(stale ? " · may be out of date" : "")")
                        .font(.caption2).foregroundStyle(stale ? .orange : .secondary)
                }
            } else if state.error == nil {
                Text(state.loading ? "Reading your usage…" : "Waiting for first reading…")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = state.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07)))
    }

    private func resetText(_ date: Date?, now: Date) -> String {
        guard let date else { return "Reset time not provided" }
        guard date > now else { return "Reset due · awaiting fresh usage" }
        let minutes = max(1, Int(ceil(date.timeIntervalSince(now) / 60)))
        let duration: String
        if minutes >= 1440 { duration = "\(minutes / 1440)d \((minutes % 1440) / 60)h" }
        else if minutes >= 60 { duration = "\(minutes / 60)h \(minutes % 60)m" }
        else { duration = "\(minutes)m" }
        return "Resets in \(duration) · \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
    }
}
