import Foundation

public enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex
    case claude

    public var id: String { self.rawValue }

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        }
    }

    public var shortName: String {
        switch self {
        case .codex: "CX"
        case .claude: "CL"
        }
    }

    public var symbolName: String {
        switch self {
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .claude: "sparkles"
        }
    }
}

public struct UsageWindow: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let usedPercent: Double
    public let resetsAt: Date?

    public var remainingPercent: Double {
        max(0, 100 - self.usedPercent)
    }

    public init(id: String, title: String, usedPercent: Double, resetsAt: Date?) {
        self.id = id
        self.title = title
        self.usedPercent = min(100, max(0, usedPercent))
        self.resetsAt = resetsAt
    }
}

public struct ProviderUsageSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: ProviderKind { self.kind }

    public let kind: ProviderKind
    public let planName: String?
    public let accountLabel: String?
    public let projectLabel: String?
    public let windows: [UsageWindow]
    public let today: DailyUsageStats
    public let modelMix: [ModelUsageShare]
    public let creditBalance: Double?
    public let extraSpend: ProviderSpend?
    public let streakDays: Int
    public let updatedAt: Date

    public init(
        kind: ProviderKind,
        planName: String?,
        accountLabel: String?,
        projectLabel: String?,
        windows: [UsageWindow],
        today: DailyUsageStats = .empty,
        modelMix: [ModelUsageShare] = [],
        creditBalance: Double?,
        extraSpend: ProviderSpend?,
        streakDays: Int = 0,
        updatedAt: Date = Date())
    {
        self.kind = kind
        self.planName = planName
        self.accountLabel = accountLabel
        self.projectLabel = projectLabel
        self.windows = windows
        self.today = today
        self.modelMix = modelMix
        self.creditBalance = creditBalance
        self.extraSpend = extraSpend
        self.streakDays = streakDays
        self.updatedAt = updatedAt
    }

    public var highestUsedPercent: Double {
        self.windows.map(\.usedPercent).max() ?? 0
    }

    public var mostPressedWindow: UsageWindow? {
        self.windows.max { $0.usedPercent < $1.usedPercent }
    }

    public var nextResetAt: Date? {
        self.windows
            .compactMap(\.resetsAt)
            .filter { $0 > Date() }
            .min()
    }
}

public struct ProviderSpend: Codable, Equatable, Sendable {
    public let used: Double
    public let limit: Double
    public let currencyCode: String

    public init(used: Double, limit: Double, currencyCode: String) {
        self.used = used
        self.limit = limit
        self.currencyCode = currencyCode
    }
}

public struct DailyUsageStats: Codable, Equatable, Sendable {
    public let requests: Int
    public let inputTokens: Int
    public let outputTokens: Int
    public let activeMinutes: Int
    public let spend: ProviderSpend?
    public let peakHourLabel: String?

    public var totalTokens: Int {
        self.inputTokens + self.outputTokens
    }

    public static let empty = DailyUsageStats(
        requests: 0,
        inputTokens: 0,
        outputTokens: 0,
        activeMinutes: 0,
        spend: nil,
        peakHourLabel: nil)

    public init(
        requests: Int,
        inputTokens: Int,
        outputTokens: Int,
        activeMinutes: Int,
        spend: ProviderSpend?,
        peakHourLabel: String?)
    {
        self.requests = requests
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.activeMinutes = activeMinutes
        self.spend = spend
        self.peakHourLabel = peakHourLabel
    }
}

public struct ModelUsageShare: Codable, Equatable, Identifiable, Sendable {
    public var id: String { self.modelName }

    public let modelName: String
    public let percent: Double

    public init(modelName: String, percent: Double) {
        self.modelName = modelName
        self.percent = min(100, max(0, percent))
    }
}

public struct UsageOverview: Codable, Equatable, Sendable {
    public let snapshots: [ProviderUsageSnapshot]
    public let updatedAt: Date

    public init(snapshots: [ProviderUsageSnapshot], updatedAt: Date = Date()) {
        self.snapshots = snapshots
        self.updatedAt = updatedAt
    }

    public static let empty = UsageOverview(snapshots: [])

    public func snapshot(for kind: ProviderKind) -> ProviderUsageSnapshot? {
        self.snapshots.first { $0.kind == kind }
    }

    public var highestUsedPercent: Double {
        self.snapshots
            .flatMap(\.windows)
            .map(\.usedPercent)
            .max() ?? 0
    }

    public var mostPressedSnapshot: ProviderUsageSnapshot? {
        self.snapshots.max { $0.highestUsedPercent < $1.highestUsedPercent }
    }

    public var nextResetAt: Date? {
        self.snapshots
            .compactMap(\.nextResetAt)
            .min()
    }

    public var totalRequestsToday: Int {
        self.snapshots.reduce(0) { $0 + $1.today.requests }
    }

    public var totalActiveMinutesToday: Int {
        self.snapshots.reduce(0) { $0 + $1.today.activeMinutes }
    }
}
