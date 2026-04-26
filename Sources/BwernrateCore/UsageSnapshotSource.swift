import Foundation

public actor UsageSnapshotSource {
    public init() {}

    public func loadOverview() async throws -> UsageOverview {
        let now = Date()
        return UsageOverview(
            snapshots: [
                ProviderUsageSnapshot(
                    kind: .codex,
                    planName: "Plus",
                    accountLabel: "Local account",
                    projectLabel: "ai-usage-app",
                    windows: [
                        UsageWindow(
                            id: "codex-session",
                            title: "Session",
                            usedPercent: 28,
                            resetsAt: now.addingTimeInterval(68 * 60)),
                        UsageWindow(
                            id: "codex-weekly",
                            title: "Weekly",
                            usedPercent: 44,
                            resetsAt: now.addingTimeInterval(2.6 * 24 * 60 * 60)),
                    ],
                    today: DailyUsageStats(
                        requests: 42,
                        inputTokens: 184_200,
                        outputTokens: 61_900,
                        activeMinutes: 96,
                        spend: ProviderSpend(used: 4.80, limit: 25, currencyCode: "USD"),
                        peakHourLabel: "10-11 AM"),
                    modelMix: [
                        ModelUsageShare(modelName: "gpt-5.3-codex", percent: 57),
                        ModelUsageShare(modelName: "gpt-5.4", percent: 31),
                        ModelUsageShare(modelName: "mini", percent: 12),
                    ],
                    creditBalance: 18.4,
                    extraSpend: nil,
                    streakDays: 12,
                    updatedAt: now),
                ProviderUsageSnapshot(
                    kind: .claude,
                    planName: "Max",
                    accountLabel: "Local account",
                    projectLabel: "design pass",
                    windows: [
                        UsageWindow(
                            id: "claude-session",
                            title: "Session",
                            usedPercent: 63,
                            resetsAt: now.addingTimeInterval(32 * 60)),
                        UsageWindow(
                            id: "claude-weekly",
                            title: "Weekly",
                            usedPercent: 71,
                            resetsAt: now.addingTimeInterval(4.1 * 24 * 60 * 60)),
                    ],
                    today: DailyUsageStats(
                        requests: 31,
                        inputTokens: 142_600,
                        outputTokens: 48_300,
                        activeMinutes: 78,
                        spend: ProviderSpend(used: 3.20, limit: 20, currencyCode: "USD"),
                        peakHourLabel: "9-10 AM"),
                    modelMix: [
                        ModelUsageShare(modelName: "opus", percent: 46),
                        ModelUsageShare(modelName: "sonnet", percent: 42),
                        ModelUsageShare(modelName: "haiku", percent: 12),
                    ],
                    creditBalance: nil,
                    extraSpend: ProviderSpend(used: 3.2, limit: 20, currencyCode: "USD"),
                    streakDays: 8,
                    updatedAt: now),
            ],
            updatedAt: now)
    }
}
