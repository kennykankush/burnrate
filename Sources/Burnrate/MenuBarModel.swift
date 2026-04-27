import BurnrateCore
import Foundation
import Observation

enum AppTab: String, CaseIterable, Identifiable {
    case now
    case patterns
    case wrap
    case health

    var id: String { self.rawValue }

    var label: String {
        switch self {
        case .now: "Now"
        case .patterns: "Patterns"
        case .wrap: "Wrap"
        case .health: "Health"
        }
    }

    var symbol: String {
        switch self {
        case .now: "flame"
        case .patterns: "square.grid.2x2"
        case .wrap: "calendar"
        case .health: "stethoscope"
        }
    }

    /// Keyboard shortcut bound on each tab button. ⌘1\u{2013}⌘4 follows
    /// the macOS convention used by Mail, Safari, etc.
    var keyEquivalent: Character {
        switch self {
        case .now: "1"
        case .patterns: "2"
        case .wrap: "3"
        case .health: "4"
        }
    }
}

/// What the menu bar status item shows. Each module renders as a Stats-
/// style two-line stack (label on top, value on bottom). User picks via
/// right-click on the item or via the gear-icon submenu in the popover.
/// When a window is depleted, the controller temporarily overrides
/// whatever the user picked with a `WAIT` countdown.
enum MenuBarModule: String, CaseIterable, Identifiable {
    case context
    case turnsLeft
    case fiveHour
    case weekly
    case dollarsPerMin
    case tokensPerMin
    case streak
    case cacheHit

    var id: String { self.rawValue }

    /// Top-line label (e.g., "CTX", "LEFT", "5H"). Kept short — menu-bar
    /// real estate is tight, and this sits above the numeric value.
    var label: String {
        switch self {
        case .context: "CTX"
        case .turnsLeft: "LEFT"
        case .fiveHour: "5H"
        case .weekly: "7D"
        case .dollarsPerMin: "$/M"
        case .tokensPerMin: "BURN"
        case .streak: "STREAK"
        case .cacheHit: "CACHE"
        }
    }

    /// Long-form name shown in the picker menu — more readable than the
    /// abbreviated label.
    var displayName: String {
        switch self {
        case .context: "Context %"
        case .turnsLeft: "Turns left"
        case .fiveHour: "5h burst %"
        case .weekly: "Weekly %"
        case .dollarsPerMin: "USD / minute"
        case .tokensPerMin: "Tokens / minute"
        case .streak: "Streak"
        case .cacheHit: "Cache hit %"
        }
    }
}

/// What the status item should render right now. The `label` is the
/// abbreviated top-line text; `value` is the bottom-line value.
struct MenuBarDisplay: Equatable {
    let label: String
    let value: String

    static let placeholder = MenuBarDisplay(label: "—", value: "—")
}

@MainActor
@Observable
final class MenuBarModel {
    var overview: UsageOverview = .empty
    var selectedProvider: ProviderKind = .codex
    var activeTab: AppTab = AppTab(rawValue: UserDefaults.standard.string(forKey: MenuBarModel.activeTabKey) ?? "") ?? .now
    var isRefreshing = false
    var lastError: UsageError?
    var lastRefreshAt: Date?
    var fireEvent: FireEvent?
    var alertMode: UsageAlertMode = UsageAlertMode(rawValue: UserDefaults.standard.string(forKey: UsageNotificationController.alertModeKey) ?? "") ?? .all
    var isLaunchAtLoginEnabled: Bool = LaunchAtLoginManager.isEnabled
    var selectedMenuBarModule: MenuBarModule = MenuBarModule(rawValue: UserDefaults.standard.string(forKey: MenuBarModel.menuBarModuleKey) ?? "") ?? .context

    /// Fires after every refresh tick (success or failure) so the
    /// non-SwiftUI status bar label can re-render. SwiftUI views in the
    /// popover observe `@Observable` directly and don't need this hook.
    var onSnapshotChanged: (@MainActor () -> Void)?

    static let activeTabKey = "burnrate.activeTab"
    static let menuBarModuleKey = "burnrate.menuBarModule"

    /// Friendly translation of a thrown error from the snapshot pipeline.
    /// We keep raw `localizedDescription` available for debug, but expose
    /// a short `title` (statusline) and an optional `recovery` hint
    /// (empty-state body) so the UI never shows raw `401: Unauthorized`
    /// strings to the user.
    struct UsageError: Equatable, Sendable {
        let title: String
        let recovery: String?
        let raw: String

        static func from(_ error: Error) -> UsageError {
            if let url = error as? URLError {
                switch url.code {
                case .notConnectedToInternet:
                    return UsageError(
                        title: "Offline",
                        recovery: "Reconnect and we'll resume on the next refresh.",
                        raw: url.localizedDescription)
                case .timedOut:
                    return UsageError(
                        title: "Request timed out",
                        recovery: "We'll retry automatically.",
                        raw: url.localizedDescription)
                case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                    return UsageError(
                        title: "Can't reach the API",
                        recovery: "Check your connection.",
                        raw: url.localizedDescription)
                default:
                    return UsageError(
                        title: "Network error",
                        recovery: nil,
                        raw: url.localizedDescription)
                }
            }

            let description = error.localizedDescription
            let lowered = description.lowercased()

            if description.contains("401") || lowered.contains("unauthorized") {
                return UsageError(
                    title: "Auth expired",
                    recovery: "Re-authorize Claude Code or Codex to resume.",
                    raw: description)
            }
            if description.contains("403") || lowered.contains("forbidden") {
                return UsageError(
                    title: "Permission denied",
                    recovery: "Your token may not have the right scopes.",
                    raw: description)
            }
            if description.contains("404") || lowered.contains("not found") {
                return UsageError(
                    title: "Endpoint not found",
                    recovery: "The API may have changed — check for an update.",
                    raw: description)
            }
            if description.contains("429") || lowered.contains("rate limit") {
                return UsageError(
                    title: "Rate limited",
                    recovery: "We'll back off and retry.",
                    raw: description)
            }
            if description.contains("500") || description.contains("502") ||
               description.contains("503") || description.contains("504")
            {
                return UsageError(
                    title: "Server error from the API",
                    recovery: "Usually transient — we'll retry.",
                    raw: description)
            }
            if lowered.contains("missingaccesstoken") || lowered.contains("missing access token") {
                return UsageError(
                    title: "Not signed in",
                    recovery: "Run \u{201C}codex auth\u{201D} or open Claude Code to sign in.",
                    raw: description)
            }
            if lowered.contains("unexpectedresponse") || lowered.contains("unexpected response") {
                return UsageError(
                    title: "Unexpected response from the API",
                    recovery: "We'll retry on the next refresh.",
                    raw: description)
            }
            return UsageError(title: description, recovery: nil, raw: description)
        }

        static func custom(title: String, recovery: String? = nil) -> UsageError {
            UsageError(title: title, recovery: recovery, raw: title)
        }
    }

    /// Captured when a user turn lands in the critical zone with a large token
    /// burn — drives the "playing with fire" statusline celebration.
    struct FireEvent: Equatable {
        let turnTokens: Int
        let contextUsedPercent: Double
        let triggeredAt: Date
    }

    /// Personal turn-size pattern, derived from observed per-turn deltas.
    /// This is what the bucket display + forecast use, instead of hardcoded
    /// 3K/12K/40K guesses.
    struct TurnPattern: Equatable {
        let samples: [Int]      // recent turn deltas, oldest first
        let avg: Int            // mean of samples
        let p90: Int            // 90th percentile (or max for small samples)
        let trend: Trend        // recent half vs older half

        enum Trend: Equatable { case up, flat, down }

        var hasEnoughData: Bool { self.avg > 0 }

        static let empty = TurnPattern(samples: [], avg: 0, p90: 0, trend: .flat)
    }

    var turnPatterns: [ProviderKind: TurnPattern] = [:]

    /// One snapshot of a window's usage at a point in time. The `resetsAt`
    /// is captured so we can detect window rolls (when it jumps forward,
    /// the window has reset and history should be cleared).
    struct WindowSample: Equatable {
        let timestamp: Date
        let usedPercent: Double
        let resetsAt: Date
    }

    /// Combined snapshot + forecast for a window. Built fresh on demand
    /// from `windowSamples` history — never cached.
    struct WindowForecast: Equatable {
        /// Model A — gap between current usage and even-pacing expectation
        /// at this point in the window. A snapshot, not a prediction.
        let aheadOfPacePercent: Double

        /// Model B — projected usage at reset assuming the recent burn
        /// rate (last ~hour of samples) continues. Nil when we don't have
        /// enough history yet.
        let projectedAtResetPercent: Double?

        /// When current usage is projected to hit 100%, if the projection
        /// puts us over budget. Nil otherwise.
        let runsOutAt: Date?
    }

    /// Per-window sample history. Drives the recent-rate projection that
    /// powers `WindowForecast.projectedAtResetPercent`. Keyed by the
    /// stable window id (e.g. "claude-oauth-5h"); cleared on window roll.
    private var windowSamples: [String: [WindowSample]] = [:]

    /// Cumulative-spend snapshot for rolling burn-rate calculation. Used
    /// by the overage projection to replace the month-to-date average
    /// (which over-projects for weeks after a heavy first day).
    struct OverageSample: Codable, Equatable {
        let timestamp: Date
        let usedCredits: Double
        let monthlyLimit: Double
    }

    /// Cumulative-spend history persisted to UserDefaults. Captured every
    /// refresh so we accumulate enough cross-day spread to compute a real
    /// 7-day slope, even across app restarts.
    private var overageHistory: [OverageSample] = []
    private static let overageHistoryKey = "burnrate.overageHistory"
    private static let overageHistoryMaxAgeDays: TimeInterval = 14 * 86400

    private let source = UsageSnapshotSource()
    private let notificationController = UsageNotificationController()
    private var hasStarted = false
    private var refreshTask: Task<Void, Never>?
    private var fireExpiryTask: Task<Void, Never>?
    private var prevUserMessageCount: [ProviderKind: Int] = [:]
    private var prevContextUsedTokens: [ProviderKind: Int] = [:]
    private var turnDeltaHistory: [ProviderKind: [Int]] = [:]
    private static let maxTurnHistory = 8

    /// Cap on per-window history. At a 30-second refresh cadence, 120
    /// samples = the last 60 minutes — long enough to compute a stable
    /// recent burn rate, short enough that the projection follows
    /// behavioural shifts within an hour.
    private static let maxWindowHistory = 120

    private static func median(of values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    var selectedSnapshot: ProviderUsageSnapshot? {
        self.overview.snapshot(for: self.selectedProvider) ?? self.overview.snapshots.first
    }

    /// Authoritative display values for the menu-bar status item. The
    /// controller renders these as a two-line stack. When any window is
    /// depleted, override the user's pick with a `WAIT` countdown — the
    /// killer module no other tracker has, because no other tracker
    /// watches rate-limit windows.
    var menuBarDisplay: MenuBarDisplay {
        guard !self.overview.snapshots.isEmpty else {
            return MenuBarDisplay(label: "BURN", value: "—")
        }
        if let depleted = self.firstDepletedWindow() {
            return MenuBarDisplay(
                label: "WAIT",
                value: Self.countdown(to: depleted.resetsAt))
        }
        return self.value(for: self.selectedMenuBarModule)
            ?? MenuBarDisplay(label: self.selectedMenuBarModule.label, value: "—")
    }

    func setMenuBarModule(_ module: MenuBarModule) {
        self.selectedMenuBarModule = module
        UserDefaults.standard.set(module.rawValue, forKey: Self.menuBarModuleKey)
    }

    private func firstDepletedWindow() -> UsageWindow? {
        for snap in self.overview.snapshots {
            if let depleted = snap.windows.first(where: { $0.usedPercent >= 99 && $0.resetsAt != nil }) {
                return depleted
            }
        }
        return nil
    }

    private func value(for module: MenuBarModule) -> MenuBarDisplay? {
        guard let snap = self.selectedSnapshot else { return nil }
        switch module {
        case .context:
            guard let context = snap.workContext else { return nil }
            return MenuBarDisplay(label: module.label, value: "\(Int(context.contextUsedPercent.rounded()))%")
        case .turnsLeft:
            guard let pattern = self.turnPatterns[snap.kind], pattern.avg > 0,
                  let context = snap.workContext, context.contextRemainingTokens > 0
            else { return nil }
            let turns = max(0, context.contextRemainingTokens / pattern.avg)
            return MenuBarDisplay(label: module.label, value: "\(turns)")
        case .fiveHour:
            guard let window = snap.windows.first(where: Self.is5hWindow) else { return nil }
            return MenuBarDisplay(label: module.label, value: "\(Int(window.usedPercent.rounded()))%")
        case .weekly:
            guard let window = snap.windows.first(where: Self.is7dWindow) else { return nil }
            return MenuBarDisplay(label: module.label, value: "\(Int(window.usedPercent.rounded()))%")
        case .dollarsPerMin:
            guard let usd = snap.claudeSession?.advisor?.usdPerMinute, usd > 0 else { return nil }
            return MenuBarDisplay(label: module.label, value: String(format: "%.2f", usd))
        case .tokensPerMin:
            let tpm = snap.claudeSession?.advisor?.tokensPerMinute
                ?? snap.codexSession?.insight?.tokensPerMinute
                ?? 0
            guard tpm > 0 else { return nil }
            return MenuBarDisplay(label: module.label, value: Self.compact(tpm))
        case .streak:
            guard snap.streakDays > 0 else { return nil }
            return MenuBarDisplay(label: module.label, value: "\(snap.streakDays)d")
        case .cacheHit:
            guard let agg = snap.claudeAggregate, agg.lifetimeCacheReadTokens > 0 else { return nil }
            let denom = max(1, agg.lifetimeInputTokens + agg.lifetimeCacheReadTokens)
            let pct = Int(Double(agg.lifetimeCacheReadTokens) / Double(denom) * 100)
            return MenuBarDisplay(label: module.label, value: "\(pct)%")
        }
    }

    private static func is5hWindow(_ w: UsageWindow) -> Bool {
        let id = w.id.lowercased()
        let title = w.title.lowercased()
        return id.contains("5h") || id.contains("primary") || title == "session" || title == "5h"
    }

    private static func is7dWindow(_ w: UsageWindow) -> Bool {
        let id = w.id.lowercased()
        let title = w.title.lowercased()
        // Exclude the per-model splits — the plain "Weekly" is what the
        // module surfaces. Users who want Opus/Sonnet specifically can
        // see them in the popover.
        guard !id.contains("opus"), !id.contains("sonnet") else { return false }
        return id.contains("7d") || id.contains("weekly") || title.contains("week")
    }

    private static func compact(_ value: Int) -> String {
        switch value {
        case 1_000_000...:
            return String(format: "%.1fM", Double(value) / 1_000_000)
        case 10_000...:
            return "\(value / 1_000)K"
        case 1_000...:
            return String(format: "%.1fK", Double(value) / 1_000)
        default:
            return "\(value)"
        }
    }

    private static func countdown(to date: Date?) -> String {
        guard let date else { return "—" }
        let secs = max(0, Int(date.timeIntervalSinceNow))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h > 0 { return "\(h)h\(m)m" }
        return "\(m)m"
    }

    func setActiveTab(_ tab: AppTab) {
        self.activeTab = tab
        UserDefaults.standard.set(tab.rawValue, forKey: Self.activeTabKey)
    }

    /// Flip selectedProvider to the other available provider. Skips
    /// providers that have no snapshot to avoid landing on a greyed-out
    /// tab. Bound to \u{2318}\\\\ in the popover.
    func cycleProvider() {
        let available = self.overview.snapshots.map(\.kind)
        guard available.count > 1 else { return }
        let current = self.selectedProvider
        let next = available.first { $0 != current } ?? current
        self.selectedProvider = next
    }

    func start() {
        guard !self.hasStarted else { return }
        self.hasStarted = true
        self.loadOverageHistory()
        self.refreshTask = Task {
            await self.notificationController.prepare()
            await self.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await self.refresh()
            }
        }
    }

    func refresh() async {
        guard !self.isRefreshing else { return }
        self.isRefreshing = true
        defer { self.isRefreshing = false }

        do {
            let recentRate = self.recentDailySpendRate(now: Date())
            let overview = try await self.source.loadOverview(recentDailySpend: recentRate)
            self.detectFireEvents(in: overview)
            self.recordWindowSamples(from: overview, now: Date())
            self.recordOverageSamples(from: overview, now: Date())
            self.overview = overview
            await self.notificationController.evaluate(overview)
            if overview.snapshot(for: self.selectedProvider) == nil,
               let first = overview.snapshots.first
            {
                self.selectedProvider = first.kind
            }
            self.lastError = nil
            self.lastRefreshAt = Date()
        } catch {
            self.lastError = UsageError.from(error)
        }
        self.onSnapshotChanged?()
    }

    /// Detect per-turn token deltas, feed the rolling-window pattern, and
    /// fire "playing with fire" moments when conditions align.
    private func detectFireEvents(in newOverview: UsageOverview) {
        for snap in newOverview.snapshots {
            guard let context = snap.workContext else { continue }

            // Bootstrap: if we have no pattern yet for this provider, seed it
            // from the existing per-turn growth estimate (current context size
            // ÷ user message count). Means the personalized forecast appears
            // immediately on first refresh, instead of needing 3+ observed
            // deltas before kicking in.
            if (self.turnPatterns[snap.kind]?.samples.isEmpty ?? true),
               let bootstrap = context.averageGrowthTokens, bootstrap > 0
            {
                self.turnPatterns[snap.kind] = TurnPattern(
                    samples: [bootstrap],
                    avg: bootstrap,
                    p90: bootstrap,
                    trend: .flat)
            }
            let newCount: Int
            switch snap.kind {
            case .claude: newCount = snap.claudeSession?.userMessageCount ?? 0
            case .codex: newCount = snap.codexSession?.toolCalls ?? 0
            }
            let newUsed = context.contextUsedTokens
            defer {
                self.prevUserMessageCount[snap.kind] = newCount
                self.prevContextUsedTokens[snap.kind] = newUsed
            }
            guard let prevCount = self.prevUserMessageCount[snap.kind],
                  let prevUsed = self.prevContextUsedTokens[snap.kind],
                  newCount > prevCount
            else { continue }
            let turnDelta = max(0, newUsed - prevUsed)

            // Record this turn into the rolling history, recompute pattern.
            self.recordTurn(provider: snap.kind, delta: turnDelta)

            // Critical zone + large burn = playing with fire
            if context.contextUsedPercent >= 75, turnDelta >= 35_000 {
                self.fireEvent = FireEvent(
                    turnTokens: turnDelta,
                    contextUsedPercent: context.contextUsedPercent,
                    triggeredAt: Date())
                self.scheduleFireExpiry()
            }
        }
    }

    private func recordTurn(provider: ProviderKind, delta: Int) {
        // Skip near-zero deltas (likely from compaction or session restarts) —
        // they pollute the average without representing real user activity.
        guard delta >= 500 else { return }

        var history = self.turnDeltaHistory[provider] ?? []
        history.append(delta)
        if history.count > Self.maxTurnHistory {
            history.removeFirst(history.count - Self.maxTurnHistory)
        }
        self.turnDeltaHistory[provider] = history

        // Compute pattern stats. Need at least 1 sample to publish anything.
        let avg = history.reduce(0, +) / max(1, history.count)
        let p90: Int = {
            guard history.count > 0 else { return 0 }
            if history.count <= 4 { return history.max() ?? 0 }
            let sorted = history.sorted()
            let idx = Int(Double(sorted.count - 1) * 0.9)
            return sorted[idx]
        }()
        let trend: TurnPattern.Trend = {
            // Need ≥6 samples (3 vs 3) before we'll claim a trend. With
            // mean-of-half comparisons at 4 samples (2 vs 2), a single
            // outlier turn could flip the trend; median-of-half at 6 is
            // robust to a single outlier in either half.
            guard history.count >= 6 else { return .flat }
            let half = history.count / 2
            let older = Self.median(of: Array(history.prefix(half)))
            let recent = Self.median(of: Array(history.suffix(half)))
            guard older > 0 else { return .flat }
            if Double(recent) >= Double(older) * 1.4 { return .up }
            if Double(recent) <= Double(older) * 0.7 { return .down }
            return .flat
        }()

        self.turnPatterns[provider] = TurnPattern(samples: history, avg: avg, p90: p90, trend: trend)
    }

    /// Append the current usedPercent for every observed window. Detects
    /// window rolls by watching `resetsAt`: when it jumps forward by more
    /// than a minute, the underlying window has reset, so we drop history
    /// and start fresh.
    private func recordWindowSamples(from overview: UsageOverview, now: Date) {
        for snap in overview.snapshots {
            for window in snap.windows {
                guard let resetsAt = window.resetsAt else { continue }
                var history = self.windowSamples[window.id] ?? []
                if let last = history.last,
                   abs(last.resetsAt.timeIntervalSince(resetsAt)) > 60
                {
                    history = []
                }
                history.append(WindowSample(
                    timestamp: now,
                    usedPercent: window.usedPercent,
                    resetsAt: resetsAt))
                if history.count > Self.maxWindowHistory {
                    history.removeFirst(history.count - Self.maxWindowHistory)
                }
                self.windowSamples[window.id] = history
            }
        }
    }

    /// Compute the snapshot ("ahead of pace") + forecast ("trending to
    /// X% by reset") for a window. The two models are deliberately kept
    /// distinct: one is an honest reading of where you are right now,
    /// the other is a real prediction from the recent burn rate. See
    /// `WindowForecast` for the rationale.
    func forecast(for window: UsageWindow, now: Date = Date()) -> WindowForecast? {
        guard let resetsAt = window.resetsAt,
              let total = window.totalDuration,
              window.usedPercent > 0
        else { return nil }
        let timeToReset = resetsAt.timeIntervalSince(now)
        guard timeToReset > 0 else { return nil }
        let elapsed = total - timeToReset
        // Skip the first ~3% of the window — too little signal to read.
        guard elapsed >= total * 0.03 else { return nil }

        // Model A — ahead-of-pace snapshot. Gap between actual usage and
        // where even-pacing through the window would have you right now.
        let elapsedFraction = elapsed / total
        let expectedPercent = elapsedFraction * 100
        let aheadOfPace = window.usedPercent - expectedPercent

        // Model B — recent-rate forecast. Compute the slope between the
        // oldest and newest samples we have for this window. We deliberately
        // use an unweighted slope: it's robust to noise and easy to reason
        // about. EWMA was overkill for the ~120-sample windows we keep.
        var projected: Double?
        var runsOutAt: Date?
        let samples = (self.windowSamples[window.id] ?? []).filter { sample in
            // Only samples from the same window incarnation
            abs(sample.resetsAt.timeIntervalSince(resetsAt)) <= 60
        }
        if samples.count >= 2,
           let oldest = samples.first,
           let newest = samples.last
        {
            let dt = newest.timestamp.timeIntervalSince(oldest.timestamp)
            let dPercent = newest.usedPercent - oldest.usedPercent
            // Need at least 2 minutes of span for the slope to mean anything.
            if dt >= 120 {
                let burnPerSec = max(0, dPercent / dt)
                let raw = window.usedPercent + burnPerSec * timeToReset
                projected = min(200, max(window.usedPercent, raw))
                if burnPerSec > 0, raw > 100 {
                    let secondsToFull = (100 - window.usedPercent) / burnPerSec
                    runsOutAt = now.addingTimeInterval(secondsToFull)
                }
            }
        }

        // Don't surface anything for sub-2% drift unless we have a
        // meaningful forecast that overruns.
        if aheadOfPace < 2,
           !(projected.map { $0 > 100 } ?? false)
        {
            return nil
        }

        return WindowForecast(
            aheadOfPacePercent: max(0, aheadOfPace),
            projectedAtResetPercent: projected,
            runsOutAt: runsOutAt)
    }

    /// Append a cumulative-spend snapshot per provider on every refresh.
    /// Trims by age (14-day cap) rather than count: we want a slope over
    /// real days, not over refresh ticks. Persists to UserDefaults so
    /// samples survive app restarts.
    private func recordOverageSamples(from overview: UsageOverview, now: Date) {
        let cutoff = now.addingTimeInterval(-Self.overageHistoryMaxAgeDays)
        var history = self.overageHistory.filter { $0.timestamp >= cutoff }
        for snap in overview.snapshots {
            guard let spend = snap.extraSpend, spend.limit > 0 else { continue }
            // Drop redundant samples within the same minute — refresh
            // cadence is 30s but we don't need that granularity for a
            // multi-day slope.
            if let last = history.last,
               now.timeIntervalSince(last.timestamp) < 60,
               last.usedCredits == spend.used
            { continue }
            history.append(OverageSample(
                timestamp: now,
                usedCredits: spend.used,
                monthlyLimit: spend.limit))
        }
        self.overageHistory = history
        self.persistOverageHistory()
    }

    /// Compute a daily spend rate from the rolling history. Uses a 7-day
    /// trailing window: takes the oldest sample within the last 7 days
    /// and computes (delta in usedCredits) / (delta in days). Returns nil
    /// when we don't have ≥2 days of history yet — caller falls back to
    /// month-to-date averaging in that case.
    func recentDailySpendRate(now: Date = Date()) -> Double? {
        guard self.overageHistory.count >= 2 else { return nil }
        let weekAgo = now.addingTimeInterval(-7 * 86400)
        // Use the oldest sample within the 7-day window. If the user has
        // been running >7 days the slope is exactly 7-day; if <7, slope
        // spans whatever history we have.
        guard let oldest = self.overageHistory.first(where: { $0.timestamp >= weekAgo }),
              let newest = self.overageHistory.last
        else { return nil }
        let deltaDays = newest.timestamp.timeIntervalSince(oldest.timestamp) / 86400
        // Need at least 2 days of spread for a meaningful rate.
        guard deltaDays >= 2 else { return nil }
        let deltaSpend = newest.usedCredits - oldest.usedCredits
        // If spend went down (limit reset, new cycle), don't try to project.
        guard deltaSpend >= 0 else { return nil }
        return deltaSpend / deltaDays
    }

    private func loadOverageHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.overageHistoryKey),
              let decoded = try? JSONDecoder().decode([OverageSample].self, from: data)
        else { return }
        let cutoff = Date().addingTimeInterval(-Self.overageHistoryMaxAgeDays)
        self.overageHistory = decoded.filter { $0.timestamp >= cutoff }
    }

    private func persistOverageHistory() {
        guard let data = try? JSONEncoder().encode(self.overageHistory) else { return }
        UserDefaults.standard.set(data, forKey: Self.overageHistoryKey)
    }

    private func scheduleFireExpiry() {
        self.fireExpiryTask?.cancel()
        self.fireExpiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            self?.fireEvent = nil
        }
    }

    func cycleAlertMode() {
        self.alertMode = self.alertMode.next
        UserDefaults.standard.set(self.alertMode.rawValue, forKey: UsageNotificationController.alertModeKey)
    }

    func toggleLaunchAtLogin() {
        do {
            if self.isLaunchAtLoginEnabled {
                try LaunchAtLoginManager.disable()
            } else {
                try LaunchAtLoginManager.enable()
            }
        } catch {
            self.lastError = UsageError.custom(
                title: "Launch at login failed",
                recovery: error.localizedDescription)
        }
        self.isLaunchAtLoginEnabled = LaunchAtLoginManager.isEnabled
    }
}
