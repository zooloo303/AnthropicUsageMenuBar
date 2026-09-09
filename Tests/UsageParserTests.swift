import Foundation
import Testing
@testable import UsageCore

struct UsageParserTests {
    @Test func testClaudeDecodesRealWindowShapeAndIgnoresExtraUsage() throws {
        let data = Data(#"{"five_hour":{"utilization":34.5,"resets_at":"2026-09-09T01:00:00.123Z"},"seven_day":{"utilization":62,"resets_at":"2026-09-12T12:00:00Z"},"seven_day_sonnet":null,"extra_usage":{"is_enabled":true,"used_credits":15}}"#.utf8)
        let snapshot = try UsageParser.claude(data, plan: "max")
        #expect(snapshot.windows.count == 2)
        #expect(snapshot.windows[0].usedPercent == 34.5)
        #expect(abs(snapshot.windows[0].fraction - 0.345) < 0.0001)
        #expect(snapshot.windows[0].resetsAt != nil)
        #expect(snapshot.windows[1].resetsAt != nil)
        #expect(snapshot.plan == "max")
    }

    @Test func testMissingLimitsNeverBecomeZeroUsage() {
        for json in ["{}", #"{"five_hour":null,"seven_day":null}"#] {
            #expect(throws: (any Error).self) { try UsageParser.claude(Data(json.utf8)) }
        }
        #expect(throws: (any Error).self) { try UsageParser.codex(Data(#"{"rateLimits":{"primary":null,"secondary":null}}"#.utf8)) }
    }

    @Test func testCodexPrefersMultipleBucketsWithoutDuplicatingLegacy() throws {
        let data = Data(#"{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":18,"windowDurationMins":300,"resetsAt":1788900000},"secondary":{"usedPercent":43,"windowDurationMins":10080,"resetsAt":1789100000},"planType":"pro"},"other":{"limitName":"Other model","primary":{"usedPercent":20,"windowDurationMins":60}}}}"#.utf8)
        let snapshot = try UsageParser.codex(data)
        #expect(snapshot.windows.count == 3)
        #expect(snapshot.windows[0].usedPercent == 18)
        #expect(snapshot.windows[0].title == "5-hour session")
        #expect(snapshot.windows[1].title == "Weekly")
        #expect(snapshot.windows[2].title == "Other model · 1-hour window")
        #expect(snapshot.windows[0].resetsAt == Date(timeIntervalSince1970: 1788900000))
        #expect(snapshot.plan == "pro")
    }

    @Test func testCodexLegacyAndNullReset() throws {
        let snapshot = try UsageParser.codex(Data(#"{"rateLimits":{"primary":{"usedPercent":0,"windowDurationMins":15,"resetsAt":null},"secondary":null},"rateLimitsByLimitId":null}"#.utf8))
        #expect(snapshot.windows[0].usedPercent == 0)
        #expect(snapshot.windows[0].title == "15-minute window")
        #expect(snapshot.windows[0].resetsAt == nil)
    }

    @Test func testProgressClampsOverageWithoutHidingReportedUsage() throws {
        let snapshot = try UsageParser.claudeFixture(percent: 110)
        #expect(snapshot.windows[0].fraction == 1)
        #expect(snapshot.windows[0].usedPercent == 110)
    }

    @Test func testMalformedResponsesFailInsteadOfShowingSuccess() {
        #expect(throws: (any Error).self) { try UsageParser.claude(Data(#"{"five_hour":{"utilization":"unknown"}}"#.utf8)) }
        #expect(throws: (any Error).self) { try UsageParser.codex(Data(#"{"rateLimits":{"primary":{"usedPercent":"unknown"}}}"#.utf8)) }
    }
}

private extension UsageParser {
    static func claudeFixture(percent: Double) throws -> UsageSnapshot {
        try claude(Data("{\"five_hour\":{\"utilization\":\(percent),\"resets_at\":null}}".utf8))
    }
}
