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
    public let workContext: WorkContextSnapshot?
    public let codexSession: CodexSessionStats?
    public let codexMemory: CodexProjectMemory?
    public let claudeSession: ClaudeSessionStats?
    public let claudeAggregate: ClaudeAggregateStats?
    public let claudeFacets: ClaudeFacets?
    public let claudeTodayBreakdown: ClaudeTodayBreakdown?
    public let patternCards: [ClaudePatternCard]
    public let healthIndicators: [ClaudeHealthIndicator]
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
        workContext: WorkContextSnapshot? = nil,
        codexSession: CodexSessionStats? = nil,
        codexMemory: CodexProjectMemory? = nil,
        claudeSession: ClaudeSessionStats? = nil,
        claudeAggregate: ClaudeAggregateStats? = nil,
        claudeFacets: ClaudeFacets? = nil,
        claudeTodayBreakdown: ClaudeTodayBreakdown? = nil,
        patternCards: [ClaudePatternCard] = [],
        healthIndicators: [ClaudeHealthIndicator] = [],
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
        self.workContext = workContext
        self.codexSession = codexSession
        self.codexMemory = codexMemory
        self.claudeSession = claudeSession
        self.claudeAggregate = claudeAggregate
        self.claudeFacets = claudeFacets
        self.claudeTodayBreakdown = claudeTodayBreakdown
        self.patternCards = patternCards
        self.healthIndicators = healthIndicators
        self.creditBalance = creditBalance
        self.extraSpend = extraSpend
        self.streakDays = streakDays
        self.updatedAt = updatedAt
    }

    public var highestUsedPercent: Double {
        self.windows.map(\.usedPercent).max() ?? 0
    }

    public var primaryWindow: UsageWindow? {
        self.windows.first
    }

    public var primaryUsedPercent: Double {
        self.primaryWindow?.usedPercent ?? self.highestUsedPercent
    }

    public var primaryResetAt: Date? {
        self.primaryWindow?.resetsAt
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

public struct CodexSessionStats: Codable, Equatable, Sendable {
    public let insight: CodexSessionInsight?
    public let threadTitle: String?
    public let gitBranch: String?
    public let reasoningEffort: String?
    public let cliVersion: String?
    public let source: String?
    public let approvalMode: String?
    public let sandboxLabel: String?
    public let sessionStartedAt: Date?
    public let lastActivityAt: Date?
    public let totalInputTokens: Int
    public let cachedInputTokens: Int
    public let totalOutputTokens: Int
    public let reasoningOutputTokens: Int
    public let lastInputTokens: Int
    public let lastOutputTokens: Int
    public let lastCachedInputTokens: Int
    public let lastReasoningOutputTokens: Int
    public let tokenEvents: Int
    public let toolCalls: Int
    public let shellCommands: Int
    public let patchEvents: Int
    public let webSearches: Int
    public let errors: Int
    public let compactions: Int
    public let flightEvents: [CodexFlightEvent]
    public let biggestBurnEvent: CodexFlightEvent?

    public var totalSessionTokens: Int {
        self.totalInputTokens + self.totalOutputTokens
    }

    public var lastTurnTokens: Int {
        self.lastInputTokens + self.lastOutputTokens
    }

    public var cacheSharePercent: Double {
        guard self.totalInputTokens > 0 else { return 0 }
        return min(100, max(0, Double(self.cachedInputTokens) / Double(self.totalInputTokens) * 100))
    }

    public var reasoningSharePercent: Double {
        guard self.totalOutputTokens > 0 else { return 0 }
        return min(100, max(0, Double(self.reasoningOutputTokens) / Double(self.totalOutputTokens) * 100))
    }

    public var activeMinutes: Int {
        guard let sessionStartedAt, let lastActivityAt else { return 0 }
        return max(0, Int(lastActivityAt.timeIntervalSince(sessionStartedAt) / 60))
    }

    public init(
        insight: CodexSessionInsight? = nil,
        threadTitle: String?,
        gitBranch: String?,
        reasoningEffort: String?,
        cliVersion: String?,
        source: String?,
        approvalMode: String?,
        sandboxLabel: String?,
        sessionStartedAt: Date?,
        lastActivityAt: Date?,
        totalInputTokens: Int,
        cachedInputTokens: Int,
        totalOutputTokens: Int,
        reasoningOutputTokens: Int,
        lastInputTokens: Int,
        lastOutputTokens: Int,
        lastCachedInputTokens: Int,
        lastReasoningOutputTokens: Int,
        tokenEvents: Int,
        toolCalls: Int,
        shellCommands: Int,
        patchEvents: Int,
        webSearches: Int,
        errors: Int,
        compactions: Int,
        flightEvents: [CodexFlightEvent] = [],
        biggestBurnEvent: CodexFlightEvent? = nil)
    {
        self.insight = insight
        self.threadTitle = threadTitle
        self.gitBranch = gitBranch
        self.reasoningEffort = reasoningEffort
        self.cliVersion = cliVersion
        self.source = source
        self.approvalMode = approvalMode
        self.sandboxLabel = sandboxLabel
        self.sessionStartedAt = sessionStartedAt
        self.lastActivityAt = lastActivityAt
        self.totalInputTokens = totalInputTokens
        self.cachedInputTokens = cachedInputTokens
        self.totalOutputTokens = totalOutputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.lastInputTokens = lastInputTokens
        self.lastOutputTokens = lastOutputTokens
        self.lastCachedInputTokens = lastCachedInputTokens
        self.lastReasoningOutputTokens = lastReasoningOutputTokens
        self.tokenEvents = tokenEvents
        self.toolCalls = toolCalls
        self.shellCommands = shellCommands
        self.patchEvents = patchEvents
        self.webSearches = webSearches
        self.errors = errors
        self.compactions = compactions
        self.flightEvents = flightEvents
        self.biggestBurnEvent = biggestBurnEvent
    }
}

public struct CodexFlightEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(self.timestamp.timeIntervalSince1970)-\(self.kind.rawValue)-\(self.title)" }

    public let timestamp: Date
    public let kind: CodexFlightEventKind
    public let title: String
    public let detail: String
    public let tokenImpact: Int?

    public init(
        timestamp: Date,
        kind: CodexFlightEventKind,
        title: String,
        detail: String,
        tokenImpact: Int?)
    {
        self.timestamp = timestamp
        self.kind = kind
        self.title = title
        self.detail = detail
        self.tokenImpact = tokenImpact
    }
}

public enum CodexFlightEventKind: String, Codable, Equatable, Sendable {
    case tokenSpike
    case shell
    case patch
    case web
    case error
    case compaction
}

public struct CodexProjectMemory: Codable, Equatable, Sendable {
    public let projectName: String
    public let sessionCount: Int
    public let averageSessionTokens: Int
    public let averageTurnTokens: Int
    public let heaviestSessionTokens: Int
    public let heaviestSessionTitle: String?
    public let relativeBurnMultiple: Double
    public let lastUpdatedAt: Date?

    public init(
        projectName: String,
        sessionCount: Int,
        averageSessionTokens: Int,
        averageTurnTokens: Int,
        heaviestSessionTokens: Int,
        heaviestSessionTitle: String?,
        relativeBurnMultiple: Double,
        lastUpdatedAt: Date?)
    {
        self.projectName = projectName
        self.sessionCount = sessionCount
        self.averageSessionTokens = averageSessionTokens
        self.averageTurnTokens = averageTurnTokens
        self.heaviestSessionTokens = heaviestSessionTokens
        self.heaviestSessionTitle = heaviestSessionTitle
        self.relativeBurnMultiple = relativeBurnMultiple
        self.lastUpdatedAt = lastUpdatedAt
    }
}

public struct CodexSessionInsight: Codable, Equatable, Sendable {
    public let health: CodexThreadHealth
    public let recommendation: String
    public let primaryDriver: String
    public let driverDetail: String
    public let forecast: String
    public let riskReason: String
    public let resetPlan: String
    public let lastTurnSharePercent: Double
    public let projectedTurnsRemaining: Int?
    public let tokensPerMinute: Int

    public init(
        health: CodexThreadHealth,
        recommendation: String,
        primaryDriver: String,
        driverDetail: String,
        forecast: String,
        riskReason: String,
        resetPlan: String,
        lastTurnSharePercent: Double,
        projectedTurnsRemaining: Int?,
        tokensPerMinute: Int)
    {
        self.health = health
        self.recommendation = recommendation
        self.primaryDriver = primaryDriver
        self.driverDetail = driverDetail
        self.forecast = forecast
        self.riskReason = riskReason
        self.resetPlan = resetPlan
        self.lastTurnSharePercent = min(100, max(0, lastTurnSharePercent))
        self.projectedTurnsRemaining = projectedTurnsRemaining
        self.tokensPerMinute = max(0, tokensPerMinute)
    }
}

public enum CodexThreadHealth: String, Codable, Equatable, Sendable {
    case efficient
    case healthy
    case watch
    case tight
    case stuck

    public var title: String {
        switch self {
        case .efficient: "Efficient"
        case .healthy: "Healthy"
        case .watch: "Watch"
        case .tight: "Tight"
        case .stuck: "Needs check"
        }
    }
}

public struct WorkContextSnapshot: Codable, Equatable, Sendable {
    public let sessionId: String?
    public let directory: String?
    public let modelName: String?
    public let contextUsedTokens: Int
    public let contextWindowTokens: Int
    public let averageGrowthTokens: Int?
    public let nextMessageTokens: Int?
    public let userMessageCount: Int
    public let updatedAt: Date

    public var contextUsedPercent: Double {
        guard self.contextWindowTokens > 0 else { return 0 }
        return min(100, max(0, Double(self.contextUsedTokens) / Double(self.contextWindowTokens) * 100))
    }

    public var contextRemainingPercent: Double {
        max(0, 100 - self.contextUsedPercent)
    }

    public var contextRemainingTokens: Int {
        max(0, self.contextWindowTokens - self.contextUsedTokens)
    }

    public var estimatedMessagesRemaining: Int? {
        guard let averageGrowthTokens, averageGrowthTokens > 0 else { return nil }
        return max(0, self.contextRemainingTokens / averageGrowthTokens)
    }

    public init(
        sessionId: String?,
        directory: String?,
        modelName: String?,
        contextUsedTokens: Int,
        contextWindowTokens: Int,
        averageGrowthTokens: Int?,
        nextMessageTokens: Int?,
        userMessageCount: Int,
        updatedAt: Date)
    {
        self.sessionId = sessionId
        self.directory = directory
        self.modelName = modelName
        self.contextUsedTokens = contextUsedTokens
        self.contextWindowTokens = contextWindowTokens
        self.averageGrowthTokens = averageGrowthTokens
        self.nextMessageTokens = nextMessageTokens
        self.userMessageCount = userMessageCount
        self.updatedAt = updatedAt
    }
}

// MARK: - Claude Code

public struct ClaudeAdvisor: Codable, Equatable, Sendable {
    public let health: CodexThreadHealth
    public let recommendation: String
    public let primaryDriver: String
    public let driverDetail: String
    public let forecast: String
    public let riskReason: String
    public let resetPlan: String
    public let lastTurnSharePercent: Double
    public let projectedTurnsRemaining: Int?
    public let tokensPerMinute: Int
    public let usdPerMinute: Double?

    public init(
        health: CodexThreadHealth,
        recommendation: String,
        primaryDriver: String,
        driverDetail: String,
        forecast: String,
        riskReason: String,
        resetPlan: String,
        lastTurnSharePercent: Double,
        projectedTurnsRemaining: Int?,
        tokensPerMinute: Int,
        usdPerMinute: Double? = nil)
    {
        self.health = health
        self.recommendation = recommendation
        self.primaryDriver = primaryDriver
        self.driverDetail = driverDetail
        self.forecast = forecast
        self.riskReason = riskReason
        self.resetPlan = resetPlan
        self.lastTurnSharePercent = min(100, max(0, lastTurnSharePercent))
        self.projectedTurnsRemaining = projectedTurnsRemaining
        self.tokensPerMinute = max(0, tokensPerMinute)
        self.usdPerMinute = usdPerMinute
    }
}

public struct ClaudeSessionStats: Codable, Equatable, Sendable {
    public let advisor: ClaudeAdvisor?
    public let sessionId: String?
    public let projectPath: String?
    public let projectName: String?
    public let threadTitle: String?
    public let firstPrompt: String?
    public let gitBranch: String?
    public let modelName: String?
    public let cliVersion: String?
    public let entrypoint: String?
    public let permissionMode: String?
    public let sessionStartedAt: Date?
    public let lastActivityAt: Date?
    public let userMessageCount: Int
    public let assistantMessageCount: Int
    public let toolCalls: Int
    public let toolHistogram: [ClaudeToolCount]
    public let toolErrors: Int
    public let userInterruptions: Int
    public let totalInputTokens: Int
    public let cacheCreateInputTokens: Int
    public let cacheReadInputTokens: Int
    public let totalOutputTokens: Int
    public let lastInputTokens: Int
    public let lastOutputTokens: Int
    public let lastCacheReadTokens: Int
    public let lastCacheCreateTokens: Int
    public let webSearches: Int
    public let webFetches: Int
    public let serviceTier: String?
    public let sidechainTokens: Int
    public let thinkingBlockCount: Int
    public let activeTaskTitle: String?
    public let activeTaskChain: [String]
    public let lastTurnDurationMs: Int?

    public var totalSessionTokens: Int {
        self.totalInputTokens + self.totalOutputTokens
    }

    public var lastTurnTokens: Int {
        self.lastInputTokens + self.lastOutputTokens
    }

    public var cacheSharePercent: Double {
        let denominator = self.totalInputTokens + self.cacheReadInputTokens
        guard denominator > 0 else { return 0 }
        return min(100, max(0, Double(self.cacheReadInputTokens) / Double(denominator) * 100))
    }

    public var activeMinutes: Int {
        guard let sessionStartedAt, let lastActivityAt else { return 0 }
        return max(0, Int(lastActivityAt.timeIntervalSince(sessionStartedAt) / 60))
    }

    public init(
        advisor: ClaudeAdvisor? = nil,
        sessionId: String?,
        projectPath: String?,
        projectName: String?,
        threadTitle: String?,
        firstPrompt: String?,
        gitBranch: String?,
        modelName: String?,
        cliVersion: String?,
        entrypoint: String?,
        permissionMode: String?,
        sessionStartedAt: Date?,
        lastActivityAt: Date?,
        userMessageCount: Int,
        assistantMessageCount: Int,
        toolCalls: Int,
        toolHistogram: [ClaudeToolCount] = [],
        toolErrors: Int,
        userInterruptions: Int,
        totalInputTokens: Int,
        cacheCreateInputTokens: Int,
        cacheReadInputTokens: Int,
        totalOutputTokens: Int,
        lastInputTokens: Int,
        lastOutputTokens: Int,
        lastCacheReadTokens: Int,
        lastCacheCreateTokens: Int,
        webSearches: Int,
        webFetches: Int,
        serviceTier: String?,
        sidechainTokens: Int,
        thinkingBlockCount: Int,
        activeTaskTitle: String?,
        activeTaskChain: [String] = [],
        lastTurnDurationMs: Int?)
    {
        self.advisor = advisor
        self.sessionId = sessionId
        self.projectPath = projectPath
        self.projectName = projectName
        self.threadTitle = threadTitle
        self.firstPrompt = firstPrompt
        self.gitBranch = gitBranch
        self.modelName = modelName
        self.cliVersion = cliVersion
        self.entrypoint = entrypoint
        self.permissionMode = permissionMode
        self.sessionStartedAt = sessionStartedAt
        self.lastActivityAt = lastActivityAt
        self.userMessageCount = userMessageCount
        self.assistantMessageCount = assistantMessageCount
        self.toolCalls = toolCalls
        self.toolHistogram = toolHistogram
        self.toolErrors = toolErrors
        self.userInterruptions = userInterruptions
        self.totalInputTokens = totalInputTokens
        self.cacheCreateInputTokens = cacheCreateInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.totalOutputTokens = totalOutputTokens
        self.lastInputTokens = lastInputTokens
        self.lastOutputTokens = lastOutputTokens
        self.lastCacheReadTokens = lastCacheReadTokens
        self.lastCacheCreateTokens = lastCacheCreateTokens
        self.webSearches = webSearches
        self.webFetches = webFetches
        self.serviceTier = serviceTier
        self.sidechainTokens = sidechainTokens
        self.thinkingBlockCount = thinkingBlockCount
        self.activeTaskTitle = activeTaskTitle
        self.activeTaskChain = activeTaskChain
        self.lastTurnDurationMs = lastTurnDurationMs
    }
}

public struct ClaudeToolCount: Codable, Equatable, Identifiable, Sendable {
    public var id: String { self.name }
    public let name: String
    public let count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

public struct ClaudeAggregateStats: Codable, Equatable, Sendable {
    public let firstSessionDate: Date?
    public let totalSessions: Int
    public let totalMessages: Int
    public let longestSessionMinutes: Int
    public let longestSessionMessageCount: Int
    public let longestSessionDate: Date?
    public let dailyMessageCounts: [ClaudeDailyCount]
    public let hourCounts: [Int]
    public let lifetimeInputTokens: Int
    public let lifetimeOutputTokens: Int
    public let lifetimeCacheReadTokens: Int
    public let lifetimeCacheCreationTokens: Int
    public let lifetimeWebSearchRequests: Int
    public let lifetimeModelTokens: [ClaudeModelTokens]
    public let lifetimeSyntheticCostUSD: Double
    public let modelMix: [ModelUsageShare]
    public let recentDayTokens: [ClaudeDailyTokenCount]
    public let speculationTimeSavedMs: Int
    public let lastComputedDate: String?
    public let toolLeaderboard: ClaudeToolLeaderboard
    public let betaGates: [ClaudeBetaGate]

    public var daysSinceFirstSession: Int? {
        guard let firstSessionDate else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: firstSessionDate)
        let end = calendar.startOfDay(for: Date())
        return calendar.dateComponents([.day], from: start, to: end).day.map { $0 + 1 }
    }

    public var streakDays: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let activeDays = Set(
            self.dailyMessageCounts
                .filter { $0.messageCount > 0 }
                .map { calendar.startOfDay(for: $0.date) })
        var streak = 0
        var cursor = today
        while activeDays.contains(cursor) {
            streak += 1
            guard let next = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = next
        }
        return streak
    }

    public var peakHourBand: (start: Int, end: Int, sharePercent: Double)? {
        guard self.hourCounts.count == 24 else { return nil }
        let total = self.hourCounts.reduce(0, +)
        guard total > 0 else { return nil }
        var bestStart = 0
        var bestSum = 0
        let bandWidth = 4
        for start in 0..<24 {
            var sum = 0
            for offset in 0..<bandWidth {
                sum += self.hourCounts[(start + offset) % 24]
            }
            if sum > bestSum {
                bestSum = sum
                bestStart = start
            }
        }
        let share = Double(bestSum) / Double(total) * 100
        return (bestStart, (bestStart + bandWidth) % 24, share)
    }

    public init(
        firstSessionDate: Date?,
        totalSessions: Int,
        totalMessages: Int,
        longestSessionMinutes: Int,
        longestSessionMessageCount: Int,
        longestSessionDate: Date?,
        dailyMessageCounts: [ClaudeDailyCount],
        hourCounts: [Int],
        lifetimeInputTokens: Int,
        lifetimeOutputTokens: Int,
        lifetimeCacheReadTokens: Int,
        lifetimeCacheCreationTokens: Int,
        lifetimeWebSearchRequests: Int,
        lifetimeModelTokens: [ClaudeModelTokens],
        lifetimeSyntheticCostUSD: Double,
        modelMix: [ModelUsageShare],
        recentDayTokens: [ClaudeDailyTokenCount],
        speculationTimeSavedMs: Int,
        lastComputedDate: String?,
        toolLeaderboard: ClaudeToolLeaderboard = .empty,
        betaGates: [ClaudeBetaGate] = [])
    {
        self.firstSessionDate = firstSessionDate
        self.totalSessions = totalSessions
        self.totalMessages = totalMessages
        self.longestSessionMinutes = longestSessionMinutes
        self.longestSessionMessageCount = longestSessionMessageCount
        self.longestSessionDate = longestSessionDate
        self.dailyMessageCounts = dailyMessageCounts
        self.hourCounts = hourCounts
        self.lifetimeInputTokens = lifetimeInputTokens
        self.lifetimeOutputTokens = lifetimeOutputTokens
        self.lifetimeCacheReadTokens = lifetimeCacheReadTokens
        self.lifetimeCacheCreationTokens = lifetimeCacheCreationTokens
        self.lifetimeWebSearchRequests = lifetimeWebSearchRequests
        self.lifetimeModelTokens = lifetimeModelTokens
        self.lifetimeSyntheticCostUSD = lifetimeSyntheticCostUSD
        self.modelMix = modelMix
        self.recentDayTokens = recentDayTokens
        self.speculationTimeSavedMs = speculationTimeSavedMs
        self.lastComputedDate = lastComputedDate
        self.toolLeaderboard = toolLeaderboard
        self.betaGates = betaGates
    }
}

public struct ClaudeToolLeaderboard: Codable, Equatable, Sendable {
    public let bashCommands: [ClaudeToolCount]
    public let mcpServers: [ClaudeToolCount]
    public let skills: [ClaudeToolCount]
    public let webFetchHosts: [ClaudeToolCount]
    public let totalToolCalls: Int
    public let scannedFileCount: Int

    public static let empty = ClaudeToolLeaderboard(
        bashCommands: [], mcpServers: [], skills: [], webFetchHosts: [],
        totalToolCalls: 0, scannedFileCount: 0)

    public init(
        bashCommands: [ClaudeToolCount],
        mcpServers: [ClaudeToolCount],
        skills: [ClaudeToolCount],
        webFetchHosts: [ClaudeToolCount],
        totalToolCalls: Int,
        scannedFileCount: Int)
    {
        self.bashCommands = bashCommands
        self.mcpServers = mcpServers
        self.skills = skills
        self.webFetchHosts = webFetchHosts
        self.totalToolCalls = totalToolCalls
        self.scannedFileCount = scannedFileCount
    }
}

public struct ClaudeBetaGate: Codable, Equatable, Identifiable, Sendable {
    public var id: String { self.name }
    public let name: String
    public let date: Date?
    public let humanLabel: String

    public init(name: String, date: Date?, humanLabel: String) {
        self.name = name
        self.date = date
        self.humanLabel = humanLabel
    }
}

public struct ClaudeTodayBreakdown: Codable, Equatable, Sendable {
    public let hourBuckets: [Int]
    public let languages: [ClaudeToolCount]
    public let linesAdded: Int
    public let linesRemoved: Int
    public let filesModified: Int
    public let gitCommits: Int

    public static let empty = ClaudeTodayBreakdown(
        hourBuckets: Array(repeating: 0, count: 24),
        languages: [],
        linesAdded: 0, linesRemoved: 0, filesModified: 0, gitCommits: 0)

    public init(
        hourBuckets: [Int],
        languages: [ClaudeToolCount],
        linesAdded: Int,
        linesRemoved: Int,
        filesModified: Int,
        gitCommits: Int)
    {
        self.hourBuckets = hourBuckets
        self.languages = languages
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.filesModified = filesModified
        self.gitCommits = gitCommits
    }
}

public struct ClaudeModelTokens: Codable, Equatable, Identifiable, Sendable {
    public var id: String { self.modelName }
    public let modelName: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadTokens: Int
    public let cacheCreationTokens: Int
    public let syntheticCostUSD: Double

    public init(
        modelName: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int,
        cacheCreationTokens: Int,
        syntheticCostUSD: Double)
    {
        self.modelName = modelName
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.syntheticCostUSD = syntheticCostUSD
    }
}

public struct ClaudeDailyCount: Codable, Equatable, Identifiable, Sendable {
    public var id: String { ISO8601DateFormatter().string(from: self.date) }
    public let date: Date
    public let messageCount: Int
    public let sessionCount: Int
    public let toolCallCount: Int

    public init(date: Date, messageCount: Int, sessionCount: Int, toolCallCount: Int) {
        self.date = date
        self.messageCount = messageCount
        self.sessionCount = sessionCount
        self.toolCallCount = toolCallCount
    }
}

public struct ClaudeDailyTokenCount: Codable, Equatable, Identifiable, Sendable {
    public var id: String { ISO8601DateFormatter().string(from: self.date) }
    public let date: Date
    public let totalTokens: Int

    public init(date: Date, totalTokens: Int) {
        self.date = date
        self.totalTokens = totalTokens
    }
}

public struct ClaudeFacets: Codable, Equatable, Sendable {
    public let sessionId: String?
    public let outcome: String?
    public let helpfulness: String?
    public let sessionType: String?
    public let underlyingGoal: String?
    public let briefSummary: String?
    public let frictionDetail: String?
    public let primarySuccess: String?
    public let frictionCounts: [ClaudeFrictionCount]
    public let satisfactionCounts: [ClaudeFrictionCount]
    public let recordedAt: Date?

    public var totalFriction: Int {
        self.frictionCounts.reduce(0) { $0 + $1.count }
    }

    public init(
        sessionId: String?,
        outcome: String?,
        helpfulness: String?,
        sessionType: String?,
        underlyingGoal: String?,
        briefSummary: String?,
        frictionDetail: String?,
        primarySuccess: String?,
        frictionCounts: [ClaudeFrictionCount],
        satisfactionCounts: [ClaudeFrictionCount],
        recordedAt: Date?)
    {
        self.sessionId = sessionId
        self.outcome = outcome
        self.helpfulness = helpfulness
        self.sessionType = sessionType
        self.underlyingGoal = underlyingGoal
        self.briefSummary = briefSummary
        self.frictionDetail = frictionDetail
        self.primarySuccess = primarySuccess
        self.frictionCounts = frictionCounts
        self.satisfactionCounts = satisfactionCounts
        self.recordedAt = recordedAt
    }
}

public struct ClaudeFrictionCount: Codable, Equatable, Identifiable, Sendable {
    public var id: String { self.name }
    public let name: String
    public let count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

public struct ClaudePatternCard: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(self.kind.rawValue)-\(self.title)" }
    public let kind: ClaudePatternKind
    public let title: String
    public let body: String
    public let footnote: String?
    public let highlightValue: String?
    public let progressPercent: Double?
    public let tone: ClaudePatternTone
    /// Higher = surface earlier. Anomalies score high; baseline cards score low.
    public let sortPriority: Double

    public init(
        kind: ClaudePatternKind,
        title: String,
        body: String,
        footnote: String? = nil,
        highlightValue: String? = nil,
        progressPercent: Double? = nil,
        tone: ClaudePatternTone = .neutral,
        sortPriority: Double = 0)
    {
        self.kind = kind
        self.title = title
        self.body = body
        self.footnote = footnote
        self.highlightValue = highlightValue
        self.progressPercent = progressPercent.map { min(100, max(0, $0)) }
        self.tone = tone
        self.sortPriority = sortPriority
    }
}

public enum ClaudePatternKind: String, Codable, Equatable, Sendable {
    case chronotype
    case cacheSavings
    case marathon
    case streak
    case modelMix
    case hourProfile
    case wrongPath
    case codeImpact
    case toolBias
    case speculation
    case wrap
    case costPerCommit
    case projectLeaderboard
    case badDay
    case monthlyWrap
    case apiEquivalent
    case overage
    case overageForecast
    case thinkingSpend
    case anxietyMeter
    case idleReclaim
    case pluginPopularity
    case bashLeaderboard
    case mcpLeaderboard
    case skillLeaderboard
    case betaTimeline
    case mostExpensiveTurn
    case overageReceipts
    case pastedNovel
    case contextDeaths
    case regretIndex
    case firstPromptEver
    case burnstarSign
    case codenameCollector
    case weekendWarrior
    case achievements
    case anniversary
    case skipList
}

public enum ClaudePatternTone: String, Codable, Equatable, Sendable {
    case positive
    case neutral
    case caution
}

public struct ClaudeHealthIndicator: Codable, Equatable, Identifiable, Sendable {
    public var id: String { self.label }
    public let label: String
    public let detail: String
    public let status: ClaudeHealthStatus

    public init(label: String, detail: String, status: ClaudeHealthStatus) {
        self.label = label
        self.detail = detail
        self.status = status
    }
}

public enum ClaudeHealthStatus: String, Codable, Equatable, Sendable {
    case ok
    case warn
    case error
    case unknown
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
