import AppKit
import BurnrateCore
import Observation
import os.log
import SwiftUI

private let log = Logger(subsystem: "fyi.burnrate.app", category: "notch")

/// Single gating point for every haptic the alcove fires. All call
/// sites — alcove open/close, conversation pill confirm/unpin,
/// provider switch, fire banner, tight-context heartbeat — go
/// through this so one toggle silences them all.
///
/// Default OFF: macOS trackpad haptics are surprisingly insistent
/// and can feel out of place against the alcove's silent visual
/// choreography. Opt-in for users who want the extra feedback.
@MainActor
enum HapticGate {
    /// UserDefaults key, shared with `MenuBarModel.setHapticsEnabled`.
    static let key = "burnrate.hapticsEnabled"

    static var enabled: Bool {
        UserDefaults.standard.bool(forKey: self.key)
    }

    static func perform(
        _ pattern: NSHapticFeedbackManager.FeedbackPattern,
        _ time: NSHapticFeedbackManager.PerformanceTime = .default)
    {
        guard self.enabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(
            pattern, performanceTime: time)
    }
}

/// Compact integer formatter shared across burn / streak views.
private func compactTokens(_ tokens: Int) -> String {
    if tokens >= 1_000_000 { return String(format: "%.1fM", Double(tokens) / 1_000_000) }
    if tokens >= 10_000 { return "\(tokens / 1_000)K" }
    if tokens >= 1_000 { return String(format: "%.1fK", Double(tokens) / 1_000) }
    return "\(tokens)"
}

private func compactShare(_ percent: Double) -> String {
    DisplayText.contextShare(percent)
}

// MARK: - Layout preference key

/// SwiftUI preference for measuring the open-state alcove content
/// height. The morph host reads this and resizes the drawer to match,
/// so the alcove auto-fits any content config (with or without
/// Opus/Sonnet windows, with or without advisor data) without
/// reserving empty space at the bottom.
private struct ContentSizeKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Notch palette
//
// The alcove is its own design surface — punchier and more cinematic than
// the menu bar popover. Pure black canvas, slightly warmer off-whites,
// electric tones, and a warm amber-coral accent in place of the menu
// bar's quiet lavender. Used everywhere inside the alcove; the popover
// keeps using DesignSystem.Colors.

private enum NotchPalette {
    // Text — slightly warmer than the menu bar's neutral whites
    static let primaryText = Color(red: 0.96, green: 0.96, blue: 0.94)
    static let secondaryText = Color(red: 0.74, green: 0.74, blue: 0.78)
    static let tertiaryText = Color(red: 0.44, green: 0.46, blue: 0.52)

    // Accent — replaces brandLavender. Cinematic amber-coral that pops
    // on pure black. Used for the bolt icon, dev wrench, "DEV CONTROLS"
    // label, choreography label.
    static let accent = Color(red: 1.00, green: 0.62, blue: 0.38)

    // Tones — more electric than the popover's softer success/warning/
    // danger. Mapped from UsageTone via tone(_:).
    static let toneCalm = Color(red: 0.36, green: 0.92, blue: 0.78)   // mint-teal
    static let toneWatch = Color(red: 1.00, green: 0.78, blue: 0.30)  // sunshine amber
    static let toneTight = Color(red: 1.00, green: 0.42, blue: 0.38)  // coral red
    static let danger = toneTight

    // Live indicator — electric green that reads as "right now"
    static let live = Color(red: 0.30, green: 0.95, blue: 0.55)

    // Hairlines / surfaces
    static let hairline = Color.white.opacity(0.06)
    static let hairlineStrong = Color.white.opacity(0.10)

    static func tone(_ tone: UsageTone) -> Color {
        switch tone {
        case .calm: return toneCalm
        case .watch: return toneWatch
        case .tight: return toneTight
        }
    }
}

// MARK: - Tool taxonomy

/// The four hover-switchable tools that live inside the open alcove. Each
/// is a distinct surface — different viz, different data — not four
/// variations of the same dashboard. The strip across the top of the
/// alcove uses mouse-hover (not click) to switch between them.
enum NotchTool: String, CaseIterable, Identifiable {
    /// The complete "right now" picture — context %, 5h burst, weekly
    /// as a ring trio, advisor WHY/WHEN block, and the runway bar.
    /// Compresses the menu bar's NOW tab into a single dense surface.
    case now
    /// Patterns — chronotype, model mix, leaderboards, diagnostics.
    /// Mirrors the menu bar's Patterns tab.
    case patterns
    /// Wrap — aggregate strip, cost over time, last 30d sparkline,
    /// hero feature cards. Mirrors the menu bar's Wrap tab.
    case wrap
    /// Health — system status, today's hourly breakdown, language
    /// pills, tool histogram. Mirrors the menu bar's Health tab.
    case health

    var id: String { self.rawValue }

    var label: String {
        switch self {
        case .now: "NOW"
        case .patterns: "PATTERNS"
        case .wrap: "WRAP"
        case .health: "HEALTH"
        }
    }

    var symbol: String {
        switch self {
        case .now: "bolt.fill"
        case .patterns: "square.grid.2x2"
        case .wrap: "calendar"
        case .health: "stethoscope"
        }
    }
}

struct NotchThresholdAlert: Equatable, Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let tone: UsageTone
}

// MARK: - Presenter

/// Hosts the burnrate alcove. Closed state is a black notch silhouette
/// with an optional ambient tone hairline when context heats up. Hover
/// expands into a dashboard with four hoverable tools (PACE / WINDOWS /
/// BURN / STREAK) plus a hidden dev panel for choreography tweaking.
@MainActor
final class NotchPresenter {
    let model: MenuBarModel

    private let displayState = NotchDisplayState()
    private var panel: NotchPanel?
    private var screenObserver: NSObjectProtocol?
    private var lastNotchSize: NSSize?

    /// Total panel width — sized to host the maxWidth=580 alcove with a
    /// little breathing room. Kept narrow so the closed-state panel
    /// doesn't sit over the user's menu-bar status items and block clicks.
    static let panelWidth: CGFloat = NotchMorphHost.maxWidth + 40

    init(model: MenuBarModel) {
        self.model = model
        self.observeScreenChanges()
        self.refresh()
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func refresh() {
        self.displayState.update(from: self.model)

        // If the notch size resolves to a different value than what the
        // current panel was sized for, tear the panel down so activate()
        // rebuilds it. Skip during active calibration — the host re-
        // renders the silhouette live from Observable state, and we don't
        // want to rebuild the panel on every drag tick.
        if let screen = Self.preferredScreen() {
            let target = self.computedNotchSize(for: screen)
            if self.panel != nil, target != self.lastNotchSize, !self.model.notchCalibrating {
                self.deactivate()
            }
            self.lastNotchSize = target
        }

        if self.model.notchEnabled {
            self.activate()
        } else {
            self.deactivate()
        }
    }

    /// Pick the screen the alcove should render on. The notch only
    /// exists on the MacBook's built-in display, so prefer the first
    /// screen with `auxiliaryTopLeftArea` (i.e. has a real notch). Fall
    /// back to `NSScreen.main` (the focused screen) and then the first
    /// available screen if no notched display is connected.
    static func preferredScreen() -> NSScreen? {
        if let notched = NSScreen.screens.first(where: { $0.notchFrame != nil }) {
            return notched
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func computedNotchSize(for screen: NSScreen) -> NSSize {
        let detected = screen.notchFrame?.size
            ?? NSSize(width: 200, height: max(screen.frame.maxY - screen.visibleFrame.maxY, 24))
        let w = self.model.notchWidthOverride.map { CGFloat($0) } ?? detected.width
        let h = self.model.notchHeightOverride.map { CGFloat($0) } ?? detected.height
        return NSSize(width: max(60, w), height: max(20, h))
    }

    private func activate() {
        if self.panel != nil { return }
        guard let screen = Self.preferredScreen() else {
            log.error("activate: no NSScreen available")
            return
        }

        let notchSize = self.computedNotchSize(for: screen)
        let detected = screen.notchFrame?.size
            ?? NSSize(width: 200, height: max(screen.frame.maxY - screen.visibleFrame.maxY, 24))

        let host = NSHostingView(rootView: NotchMorphHost(
            state: self.displayState,
            model: self.model,
            detectedNotchWidth: detected.width,
            detectedNotchHeight: detected.height
        ))
        host.translatesAutoresizingMaskIntoConstraints = true

        let panel = NotchPanel()
        panel.contentView = host

        let panelWidth: CGFloat = Self.panelWidth
        let panelHeight: CGFloat = notchSize.height + NotchMorphHost.maxDrawerHeight + 40
        let origin = NSPoint(
            x: screen.frame.midX - (panelWidth / 2),
            y: screen.frame.maxY - panelHeight
        )
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: panelWidth, height: panelHeight)), display: false)
        panel.orderFrontRegardless()

        self.panel = panel
        let isNotched = screen.hasNotchAuxiliaryAreas
        log.info("alcove activated, hasNotch=\(isNotched, privacy: .public), notch=\(notchSize.debugDescription, privacy: .public)")
    }

    private func deactivate() {
        guard let panel else { return }
        self.panel = nil
        panel.orderOut(nil)
        panel.close()
        log.info("alcove deactivated")
    }

    private func observeScreenChanges() {
        self.screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.deactivate()
                self?.refresh()
            }
        }
    }
}

// MARK: - Observable display state

@MainActor
@Observable
final class NotchDisplayState {
    /// Header
    var projectLabel: String = "—"
    var providerLabel: String = ""
    var isLive: Bool = false
    var sessionDuration: String = ""
    var sessionTurns: Int = 0
    /// Active model (shortened) + git branch — surfaced in NOW's hero
    /// chips and footer row to give the user context for the burn.
    var modelLabel: String? = nil
    var gitBranch: String? = nil

    /// Pace tool
    var contextPercent: Double = 0
    var contextTone: UsageTone = .calm
    var hasContext: Bool = false
    var verdictTitle: String = ""
    var verdictDetail: String = ""
    var verdictPattern: String = ""

    /// Windows tool
    var fiveHour: AlcoveWindow? = nil
    var weekly: AlcoveWindow? = nil
    var weeklyOpus: AlcoveWindow? = nil
    var weeklySonnet: AlcoveWindow? = nil
    var fiveHourForecast: WindowForecastSummary? = nil
    var weeklyForecast: WindowForecastSummary? = nil

    /// Burn tool
    var tokensPerMinute: Int = 0
    var dollarsPerMinute: Double = 0
    var dailySpendRate: Double? = nil
    var spendUsed: Double? = nil
    var spendLimit: Double? = nil
    var hasBurnData: Bool = false

    /// Today's totals — fuels the TODAY tab's headline strip and the
    /// BURN tab's "today so far" callout. Mirrors what the menu bar's
    /// `AccountTodayStrip` shows.
    var turnsToday: Int = 0
    var totalTokensToday: Int = 0
    var activeMinutesToday: Int = 0
    var spendToday: Double? = nil
    var hasTodayData: Bool = false
    var peakHourLabel: String? = nil
    var planName: String? = nil

    /// Derived per-turn metrics (today). Computed once at update so
    /// the stat tiles can render without inline division logic.
    var dollarsPerTurnToday: Double? = nil
    var tokensPerTurnToday: Int = 0

    /// Monthly spend projection — extrapolates current month-to-date
    /// spend out to the end of the calendar month using the 7-day
    /// rolling daily rate. Lets BURN show "where you'll land".
    var projectedMonthSpend: Double? = nil
    var daysRemainingInMonth: Int = 0

    /// Cost section — synthetic cost computed from the user's rolling
    /// 30-day token rate, applied to today's tokens. Mirrors the menu
    /// bar's "Cost" panel (Today / Last 30 days / Lifetime).
    var syntheticCostToday: Double? = nil
    var cost30d: Double? = nil
    var tokens30d: Int = 0
    var costLifetime: Double? = nil
    var tokensLifetime: Int = 0

    /// Streak tool
    var streakDays: Int = 0
    var cacheHitPercent: Int? = nil
    var fireActive: Bool = false
    var fireTurnTokens: Int = 0
    var fireContextPercent: Double = 0

    /// Turn pattern — drives the monitoring-panel rhythm row at the
    /// bottom of NOW. Avg, sample count, and trend direction.
    var turnAvgTokens: Int = 0
    var turnSampleCount: Int = 0
    var turnTrend: TurnTrend = .flat
    var hasTurnPattern: Bool = false

    /// Concurrent live sessions across both providers. Pulled from
    /// `ProviderUsageSnapshot.liveSessions` — sessions whose jsonl
    /// has been touched within the last 10 minutes. Surfaces in the
    /// alcove header counter and powers the in-hero session picker
    /// (Claude only) for pinning a specific project.
    var liveSessionCount: Int = 0
    var liveSessionProjects: [String] = []
    /// Raw live sessions (Claude only — these are pinnable). Used
    /// by AlcoveTopRow's picker menu so the user can switch which
    /// session's context the alcove watches when multiple are running.
    var liveClaudeSessions: [LiveSession] = []

    enum TurnTrend: String, Sendable {
        case up
        case flat
        case down
    }

    /// Advisor (Claude `ClaudeAdvisor` or Codex `CodexSessionInsight`).
    /// Surfaces the qualitative WHAT/WHY/WHEN/DO that the menu bar's
    /// Stamina section uses — the alcove pulls the same content into
    /// NOW so the notch isn't just numbers.
    var advisorHealthTitle: String = ""
    var advisorIconName: String = "checkmark.seal"
    var advisorTone: UsageTone = .calm
    var advisorRecommendation: String = ""
    var advisorPrimaryDriver: String = ""
    var advisorDriverDetail: String = ""
    var advisorForecast: String = ""
    var advisorResetPlan: String = ""
    var advisorLastTurnShare: Double = 0
    var advisorProjectedTurns: Int? = nil
    var hasAdvisor: Bool = false

    /// Depleted-state takeover
    var depletedTitle: String? = nil
    var depletedCountdown: String? = nil
    var depletedClock: String? = nil

    /// Ambient cue painted on the closed notch silhouette so the user can
    /// glance at the menu bar and notice things are heating up without
    /// hovering. Nil = nothing painted.
    var ambientCueColor: Color? = nil
    var thresholdAlert: NotchThresholdAlert? = nil

    struct AlcoveWindow: Equatable {
        let label: String       // "5H" / "7D"
        let longLabel: String   // "5h burst" / "Weekly"
        let percent: Double
        let tone: UsageTone
        let resetText: String   // "2h 15m" / "in 4d"
        /// Raw reset Date — used to format "back at HH:mm" in the
        /// depleted sub-line. Optional because some windows don't
        /// carry a reset timestamp from the source.
        let resetsAt: Date?
    }

    struct WindowForecastSummary: Equatable {
        let aheadOfPacePercent: Double
        let projectedAtResetPercent: Double?
        let runsOutAt: Date?
        let runsOutText: String?
    }

    func update(from model: MenuBarModel) {
        let snapshot = model.selectedSnapshot
        self.projectLabel = snapshot?.projectLabel ?? "—"
        self.providerLabel = snapshot?.kind.displayName ?? ""
        self.isLive = Self.isLive(snapshot: snapshot)
        self.sessionDuration = Self.sessionDurationText(snapshot: snapshot)
        self.sessionTurns = snapshot?.claudeSession?.userMessageCount
            ?? snapshot?.codexSession?.toolCalls
            ?? 0
        self.modelLabel = Self.shortModelLabel(snapshot?.claudeSession?.modelName)
        self.gitBranch = snapshot?.claudeSession?.gitBranch
            ?? snapshot?.codexSession?.gitBranch

        // PACE
        if let context = snapshot?.workContext {
            self.contextPercent = context.contextUsedPercent
            self.contextTone = UsageTone(percent: context.contextUsedPercent)
            self.hasContext = true

            let pattern = snapshot.map {
                model.turnPattern(forSessionId: context.sessionId, provider: $0.kind)
            } ?? .empty
            if pattern.avg > 0 {
                let turnsLeft = max(0, context.contextRemainingTokens / pattern.avg)
                self.verdictTitle = Self.verdictTitle(percent: context.contextUsedPercent, turnsLeft: turnsLeft)
                self.verdictDetail = Self.verdictDetail(turnsLeft: turnsLeft)
                self.verdictPattern = Self.verdictPattern(pattern: pattern)
            } else {
                self.verdictTitle = Self.verdictTitle(percent: context.contextUsedPercent, turnsLeft: -1)
                self.verdictDetail = "first few turns are coming in"
                self.verdictPattern = "learning your pace"
            }
        } else {
            self.contextPercent = 0
            self.contextTone = .calm
            self.hasContext = false
            self.verdictTitle = "Cold start"
            self.verdictDetail = "no live session yet"
            self.verdictPattern = "open Claude Code or Codex to begin"
        }

        // WINDOWS — surface chips + per-window forecasts
        self.fiveHour = Self.alcoveWindow(from: snapshot, kind: .fiveHour)
        self.weekly = Self.alcoveWindow(from: snapshot, kind: .weekly)
        self.weeklyOpus = Self.alcoveWindow(from: snapshot, kind: .weeklyOpus)
        self.weeklySonnet = Self.alcoveWindow(from: snapshot, kind: .weeklySonnet)
        self.fiveHourForecast = Self.forecastSummary(from: snapshot, model: model, kind: .fiveHour)
        self.weeklyForecast = Self.forecastSummary(from: snapshot, model: model, kind: .weekly)

        // BURN
        let claudeAdvisor = snapshot?.claudeSession?.advisor
        let codexInsight = snapshot?.codexSession?.insight
        self.tokensPerMinute = claudeAdvisor?.tokensPerMinute ?? codexInsight?.tokensPerMinute ?? 0
        self.dollarsPerMinute = claudeAdvisor?.usdPerMinute ?? 0
        self.dailySpendRate = model.recentDailySpendRate()
        if let spend = snapshot?.extraSpend {
            self.spendUsed = spend.used
            self.spendLimit = spend.limit
        } else {
            self.spendUsed = nil
            self.spendLimit = nil
        }
        self.hasBurnData = self.tokensPerMinute > 0 || self.dollarsPerMinute > 0

        // Today's totals
        if let today = snapshot?.today {
            self.turnsToday = today.requests
            self.totalTokensToday = today.totalTokens
            self.activeMinutesToday = today.activeMinutes
            self.spendToday = today.spend?.used
            self.peakHourLabel = today.peakHourLabel
            self.hasTodayData = today.requests > 0 || today.totalTokens > 0
        } else {
            self.turnsToday = 0
            self.totalTokensToday = 0
            self.activeMinutesToday = 0
            self.spendToday = nil
            self.peakHourLabel = nil
            self.hasTodayData = false
        }
        self.planName = snapshot?.planName

        // Per-turn averages — only meaningful with at least one turn.
        if self.turnsToday > 0 {
            if let spend = self.spendToday {
                self.dollarsPerTurnToday = spend / Double(self.turnsToday)
            } else {
                self.dollarsPerTurnToday = nil
            }
            self.tokensPerTurnToday = self.totalTokensToday / self.turnsToday
        } else {
            self.dollarsPerTurnToday = nil
            self.tokensPerTurnToday = 0
        }

        // Monthly projection: month-to-date + (days remaining × daily
        // rate). When we don't have either data point yet, leave nil.
        let calendar = Calendar.current
        let now = Date()
        if let monthRange = calendar.range(of: .day, in: .month, for: now) {
            let totalDays = monthRange.count
            let dayOfMonth = calendar.component(.day, from: now)
            self.daysRemainingInMonth = max(0, totalDays - dayOfMonth)
        } else {
            self.daysRemainingInMonth = 0
        }
        if let used = self.spendUsed,
           let rate = self.dailySpendRate,
           self.daysRemainingInMonth > 0
        {
            self.projectedMonthSpend = used + rate * Double(self.daysRemainingInMonth)
        } else {
            self.projectedMonthSpend = nil
        }

        // Cost section — compute synthetic cost for today's specific input/output
        // breakdown using the pricing of the currently active model. Falls back
        // to the most heavily used model in the mix if no session is active.
        if let agg = snapshot?.claudeAggregate {
            let activeModel = snapshot?.claudeSession?.modelName
                ?? agg.modelMix.first?.modelName
                ?? "sonnet"

            if let today = snapshot?.today, today.totalTokens > 0 {
                self.syntheticCostToday = ClaudePricing.synthesizeUSD(
                    model: activeModel,
                    input: today.inputTokens,
                    output: today.outputTokens,
                    cacheRead: 0,
                    cacheCreate: 0
                )
            } else {
                self.syntheticCostToday = nil
            }

            let lifetimeTokens = agg.lifetimeInputTokens
                + agg.lifetimeOutputTokens
                + agg.lifetimeCacheReadTokens
                + agg.lifetimeCacheCreationTokens
            self.cost30d = agg.lastThirtyDayCostUSD > 0 ? agg.lastThirtyDayCostUSD : nil
            self.tokens30d = agg.lastThirtyDayTokens
            self.costLifetime = agg.lifetimeSyntheticCostUSD > 0 ? agg.lifetimeSyntheticCostUSD : nil
            self.tokensLifetime = lifetimeTokens
        } else {
            self.syntheticCostToday = nil
            self.cost30d = nil
            self.tokens30d = 0
            self.costLifetime = nil
            self.tokensLifetime = 0
        }

        // STREAK
        self.streakDays = snapshot?.streakDays ?? 0
        if let agg = snapshot?.claudeAggregate, agg.lifetimeCacheReadTokens > 0 {
            let denom = max(1, agg.lifetimeInputTokens + agg.lifetimeCacheReadTokens)
            self.cacheHitPercent = Int(Double(agg.lifetimeCacheReadTokens) / Double(denom) * 100)
        } else {
            self.cacheHitPercent = nil
        }
        if let fire = model.fireEvent {
            self.fireActive = true
            self.fireTurnTokens = fire.turnTokens
            self.fireContextPercent = fire.contextUsedPercent
        } else {
            self.fireActive = false
            self.fireTurnTokens = 0
            self.fireContextPercent = 0
        }

        // Turn pattern — feeds the bottom rhythm row.
        let activePattern: MenuBarModel.TurnPattern? = {
            guard let snap = snapshot, let context = snap.workContext else { return nil }
            let p = model.turnPattern(forSessionId: context.sessionId, provider: snap.kind)
            return p.avg > 0 ? p : nil
        }()
        if let pattern = activePattern {
            self.turnAvgTokens = pattern.avg
            self.turnSampleCount = pattern.samples.count
            switch pattern.trend {
            case .up: self.turnTrend = .up
            case .down: self.turnTrend = .down
            case .flat: self.turnTrend = .flat
            }
            self.hasTurnPattern = true
        } else {
            self.turnAvgTokens = 0
            self.turnSampleCount = 0
            self.turnTrend = .flat
            self.hasTurnPattern = false
        }

        // Concurrent sessions — aggregate across BOTH providers so the
        // counter reflects total live activity, not just the currently
        // selected provider's. If you're viewing Claude but have 2
        // Codex sessions burning too, all 4 should appear.
        let allLive = model.overview.snapshots.flatMap(\.liveSessions)
        self.liveSessionCount = allLive.count
        self.liveSessionProjects = allLive
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
            .map(\.projectName)

        // Claude-only live sessions — these are pinnable. The picker
        // menu in AlcoveTopRow uses this list to offer "switch to
        // this project" entries. Sorted by sessionId (stable UUID
        // order) rather than lastActivityAt so the pill positions
        // don't jump around every poll when activity timestamps shift
        // — pinning would otherwise yank the active session to the
        // top of the column.
        let claudeSnap = model.overview.snapshot(for: .claude)
        self.liveClaudeSessions = (claudeSnap?.liveSessions ?? [])
            .sorted { $0.sessionId < $1.sessionId }

        // Advisor — Claude's ClaudeAdvisor and Codex's
        // CodexSessionInsight share the same shape (health,
        // recommendation, primaryDriver, driverDetail, forecast,
        // resetPlan, lastTurnSharePercent, projectedTurnsRemaining).
        if let advisor = snapshot?.claudeSession?.advisor {
            self.applyAdvisor(
                health: advisor.health,
                recommendation: advisor.recommendation,
                primaryDriver: advisor.primaryDriver,
                driverDetail: advisor.driverDetail,
                forecast: advisor.forecast,
                resetPlan: advisor.resetPlan,
                lastTurnShare: advisor.lastTurnSharePercent,
                projectedTurns: advisor.projectedTurnsRemaining)
        } else if let insight = snapshot?.codexSession?.insight {
            self.applyAdvisor(
                health: insight.health,
                recommendation: insight.recommendation,
                primaryDriver: insight.primaryDriver,
                driverDetail: insight.driverDetail,
                forecast: insight.forecast,
                resetPlan: insight.resetPlan,
                lastTurnShare: insight.lastTurnSharePercent,
                projectedTurns: insight.projectedTurnsRemaining)
        } else {
            self.advisorHealthTitle = ""
            self.advisorIconName = "checkmark.seal"
            self.advisorTone = .calm
            self.advisorRecommendation = ""
            self.advisorPrimaryDriver = ""
            self.advisorDriverDetail = ""
            self.advisorForecast = ""
            self.advisorResetPlan = ""
            self.advisorLastTurnShare = 0
            self.advisorProjectedTurns = nil
            self.hasAdvisor = false
        }

        // Depleted takeover
        if let depleted = snapshot?.windows.first(where: { $0.usedPercent >= 99 && $0.resetsAt != nil }) {
            self.depletedTitle = "\(Self.windowLabel(for: depleted)) depleted"
            self.depletedCountdown = Self.countdown(to: depleted.resetsAt)
            self.depletedClock = Self.clockText(from: depleted.resetsAt)
        } else {
            self.depletedTitle = nil
            self.depletedCountdown = nil
            self.depletedClock = nil
        }

        // Ambient cue — only painted when something's actually warm. Below
        // 75% the closed notch stays untouched (NotchNook-style: empty
        // unless there's a reason to interrupt).
        if self.depletedTitle != nil {
            self.ambientCueColor = NotchPalette.danger
        } else if self.contextPercent >= 75 {
            self.ambientCueColor = NotchPalette.tone(self.contextTone)
        } else if let f = self.fiveHour, f.percent >= 75 {
            self.ambientCueColor = NotchPalette.tone(f.tone)
        } else if let w = self.weekly, w.percent >= 85 {
            self.ambientCueColor = NotchPalette.tone(w.tone)
        } else {
            self.ambientCueColor = nil
        }
        self.thresholdAlert = self.computeThresholdAlert()
    }

    private func computeThresholdAlert(now: Date = Date()) -> NotchThresholdAlert? {
        if let title = self.depletedTitle {
            let back = self.depletedCountdown.map { "back in \($0)" }
                ?? self.depletedClock
                ?? "reset pending"
            return NotchThresholdAlert(
                id: "depleted-\(title)",
                title: "BURST DEPLETED",
                detail: back,
                symbol: "lock.fill",
                tone: .tight)
        }

        if let forecast = self.fiveHourForecast,
           let runsOutAt = forecast.runsOutAt,
           runsOutAt > now
        {
            let minutes = max(1, Int(ceil(runsOutAt.timeIntervalSince(now) / 60)))
            if minutes <= 15 {
                let bucket = minutes <= 5 ? 5 : (minutes <= 10 ? 10 : 15)
                return NotchThresholdAlert(
                    id: "burst-runout-\(bucket)",
                    title: "BURST IN \(minutes)m",
                    detail: "Slow down; 5h cap is projected to hit.",
                    symbol: "flame.fill",
                    tone: minutes <= 5 ? .tight : .watch)
            }
        }

        if let fiveHour = self.fiveHour {
            if fiveHour.percent >= 95 {
                return NotchThresholdAlert(
                    id: "burst-used-95",
                    title: "BURST HOT",
                    detail: "\(Int(fiveHour.percent.rounded()))% used · \(fiveHour.resetText) left",
                    symbol: "bolt.trianglebadge.exclamationmark.fill",
                    tone: .tight)
            }
            if fiveHour.percent >= 85 {
                return NotchThresholdAlert(
                    id: "burst-used-85",
                    title: "BURST CLIMBING",
                    detail: "\(Int(fiveHour.percent.rounded()))% used · pace the next turns",
                    symbol: "speedometer",
                    tone: .watch)
            }
        }

        if self.hasContext {
            if self.contextPercent >= 86 {
                return NotchThresholdAlert(
                    id: "context-86",
                    title: "CONTEXT TIGHT",
                    detail: "\(Int(self.contextPercent.rounded()))% used · compact soon",
                    symbol: "text.badge.exclamationmark",
                    tone: .tight)
            }
            if self.contextPercent >= 75 {
                return NotchThresholdAlert(
                    id: "context-75",
                    title: "CONTEXT HEATING",
                    detail: "\(Int(self.contextPercent.rounded()))% used · keep the next ask focused",
                    symbol: "eye.fill",
                    tone: .watch)
            }
        }

        if let weekly = self.weekly, weekly.percent >= 92 {
            return NotchThresholdAlert(
                id: "weekly-92",
                title: "WEEKLY CAP HOT",
                detail: "\(Int(weekly.percent.rounded()))% used · reset \(weekly.resetText)",
                symbol: "calendar.badge.exclamationmark",
                tone: weekly.percent >= 97 ? .tight : .watch)
        }

        if let projected = self.projectedMonthSpend,
           let limit = self.spendLimit,
           limit > 0,
           projected > limit
        {
            return NotchThresholdAlert(
                id: "spend-projected-over",
                title: "SPEND CAP TRACKING",
                detail: "on pace for \(String(format: "$%.0f", projected)) of \(String(format: "$%.0f", limit))",
                symbol: "dollarsign.circle.fill",
                tone: .watch)
        }

        if self.fireActive {
            return NotchThresholdAlert(
                id: "fire-\(self.fireTurnTokens)",
                title: "BIG TURN",
                detail: "\(compactTokens(self.fireTurnTokens)) tokens · \(Int(self.fireContextPercent.rounded()))% context",
                symbol: "flame.fill",
                tone: .tight)
        }

        return nil
    }

    // MARK: - Advisor helper

    /// Folds Claude's `ClaudeAdvisor` and Codex's `CodexSessionInsight`
    /// (which share the same shape) into the display fields. Health
    /// drives the verdict word, the icon, and the tone color the
    /// alcove uses to paint the advisor block.
    private func applyAdvisor(
        health: CodexThreadHealth,
        recommendation: String,
        primaryDriver: String,
        driverDetail: String,
        forecast: String,
        resetPlan: String,
        lastTurnShare: Double,
        projectedTurns: Int?)
    {
        self.advisorHealthTitle = health.title
        self.advisorIconName = Self.iconName(for: health)
        self.advisorTone = UsageTone(health: health)
        self.advisorRecommendation = recommendation
        self.advisorPrimaryDriver = primaryDriver
        self.advisorDriverDetail = driverDetail
        self.advisorForecast = forecast
        self.advisorResetPlan = resetPlan
        self.advisorLastTurnShare = lastTurnShare
        self.advisorProjectedTurns = projectedTurns
        self.hasAdvisor = true
    }

    private static func iconName(for health: CodexThreadHealth) -> String {
        switch health {
        case .efficient: "bolt.badge.checkmark"
        case .healthy: "checkmark.seal.fill"
        case .watch: "eye.fill"
        case .tight: "exclamationmark.triangle.fill"
        case .stuck: "wrench.and.screwdriver.fill"
        }
    }

    // MARK: - Window helpers

    private enum WindowKind { case fiveHour, weekly, weeklyOpus, weeklySonnet }

    private static func alcoveWindow(from snapshot: ProviderUsageSnapshot?, kind: WindowKind) -> AlcoveWindow? {
        guard let window = self.matchedWindow(from: snapshot, kind: kind) else { return nil }
        let label: String
        let longLabel: String
        switch kind {
        case .fiveHour:    label = "5H";  longLabel = "5h burst"
        case .weekly:      label = "7D";  longLabel = "Weekly"
        case .weeklyOpus:  label = "OPUS";   longLabel = "Weekly Opus"
        case .weeklySonnet: label = "SONNET"; longLabel = "Weekly Sonnet"
        }
        return AlcoveWindow(
            label: label,
            longLabel: longLabel,
            percent: window.usedPercent,
            tone: UsageTone(percent: window.usedPercent),
            resetText: shortReset(for: window.resetsAt),
            resetsAt: window.resetsAt)
    }

    private static func forecastSummary(from snapshot: ProviderUsageSnapshot?, model: MenuBarModel, kind: WindowKind) -> WindowForecastSummary? {
        guard let window = self.matchedWindow(from: snapshot, kind: kind),
              let f = model.forecast(for: window)
        else { return nil }
        return WindowForecastSummary(
            aheadOfPacePercent: f.aheadOfPacePercent,
            projectedAtResetPercent: f.projectedAtResetPercent,
            runsOutAt: f.runsOutAt,
            runsOutText: Self.runsOutText(f.runsOutAt))
    }

    private static func matchedWindow(from snapshot: ProviderUsageSnapshot?, kind: WindowKind) -> UsageWindow? {
        guard let windows = snapshot?.windows else { return nil }
        switch kind {
        case .fiveHour:
            return windows.first(where: {
                let id = $0.id.lowercased()
                let title = $0.title.lowercased()
                return id.contains("5h") || id.contains("primary")
                    || title == "session" || title == "5h"
            })
        case .weekly:
            return windows.first(where: {
                let id = $0.id.lowercased()
                let title = $0.title.lowercased()
                guard !id.contains("opus"), !id.contains("sonnet") else { return false }
                return id.contains("7d") || id.contains("weekly") || title.contains("week")
            })
        case .weeklyOpus:
            return windows.first(where: {
                let id = $0.id.lowercased()
                let title = $0.title.lowercased()
                return id.contains("opus") || title.contains("opus")
            })
        case .weeklySonnet:
            return windows.first(where: {
                let id = $0.id.lowercased()
                let title = $0.title.lowercased()
                return id.contains("sonnet") || title.contains("sonnet")
            })
        }
    }

    private static func windowLabel(for window: UsageWindow) -> String {
        let id = window.id.lowercased()
        if id.contains("5h") || id.contains("primary") || window.title.lowercased() == "session" {
            return "5h burst"
        }
        if id.contains("opus") { return "Weekly Opus" }
        if id.contains("sonnet") { return "Weekly Sonnet" }
        return "Weekly"
    }

    private static func runsOutText(_ date: Date?) -> String? {
        guard let date else { return nil }
        let secs = max(0, Int(date.timeIntervalSinceNow))
        if secs < 60 { return "out any second" }
        if secs < 3600 { return "out in \(secs / 60)m" }
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h < 24 { return m > 0 ? "out in \(h)h \(m)m" : "out in \(h)h" }
        return "out in \(h / 24)d"
    }

    // MARK: - Verdict copy

    private static func verdictTitle(percent: Double, turnsLeft: Int) -> String {
        if turnsLeft == 0 { return "Out of room" }
        if percent >= 92 { return "Critical" }
        if percent >= 82 { return "Tight" }
        if percent >= 60 { return "Hot run" }
        if percent >= 30 { return "Cruising" }
        return "Fresh start"
    }

    private static func verdictDetail(turnsLeft: Int) -> String {
        if turnsLeft <= 0 { return "compact or wrap this thread" }
        if turnsLeft == 1 { return "1 turn left at your pace" }
        return "~\(turnsLeft) turns at your pace"
    }

    private static func verdictPattern(pattern: MenuBarModel.TurnPattern) -> String {
        let trendArrow: String
        switch pattern.trend {
        case .up: trendArrow = " ↑"
        case .down: trendArrow = " ↓"
        case .flat: trendArrow = ""
        }
        let plural = pattern.samples.count == 1 ? "" : "s"
        return "pattern: \(pattern.samples.count) turn\(plural)\(trendArrow)"
    }

    // MARK: - Time helpers

    /// Compress full model identifiers into a short readable label.
    /// "claude-sonnet-4-5-20251001" → "sonnet 4.5"
    /// "claude-opus-4-7" → "opus 4.7"
    /// Returns nil when there's nothing useful to show.
    private static func shortModelLabel(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let lower = raw.lowercased()
        let family: String
        if lower.contains("opus") { family = "opus" }
        else if lower.contains("sonnet") { family = "sonnet" }
        else if lower.contains("haiku") { family = "haiku" }
        else if lower.contains("gpt") { family = "gpt" }
        else { family = lower.split(separator: "-").first.map(String.init) ?? lower }

        // Walk dash-separated parts after the family name, picking up
        // 1- or 2-digit numeric segments as the version. Stops at the
        // first non-numeric/long segment (e.g. "20251001").
        let parts = lower.split(separator: "-").map(String.init)
        var versionParts: [String] = []
        var afterFamily = false
        for part in parts {
            if part == family { afterFamily = true; continue }
            guard afterFamily else { continue }
            if part.count <= 2, Int(part) != nil {
                versionParts.append(part)
            } else if !versionParts.isEmpty {
                break
            }
        }
        if versionParts.isEmpty { return family }
        return "\(family) \(versionParts.joined(separator: "."))"
    }

    private static func sessionDurationText(snapshot: ProviderUsageSnapshot?) -> String {
        let start: Date?
        if let claude = snapshot?.claudeSession {
            start = claude.sessionStartedAt ?? claude.lastActivityAt
        } else if let codex = snapshot?.codexSession {
            start = codex.sessionStartedAt ?? codex.lastActivityAt
        } else {
            start = nil
        }
        guard let start else { return "" }
        let secs = max(0, Int(Date().timeIntervalSince(start)))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private static func shortReset(for date: Date?) -> String {
        guard let date else { return "—" }
        let secs = max(0, Int(date.timeIntervalSinceNow))
        if secs < 3600 { return "\(secs / 60)m" }
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h < 24 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(h / 24)d"
    }

    private static func countdown(to date: Date?) -> String {
        guard let date else { return "—" }
        let secs = max(0, Int(date.timeIntervalSinceNow))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private static func clockText(from date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "back at \(formatter.string(from: date))"
    }

    private static func isLive(snapshot: ProviderUsageSnapshot?) -> Bool {
        guard let snapshot else { return false }
        let now = Date()
        if let claude = snapshot.claudeSession?.lastActivityAt {
            return now.timeIntervalSince(claude) < 120
        }
        if let codex = snapshot.codexSession?.lastActivityAt {
            return now.timeIntervalSince(codex) < 120
        }
        return false
    }
}

// MARK: - NSPanel

private final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        self.hasShadow = false
        self.backgroundColor = .clear
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.isMovable = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - SwiftUI host (notch silhouette + morph + content)

private struct NotchMorphHost: View {
    let state: NotchDisplayState
    let model: MenuBarModel
    /// Auto-detected notch size from NSScreen at panel creation time.
    /// User overrides flow through model.notchWidthOverride and become
    /// the rendered notchWidth/Height live (without panel rebuild).
    let detectedNotchWidth: CGFloat
    let detectedNotchHeight: CGFloat

    private var notchWidth: CGFloat {
        self.model.notchWidthOverride.map { CGFloat($0) } ?? self.detectedNotchWidth
    }
    private var notchHeight: CGFloat {
        self.model.notchHeightOverride.map { CGFloat($0) } ?? self.detectedNotchHeight
    }

    @State private var alcoveWidth: CGFloat = 200
    @State private var alcoveHeight: CGFloat = 38
    @State private var alcoveTopRadius: CGFloat = 6
    @State private var alcoveBottomRadius: CGFloat = 14
    @State private var alcoveScale: CGFloat = 1
    @State private var didInitGeometry = false

    @State private var isHovering = false
    @State private var hoverIntentTask: Task<Void, Never>?
    @State private var visibleAlert: NotchThresholdAlert?
    @State private var lastPresentedAlertID: String?
    @State private var alertDismissTask: Task<Void, Never>?
    @State private var dragStartWidth: CGFloat?
    @State private var dragStartHeight: CGFloat?
    /// Measured height of the alcove's open-state content (TopRow +
    /// AlcoveContent) — drives the dynamic drawer fit. Updated via
    /// `ContentSizeKey` preference; never below `minOpenHeight`,
    /// never above `maxDrawerHeight + notchHeight`.
    @State private var measuredContentHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isCalibrating: Bool { self.model.notchCalibrating }

    static let maxWidth: CGFloat = 580
    /// Upper cap on drawer height. The alcove auto-fits to its
    /// measured content via ContentSizeKey, so this is just the
    /// safety ceiling — content beyond this will be clipped, but in
    /// practice the natural fit lands well below it.
    static let maxDrawerHeight: CGFloat = 420
    /// Floor on the open height so very-empty states don't collapse
    /// into a sliver before the snapshot has populated.
    static let minOpenHeight: CGFloat = 140
    static let hoverIntentDelay: Duration = .milliseconds(180)

    private var choreography: AlcoveChoreography { self.model.alcoveChoreography }
    private var spring: AlcoveSpring { self.model.alcoveSpring }

    private var finalWidth: CGFloat { Self.maxWidth }
    /// Open-state alcove height — auto-fits to the measured content,
    /// clamped between `minOpenHeight` and `notchHeight + maxDrawerHeight`.
    /// Falls back to maxDrawerHeight when measurement hasn't fired yet
    /// so the first hover doesn't snap to a tiny sliver.
    private var finalHeight: CGFloat {
        let cap = self.notchHeight + Self.maxDrawerHeight
        let measured = self.measuredContentHeight
        if measured <= 0 { return cap }
        return min(cap, max(Self.minOpenHeight, measured))
    }

    private var contentTransition: AnyTransition {
        if self.reduceMotion {
            return .opacity.animation(.linear(duration: 0.05))
        }

        let delay = min(0.12, self.choreography.totalDuration * 0.25)
        return .asymmetric(
            insertion: .modifier(
                active: BlurTransitionModifier(isActive: true),
                identity: BlurTransitionModifier(isActive: false)
            )
            .combined(with: .offset(y: -4))
            .animation(.spring(duration: 0.22, bounce: 0.03).delay(delay)),
            removal: .opacity
                .animation(.easeIn(duration: 0.06))
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(.black)
                .frame(width: self.alcoveWidth, height: self.alcoveHeight)
                .mask {
                    NotchShape(
                        topCornerRadius: self.alcoveTopRadius,
                        bottomCornerRadius: self.alcoveBottomRadius)
                    .frame(width: self.alcoveWidth, height: self.alcoveHeight)
                }
                .overlay(alignment: .top) {
                    if self.isHovering {
                        VStack(spacing: 0) {
                            AlcoveTopRow(
                                state: self.state,
                                model: self.model,
                                notchWidth: self.notchWidth,
                                notchHeight: self.notchHeight)
                                .padding(.horizontal, 24)
                                .frame(width: self.alcoveWidth, height: self.notchHeight)

                            AlcoveContent(
                                state: self.state,
                                model: self.model,
                                reduceMotion: self.reduceMotion,
                                onTriggerDebugAlert: self.presentDebugAlert)
                                .padding(.horizontal, 32)
                                .padding(.top, 10)
                                .padding(.bottom, 18)
                                .frame(width: self.alcoveWidth)
                        }
                        .background {
                            // Measure the actual rendered height so the
                            // drawer can auto-fit. Color.clear preserves
                            // the visual; only the GeometryReader's
                            // size signal matters.
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: ContentSizeKey.self,
                                    value: geo.size.height)
                            }
                        }
                        .transition(self.contentTransition)
                    }
                }
                .overlay {
                    // Calibration outline traces the notch shape in
                    // accent so the user can see exactly what they're
                    // resizing.
                    if self.isCalibrating, !self.isHovering {
                        NotchShape(
                            topCornerRadius: self.alcoveTopRadius,
                            bottomCornerRadius: self.alcoveBottomRadius)
                            .stroke(NotchPalette.accent, lineWidth: 1.5)
                            .frame(width: self.alcoveWidth, height: self.alcoveHeight)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if self.isCalibrating, !self.isHovering {
                        CalibrationHandle()
                            .offset(x: 4, y: 4)
                            .gesture(self.makeDragGesture(rightSide: true))
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if self.isCalibrating, !self.isHovering {
                        CalibrationHandle()
                            .offset(x: -4, y: 4)
                            .gesture(self.makeDragGesture(rightSide: false))
                    }
                }
                .overlay(alignment: .bottom) {
                    // Closed-state ambient hairline. Sits inside the
                    // bottom edge of the notch silhouette when warm —
                    // glance value without hovering.
                    if !self.isHovering, !self.isCalibrating,
                       let cue = self.state.ambientCueColor
                    {
                        Capsule()
                            .fill(cue)
                            .frame(
                                width: max(20, self.notchWidth - 18),
                                height: 1.5)
                            .opacity(0.78)
                            .offset(y: -3)
                            .transition(.opacity.animation(.easeOut(duration: 0.25)))
                    }
                }
                .scaleEffect(self.alcoveScale, anchor: .top)
                .onHover(perform: self.handleHover)

            // Floating badge below the notch, only while calibrating.
            // Sits in the panel area below the menu bar so the user can
            // read dimensions and click DONE without obscuring the
            // silhouette they're resizing.
            if self.isCalibrating, !self.isHovering {
                CalibrationBadge(
                    width: self.notchWidth,
                    height: self.notchHeight,
                    onDone: {
                        HapticGate.perform(.levelChange)
                        self.model.commitNotchCalibration()
                    },
                    onReset: {
                        HapticGate.perform(.alignment)
                        self.model.setNotchWidthOverride(nil)
                        self.model.setNotchHeightOverride(nil)
                    }
                )
                .offset(y: self.alcoveHeight + 14)
            }

            if let alert = self.visibleAlert, !self.isHovering, !self.isCalibrating {
                NotchThresholdToast(alert: alert)
                    .offset(y: self.notchHeight + 12)
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .scale(scale: 0.96, anchor: .top))
                                .combined(with: .offset(y: -6)),
                            removal: .opacity
                                .combined(with: .offset(y: -4))))
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onPreferenceChange(ContentSizeKey.self) { newHeight in
            // Auto-fit the drawer to its content. Bound by min/max
            // safety values; only animates `alcoveHeight` while the
            // alcove is open so the morph-close animation isn't
            // interrupted by a measurement late in life.
            guard newHeight > 0 else { return }
            self.measuredContentHeight = newHeight
            if self.isHovering {
                let target = self.finalHeight
                if abs(self.alcoveHeight - target) > 0.5 {
                    let anim: Animation = self.reduceMotion
                        ? .linear(duration: 0.05)
                        : .spring(duration: 0.28, bounce: 0.06)
                    withAnimation(anim) {
                        self.alcoveHeight = target
                    }
                }
            }
        }
        .onAppear {
            if !self.didInitGeometry {
                self.alcoveWidth = self.notchWidth
                self.alcoveHeight = self.notchHeight
                self.didInitGeometry = true
            }
            self.presentThresholdAlertIfNeeded(self.state.thresholdAlert)
        }
        .onChange(of: self.state.thresholdAlert?.id) { _, _ in
            self.presentThresholdAlertIfNeeded(self.state.thresholdAlert)
        }
        .onChange(of: self.isCalibrating) { _, newValue in
            // Entering calibration mode auto-closes the alcove so the
            // user can see and grab the closed-notch silhouette to drag.
            if newValue, self.isHovering {
                self.closeAlcove()
            }
        }
        .onChange(of: self.notchWidth) { _, newWidth in
            // Reflect live override changes (calibration drag) into the
            // closed-state silhouette dimensions so the user sees the
            // shape resize under their cursor.
            if !self.isHovering {
                self.alcoveWidth = newWidth
            }
        }
        .onChange(of: self.notchHeight) { _, newHeight in
            if !self.isHovering {
                self.alcoveHeight = newHeight
            }
        }
    }

    private func presentThresholdAlertIfNeeded(_ alert: NotchThresholdAlert?) {
        guard let alert else {
            self.lastPresentedAlertID = nil
            self.dismissThresholdAlert()
            return
        }
        guard alert.id != self.lastPresentedAlertID else { return }
        guard !self.isHovering, !self.isCalibrating else { return }
        self.showThresholdAlert(alert)
    }

    private func presentDebugAlert(_ alert: NotchThresholdAlert) {
        self.lastPresentedAlertID = nil
        self.closeAlcove()
        self.alertDismissTask?.cancel()
        Task { @MainActor in
            try? await Task.sleep(for: self.reduceMotion ? .milliseconds(60) : .milliseconds(180))
            if self.isCalibrating { return }
            self.showThresholdAlert(alert)
        }
    }

    private func showThresholdAlert(_ alert: NotchThresholdAlert) {
        self.lastPresentedAlertID = alert.id
        self.alertDismissTask?.cancel()
        let show: Animation = self.reduceMotion
            ? .linear(duration: 0.05)
            : .spring(duration: 0.24, bounce: 0.18)
        withAnimation(show) {
            self.visibleAlert = alert
        }
        HapticGate.perform(.levelChange)

        self.alertDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            if Task.isCancelled { return }
            self.dismissThresholdAlert()
        }
    }

    private func dismissThresholdAlert() {
        self.alertDismissTask?.cancel()
        let hide: Animation = self.reduceMotion
            ? .linear(duration: 0.05)
            : .easeOut(duration: 0.18)
        withAnimation(hide) {
            self.visibleAlert = nil
        }
    }

    private func makeDragGesture(rightSide: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if self.dragStartWidth == nil {
                    self.dragStartWidth = self.notchWidth
                }
                if self.dragStartHeight == nil {
                    self.dragStartHeight = self.notchHeight
                }
                guard let startW = self.dragStartWidth,
                      let startH = self.dragStartHeight
                else { return }
                // Symmetric width — the notch is centered, so dragging
                // either bottom corner outward grows both sides equally.
                let widthDelta = rightSide
                    ? value.translation.width
                    : -value.translation.width
                let newW = max(60, min(500, startW + 2 * widthDelta))
                let newH = max(20, min(80, startH + value.translation.height))
                self.model.setNotchSizeLive(width: newW, height: newH)
            }
            .onEnded { _ in
                self.dragStartWidth = nil
                self.dragStartHeight = nil
            }
    }

    private func handleHover(_ hovering: Bool) {
        // Calibration takes over the notch silhouette — drags shouldn't
        // be interrupted by the alcove popping open under the cursor.
        if self.model.notchCalibrating { return }
        self.hoverIntentTask?.cancel()
        if hovering {
            self.hoverIntentTask = Task { @MainActor in
                try? await Task.sleep(for: Self.hoverIntentDelay)
                if Task.isCancelled { return }
                self.openAlcove()
            }
        } else {
            self.closeAlcove()
        }
    }

    private func openAlcove() {
        if self.isHovering { return }
        self.dismissThresholdAlert()
        self.isHovering = true

        if !self.reduceMotion {
            HapticGate.perform(.alignment)
        }

        if self.reduceMotion {
            self.snapToOpen()
            return
        }

        switch self.choreography {
        case .morph: self.openMorph()
        case .cascade: self.openCascade()
        case .curtain: self.openCurtain()
        case .iris: self.openIris()
        case .unfold: self.openUnfold()
        case .bloom: self.openBloom()
        case .swell: self.openSwell()
        case .drip: self.openDrip()
        case .squeeze: self.openSqueeze()
        case .press: self.openPress()
        case .stagger: self.openStagger()
        case .ripple: self.openRipple()
        case .balloon: self.openBalloon()
        case .wobble: self.openWobble()
        case .echo: self.openEcho()
        case .fall: self.openFall()
        case .rebound: self.openRebound()
        case .jelly: self.openJelly()
        case .fountain: self.openFountain()
        case .liquid: self.openLiquid()
        }
    }

    private func closeAlcove() {
        let wasOpen = self.isHovering
        let exit: Animation = self.reduceMotion
            ? .linear(duration: 0.05)
            : .spring(duration: 0.16, bounce: 0)
        withAnimation(exit) {
            self.isHovering = false
            self.alcoveWidth = self.notchWidth
            self.alcoveHeight = self.notchHeight
            self.alcoveTopRadius = 6
            self.alcoveBottomRadius = 14
            self.alcoveScale = 1
        }
        // Clear any preview that survived the hover-out so the next
        // open lands on pin / auto cleanly. Polling itself stays
        // running — the pill hover is what gates it now.
        self.model.setPreviewClaudeSessionId(nil)
        // Light tick on close, but only if we were actually open —
        // intent-debounce cancels shouldn't fire haptics.
        if wasOpen {
            HapticGate.perform(.alignment)
        }
    }

    private func snapToOpen() {
        self.alcoveWidth = self.finalWidth
        self.alcoveHeight = self.finalHeight
        self.alcoveTopRadius = 14
        self.alcoveBottomRadius = 22
        self.alcoveScale = 1
    }

    // MARK: - Choreographies (unchanged)

    private var base: Animation { self.spring.baseSpring(for: self.choreography) }

    private func openMorph() {
        withAnimation(self.base) {
            self.alcoveWidth = self.finalWidth
            self.alcoveHeight = self.finalHeight
            self.alcoveTopRadius = 14
            self.alcoveBottomRadius = 22
        }
    }

    private func openCascade() {
        withAnimation(self.base) {
            self.alcoveHeight = self.finalHeight
            self.alcoveBottomRadius = 22
        }
        withAnimation(self.base.delay(0.08)) {
            self.alcoveWidth = self.finalWidth
            self.alcoveTopRadius = 14
        }
    }

    private func openCurtain() {
        withAnimation(self.base) {
            self.alcoveWidth = self.finalWidth
            self.alcoveTopRadius = 14
        }
        withAnimation(self.base.delay(0.08)) {
            self.alcoveHeight = self.finalHeight
            self.alcoveBottomRadius = 22
        }
    }

    private func openIris() {
        self.alcoveWidth = self.finalWidth
        self.alcoveHeight = self.finalHeight
        self.alcoveTopRadius = 14
        self.alcoveBottomRadius = 22
        self.alcoveScale = 0.45
        withAnimation(self.base) { self.alcoveScale = 1 }
    }

    private func openUnfold() {
        self.alcoveWidth = self.finalWidth
        self.alcoveTopRadius = 14
        withAnimation(self.base) {
            self.alcoveHeight = self.finalHeight
            self.alcoveBottomRadius = 22
        }
    }

    private func openBloom() {
        withAnimation(self.base) {
            self.alcoveTopRadius = 14
            self.alcoveBottomRadius = 22
        }
        withAnimation(self.base.delay(0.10)) {
            self.alcoveWidth = self.finalWidth
            self.alcoveHeight = self.finalHeight
        }
    }

    private func openSwell() {
        let overshoot: CGFloat = 32
        withAnimation(self.base) {
            self.alcoveWidth = self.finalWidth + overshoot
            self.alcoveHeight = self.finalHeight
            self.alcoveTopRadius = 14
            self.alcoveBottomRadius = 22
        }
        withAnimation(.spring(duration: 0.34, bounce: 0.08).delay(0.18)) {
            self.alcoveWidth = self.finalWidth
        }
    }

    private func openDrip() {
        withAnimation(self.base) {
            self.alcoveWidth = self.finalWidth
            self.alcoveTopRadius = 14
        }
        withAnimation(.spring(duration: 0.50, bounce: 0.42).delay(0.06)) {
            self.alcoveHeight = self.finalHeight
            self.alcoveBottomRadius = 22
        }
    }

    private func openSqueeze() {
        withAnimation(.spring(duration: 0.12, bounce: 0)) {
            self.alcoveWidth = max(40, self.notchWidth - 30)
        }
        withAnimation(self.base.delay(0.10)) {
            self.alcoveWidth = self.finalWidth
            self.alcoveHeight = self.finalHeight
            self.alcoveTopRadius = 14
            self.alcoveBottomRadius = 22
        }
    }

    private func openPress() {
        withAnimation(.spring(duration: 0.10, bounce: 0)) {
            self.alcoveTopRadius = 2
            self.alcoveBottomRadius = 8
        }
        withAnimation(self.base.delay(0.10)) {
            self.alcoveWidth = self.finalWidth
            self.alcoveHeight = self.finalHeight
            self.alcoveTopRadius = 14
            self.alcoveBottomRadius = 22
        }
    }

    private func openStagger() {
        withAnimation(self.base) {
            self.alcoveTopRadius = 14
            self.alcoveBottomRadius = 22
        }
        withAnimation(self.base.delay(0.07)) {
            self.alcoveWidth = self.finalWidth
        }
        withAnimation(self.base.delay(0.16)) {
            self.alcoveHeight = self.finalHeight
        }
    }

    private func openRipple() {
        withAnimation(.spring(duration: 0.20, bounce: 0.10)) {
            self.alcoveBottomRadius = 22
        }
        withAnimation(.spring(duration: 0.22, bounce: 0.10).delay(0.06)) {
            self.alcoveTopRadius = 14
        }
        withAnimation(self.base.delay(0.14)) {
            self.alcoveWidth = self.finalWidth
            self.alcoveHeight = self.finalHeight
        }
    }

    private func openBalloon() {
        let widthOver: CGFloat = 22
        let heightOver: CGFloat = 14
        withAnimation(self.base) {
            self.alcoveWidth = self.finalWidth + widthOver
            self.alcoveHeight = self.finalHeight + heightOver
            self.alcoveTopRadius = 14
            self.alcoveBottomRadius = 22
        }
        withAnimation(.spring(duration: 0.34, bounce: 0.10).delay(0.18)) {
            self.alcoveWidth = self.finalWidth
            self.alcoveHeight = self.finalHeight
        }
    }

    private func openWobble() {
        withAnimation(.spring(duration: 0.20, bounce: 0)) {
            self.alcoveWidth = self.finalWidth + 24
            self.alcoveHeight = self.finalHeight + 12
            self.alcoveTopRadius = 14
            self.alcoveBottomRadius = 22
        }
        withAnimation(.spring(duration: 0.16, bounce: 0).delay(0.12)) {
            self.alcoveWidth = self.finalWidth - 8
            self.alcoveHeight = self.finalHeight - 4
        }
        withAnimation(.spring(duration: 0.18, bounce: 0).delay(0.24)) {
            self.alcoveWidth = self.finalWidth
            self.alcoveHeight = self.finalHeight
        }
    }

    private func openEcho() {
        withAnimation(.spring(duration: 0.18, bounce: 0)) {
            self.alcoveWidth = self.finalWidth
            self.alcoveHeight = self.finalHeight
            self.alcoveTopRadius = 14
            self.alcoveBottomRadius = 22
        }
        withAnimation(.spring(duration: 0.16, bounce: 0).delay(0.16)) {
            self.alcoveWidth = self.finalWidth - 16
            self.alcoveHeight = self.finalHeight - 8
        }
        withAnimation(.spring(duration: 0.20, bounce: 0.05).delay(0.30)) {
            self.alcoveWidth = self.finalWidth
            self.alcoveHeight = self.finalHeight
        }
    }

    private func openFall() {
        withAnimation(self.base) {
            self.alcoveWidth = self.finalWidth
            self.alcoveTopRadius = 14
        }
        withAnimation(.spring(duration: 0.30, bounce: 0)) {
            self.alcoveHeight = self.finalHeight + 18
            self.alcoveBottomRadius = 22
        }
        withAnimation(.spring(duration: 0.20, bounce: 0).delay(0.22)) {
            self.alcoveHeight = self.finalHeight
        }
    }

    private func openRebound() {
        withAnimation(self.base) {
            self.alcoveWidth = self.finalWidth
            self.alcoveTopRadius = 14
        }
        withAnimation(.spring(duration: 0.24, bounce: 0)) {
            self.alcoveHeight = self.finalHeight + 30
            self.alcoveBottomRadius = 22
        }
        withAnimation(.spring(duration: 0.22, bounce: 0.30).delay(0.18)) {
            self.alcoveHeight = self.finalHeight
        }
    }

    private func openJelly() {
        withAnimation(.spring(duration: 0.22, bounce: 0.05)) {
            self.alcoveWidth = self.finalWidth + 18
            self.alcoveTopRadius = 14
        }
        withAnimation(.spring(duration: 0.28, bounce: 0.18).delay(0.10)) {
            self.alcoveHeight = self.finalHeight
            self.alcoveBottomRadius = 22
        }
        withAnimation(.spring(duration: 0.22, bounce: 0.05).delay(0.14)) {
            self.alcoveWidth = self.finalWidth
        }
    }

    private func openFountain() {
        withAnimation(.spring(duration: 0.24, bounce: 0.20)) {
            self.alcoveHeight = self.finalHeight
            self.alcoveBottomRadius = 22
        }
        withAnimation(self.base.delay(0.06)) {
            self.alcoveWidth = self.finalWidth + 18
            self.alcoveTopRadius = 14
        }
        withAnimation(.spring(duration: 0.20, bounce: 0).delay(0.20)) {
            self.alcoveWidth = self.finalWidth
        }
    }

    private func openLiquid() {
        withAnimation(.spring(duration: 0.24, bounce: 0.15)) {
            self.alcoveWidth = self.finalWidth + 24
            self.alcoveTopRadius = 14
        }
        withAnimation(.spring(duration: 0.28, bounce: 0.18).delay(0.08)) {
            self.alcoveHeight = self.finalHeight + 14
            self.alcoveBottomRadius = 22
        }
        withAnimation(.spring(duration: 0.30, bounce: 0.10).delay(0.22)) {
            self.alcoveWidth = self.finalWidth
            self.alcoveHeight = self.finalHeight
        }
    }
}

// MARK: - Alcove content router

private struct AlcoveContent: View {
    let state: NotchDisplayState
    let model: MenuBarModel
    let reduceMotion: Bool
    let onTriggerDebugAlert: (NotchThresholdAlert) -> Void

    var body: some View {
        AlcoveShell(
            state: self.state,
            model: self.model,
            reduceMotion: self.reduceMotion,
            onTriggerDebugAlert: self.onTriggerDebugAlert)
    }
}

// MARK: - Alcove shell (header + tools + content + dev gear)

/// The expanded alcove dashboard. Header sticky on top, hover-driven tool
/// strip below, content area routed by the active tool, and a small
/// wrench icon on the right that toggles a dev panel (choreography +
/// spring pickers, hidden from regular users).
private struct AlcoveShell: View {
    let state: NotchDisplayState
    let model: MenuBarModel
    let reduceMotion: Bool
    let onTriggerDebugAlert: (NotchThresholdAlert) -> Void

    @State private var activeTool: NotchTool = .now
    @State private var hoverTask: Task<Void, Never>?
    @State private var inDevMode: Bool = false
    @Namespace private var indicatorNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Tabs (or DEV label) cluster on the left with the wrench
            // sitting immediately to their right — keeps the controls
            // visually grouped instead of the wrench floating in
            // far-right empty space.
            HStack(alignment: .center, spacing: 6) {
                if self.inDevMode {
                    HStack(spacing: 5) {
                        Image(systemName: "wrench.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(NotchPalette.accent)
                        Text("DEV CONTROLS")
                            .font(.geist(size: 9, weight: .bold))
                            .foregroundStyle(NotchPalette.accent)
                            .tracking(1.4)
                    }
                } else {
                    ToolStrip(
                        activeTool: self.activeTool,
                        namespace: self.indicatorNamespace,
                        reduceMotion: self.reduceMotion,
                        onHover: self.handleToolHover)
                        .fixedSize()
                }
                DevGear(isActive: self.inDevMode) {
                    HapticGate.perform(.alignment)
                    let anim: Animation = self.reduceMotion
                        ? .linear(duration: 0.05)
                        : .spring(duration: 0.32, bounce: 0.10)
                    withAnimation(anim) {
                        self.inDevMode.toggle()
                    }
                }
                Spacer(minLength: 0)
            }

            ZStack(alignment: .topLeading) {
                if self.inDevMode {
                    DevPanel(
                        model: self.model,
                        onTriggerDebugAlert: self.onTriggerDebugAlert)
                        .transition(self.contentTransition)
                } else {
                    self.activeToolView()
                        .transition(self.contentTransition)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var contentTransition: AnyTransition {
        if self.reduceMotion {
            return .opacity.animation(.linear(duration: 0.05))
        }
        return .asymmetric(
            insertion: .modifier(
                active: BlurTransitionModifier(isActive: true),
                identity: BlurTransitionModifier(isActive: false)
            )
            .combined(with: .offset(y: -4))
            .animation(.spring(duration: 0.22, bounce: 0.03)),
            removal: .opacity.animation(.easeIn(duration: 0.06))
        )
    }

    @ViewBuilder
    private func activeToolView() -> some View {
        switch self.activeTool {
        case .now:
            NowTool(state: self.state, model: self.model)
                .id("tool-now")
        case .patterns:
            PatternsTool(model: self.model)
                .id("tool-patterns")
        case .wrap:
            WrapTool(model: self.model)
                .id("tool-wrap")
        case .health:
            HealthTool(model: self.model)
                .id("tool-health")
        }
    }

    /// Hover-driven tool switching. Intent debounce calibrated so a
    /// normal-speed cursor traversing the strip never trips a switch
    /// mid-motion. 150ms catches the deliberate dwell while letting
    /// drive-through traffic pass cleanly and maintaining responsiveness.
    private static let toolHoverIntent: Duration = .milliseconds(150)

    private func handleToolHover(_ tool: NotchTool, hovering: Bool) {
        // Any movement (enter or exit) resets the pending switch — that's
        // what gives the debounce its "must stop" feel.
        self.hoverTask?.cancel()
        guard hovering else { return }
        if tool == self.activeTool { return }
        self.hoverTask = Task { @MainActor in
            try? await Task.sleep(for: Self.toolHoverIntent)
            if Task.isCancelled { return }
            // Light tick when the dwell commits — feels like clicking
            // through Dock items even though it's hover-driven.
            HapticGate.perform(.alignment)
            let anim: Animation = self.reduceMotion
                ? .linear(duration: 0.05)
                : .spring(duration: 0.18, bounce: 0.04)
            withAnimation(anim) {
                self.activeTool = tool
            }
        }
    }
}

// MARK: - Tool strip (hover-switching)

private struct ToolStrip: View {
    let activeTool: NotchTool
    let namespace: Namespace.ID
    let reduceMotion: Bool
    let onHover: (NotchTool, Bool) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(NotchTool.allCases) { tool in
                ToolTab(
                    tool: tool,
                    isActive: tool == self.activeTool,
                    namespace: self.namespace,
                    reduceMotion: self.reduceMotion,
                    onHover: { hovering in self.onHover(tool, hovering) })
            }
        }
    }
}

private struct ToolTab: View {
    let tool: NotchTool
    let isActive: Bool
    let namespace: Namespace.ID
    let reduceMotion: Bool
    let onHover: (Bool) -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: self.tool.symbol)
                .font(.system(size: 8, weight: .semibold))
            Text(self.tool.label)
                .font(.geist(size: 9, weight: .bold))
                .tracking(1.0)
        }
        .foregroundStyle(self.isActive
            ? NotchPalette.primaryText
            : NotchPalette.tertiaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            if self.isActive {
                Capsule()
                    .fill(Color.white.opacity(0.07))
                    .overlay {
                        Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1)
                    }
                    .matchedGeometryEffect(id: "tool-pill", in: self.namespace)
            }
        }
        .contentShape(Capsule())
        .onHover(perform: self.onHover)
    }
}

// MARK: - Dev gear

private struct DevGear: View {
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.isActive ? "wrench.fill" : "wrench")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(self.isActive
                    ? NotchPalette.accent
                    : NotchPalette.tertiaryText)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PACE tool

/// NOW tab — the dense overview. Mirrors the menu bar's NOW tab in one
/// non-scrolling alcove surface. Three rings on top show the constraints
/// people care about (CONTEXT, 5H BURST, WEEKLY); the advisor's
/// WHY/WHEN sits below as actionable insight; runway anchors the bottom.
/// This is the tab a user lands on by default — everything they need in
/// the middle of a Claude Code session.
private struct NowTool: View {
    let state: NotchDisplayState
    let model: MenuBarModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Picker only useful when (a) viewing Claude (only Claude is
    /// pinnable in the watcher path) and (b) there are 2+ unique
    /// live sessions to choose from.
    private var canPickClaudeSession: Bool {
        self.model.selectedProvider == .claude
            && self.uniqueClaudeSessions.count >= 2
    }

    private var uniqueClaudeSessions: [LiveSession] {
        var seen: Set<String> = []
        var result: [LiveSession] = []
        for session in self.state.liveClaudeSessions where !seen.contains(session.sessionId) {
            seen.insert(session.sessionId)
            result.append(session)
        }
        return result
    }

    /// Mirrors the menu bar's `WindowsSection.showsAuthHint`: only
    /// for Claude (Codex doesn't use OAuth windows), and only when
    /// no OAuth-prefixed windows have come through. The id prefix
    /// `claude-oauth-` is what `ClaudeUsageWatcher.buildWindows`
    /// stamps on 5h/7d windows derived from the OAuth API.
    private var shouldShowOAuthHint: Bool {
        guard self.model.selectedProvider == .claude else { return false }
        let windows = self.model.selectedSnapshot?.windows ?? []
        return !windows.contains { $0.id.hasPrefix("claude-oauth-") }
    }

    /// Continuous-haptic loop fired while the cursor is on the hero
    /// card AND context is in the `tight` (>82%) zone. The alcove
    /// literally trembles under your finger when you're close to the
    /// wall — physical urgency that text alone can't convey. macOS
    /// has no continuous-haptic API, so we fake it by ticking the
    /// `.alignment` pattern every ~110ms (anything tighter and the
    /// trackpad starts dropping events).
    @State private var earthquakeTask: Task<Void, Never>?
    /// Tracks the last committed hover decision so duplicate
    /// `onHover` events (SwiftUI sometimes fires true→false→true
    /// during re-renders) don't churn-restart the earthquake task
    /// and accidentally cancel themselves into a single tick.
    @State private var heroHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Group {
                if let title = self.state.depletedTitle {
                    // PREMIUM DEPLETED HERO
                    // Left-aligned massive countdown with a sleek gradient border
                    // mimicking a high-end "locked" hardware panel.
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(self.state.depletedCountdown ?? "—")
                                .font(.geistMono(size: 34, weight: .bold))
                                .foregroundStyle(NotchPalette.danger)
                                .contentTransition(.numericText())
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                        .frame(minWidth: 64, alignment: .trailing)

                        Rectangle()
                            .fill(NotchPalette.danger.opacity(0.2))
                            .frame(width: 1, height: 38)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9))
                                Text("RATE-LIMITED")
                                    .font(.geist(size: 10, weight: .bold))
                                    .tracking(1.2)
                            }
                            .foregroundStyle(NotchPalette.danger)

                            Text(title)
                                .font(.geist(size: 15, weight: .semibold))
                                .foregroundStyle(NotchPalette.primaryText)
                                .lineLimit(1)

                            if let clockText = self.state.depletedClock {
                                Text(clockText)
                                    .font(.geist(size: 11))
                                    .foregroundStyle(NotchPalette.secondaryText)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            NotchPalette.danger.opacity(0.12),
                                            NotchPalette.danger.opacity(0.02)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            NotchPalette.danger.opacity(0.35),
                                            NotchPalette.danger.opacity(0.05)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1
                                )
                        }
                    }
                } else {
                    // HERO — always shows STATE (% + verdict + recommendation)
                    // + TRAJECTORY (forecast + turns left). The hero's BACKGROUND
                    // is the heat gradient (mint → amber → coral), clip-filled
                    // to context % width — the runway IS the backdrop. Fire
                    // moments append a banner under it, never replace.
                    VerdictHero(state: self.state, model: self.model)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background {
                            HeroGradientBackdrop(
                                percent: self.state.hasContext ? self.state.contextPercent : 0)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
                .onHover(perform: self.handleHeroHover)

            if self.state.fireActive {
                FireBanner(
                    turnTokens: self.state.fireTurnTokens,
                    contextPercent: self.state.fireContextPercent)
            }

            // PERSONALIZED FORECAST — verdict + bucket chips +
            // transparency line. Lifted from the menu bar's
            // PersonalizedForecast: turns abstract "% remaining" into
            // "N small / M medium / L large asks left" anchored to
            // the user's actual turn-size pattern. Only renders when
            // there's enough data; the block self-gates internally.
            if self.state.depletedTitle == nil {
                PersonalizedForecastBlock(model: self.model)
            }

            // SUPPORTING — windows as compact meter rows. Renders the
            // canonical 5H + Weekly plus any Opus/Sonnet weekly splits
            // that exist on the user's plan, so the alcove matches the
            // menu bar's full window list.
            VStack(spacing: 5) {
                WindowMeterRow(
                    label: "5h burst",
                    percent: self.state.fiveHour?.percent ?? 0,
                    tone: self.state.fiveHour?.tone ?? .calm,
                    resetText: self.state.fiveHour?.resetText ?? "—",
                    isActive: self.state.fiveHour != nil,
                    forecast: self.state.fiveHourForecast,
                    resetsAt: self.state.fiveHour?.resetsAt)
                WindowMeterRow(
                    label: "weekly",
                    percent: self.state.weekly?.percent ?? 0,
                    tone: self.state.weekly?.tone ?? .calm,
                    resetText: self.state.weekly?.resetText ?? "—",
                    isActive: self.state.weekly != nil,
                    forecast: self.state.weeklyForecast,
                    resetsAt: self.state.weekly?.resetsAt)
                if let opus = self.state.weeklyOpus {
                    WindowMeterRow(
                        label: "weekly opus",
                        percent: opus.percent,
                        tone: opus.tone,
                        resetText: opus.resetText,
                        isActive: true,
                        resetsAt: opus.resetsAt)
                }
                if let sonnet = self.state.weeklySonnet {
                    WindowMeterRow(
                        label: "weekly sonnet",
                        percent: sonnet.percent,
                        tone: sonnet.tone,
                        resetText: sonnet.resetText,
                        isActive: true,
                        resetsAt: sonnet.resetsAt)
                }

                // OAuth missing — Claude is selected but no OAuth
                // windows came through. Without OAuth we can't read
                // 5h or 7d caps, so the meters above all show "—".
                // Surface the recovery path inline.
                if self.shouldShowOAuthHint {
                    NotchOAuthMissingHint()
                }
            }

            // WHY row — the advisor's primary driver. The menu bar's
            // signature insight ("input tokens dominating · 80% of
            // context this turn"), surfaced as a single inline line
            // beneath the window meters.
            if self.state.hasAdvisor, !self.state.advisorPrimaryDriver.isEmpty {
                HStack(spacing: 8) {
                    Text("WHY")
                        .font(.geist(size: 8, weight: .bold))
                        .foregroundStyle(NotchPalette.tertiaryText)
                        .tracking(1.4)
                        .frame(width: 32, alignment: .leading)
                    Text(self.state.advisorPrimaryDriver)
                        .font(.geist(size: 11, weight: .semibold))
                        .foregroundStyle(NotchPalette.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !self.state.advisorDriverDetail.isEmpty {
                        Text("·")
                            .font(.geist(size: 10))
                            .foregroundStyle(NotchPalette.tertiaryText)
                        Text(self.state.advisorDriverDetail)
                            .font(.geist(size: 10))
                            .foregroundStyle(NotchPalette.tertiaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }
            }

            // ─────────────────────────────────────────────────
            // Footer monitoring strip — cost today · peak hour · days
            // left in cycle. Sits at the very bottom of NOW, fills the
            // space the alcove had reserved for it.
            NowFooterStrip(state: self.state)
        }
        .onChange(of: self.state.fireActive) { _, newValue in
            // Firmer haptic when "playing with fire" trips — the
            // payoff for actually triggering the celebratory event.
            // Only fires on the false→true transition, not on close.
            if newValue {
                HapticGate.perform(.levelChange)
            }
        }
        .onDisappear {
            // Always stop the earthquake when NOW unmounts (alcove
            // close, tab switch) so we don't leak ticks.
            self.earthquakeTask?.cancel()
            self.earthquakeTask = nil
        }
    }

    /// Start/stop the tight-zone earthquake based on hover state.
    /// Only acts on rising and falling edges (true↔false) so
    /// SwiftUI's flaky duplicate hover events don't churn-cancel
    /// the task. The loop alternates haptic patterns and uses a
    /// 140ms cadence — anything faster gets rate-limited by macOS
    /// after the first 1–2 ticks, and identical-pattern spam is the
    /// first thing the system throttles.
    private func handleHeroHover(_ hovering: Bool) {
        // Edge-trigger only: ignore duplicate same-direction events.
        guard hovering != self.heroHovered else { return }
        self.heroHovered = hovering

        if !hovering {
            self.earthquakeTask?.cancel()
            self.earthquakeTask = nil
            return
        }

        guard !self.reduceMotion else { return }

        let stateRef = self.state
        self.earthquakeTask = Task { @MainActor in
            // Heartbeat rhythm — `.levelChange` is the LUB (firm
            // pulse), `.generic` is the DUB (softer answering beat),
            // then a breathing pause before the next heartbeat. Way
            // more visceral than even bubs because a heartbeat *means*
            // something — anxious urgency, the alcove pulsing under
            // your finger like it's panicking with you.
            //
            // Cadence speeds up as context climbs into critical:
            //   82–89% → ~1 beat per second (calm warning)
            //   90–94% → ~1.5 beats per second (anxious)
            //   95%+   → ~2 beats per second (panic)
            while !Task.isCancelled {
                let pct = stateRef.contextPercent
                guard pct >= 82 else {
                    try? await Task.sleep(for: .milliseconds(400))
                    continue
                }

                let restingPauseMs: Int
                if pct >= 95 { restingPauseMs = 360 }
                else if pct >= 90 { restingPauseMs = 540 }
                else { restingPauseMs = 800 }

                // LUB — the firm "first" beat.
                HapticGate.perform(.levelChange, .now)
                try? await Task.sleep(for: .milliseconds(95))

                // DUB — softer answering beat right behind it.
                HapticGate.perform(.generic, .now)

                // Resting pause before the next heartbeat.
                try? await Task.sleep(for: .milliseconds(restingPauseMs))
            }
        }
    }
}

/// Quiet footer monitoring strip at the bottom of NOW. Each item only
/// renders when its data is meaningful — don't show "$0.00 today" or
/// "—" placeholders. Strip collapses to nothing when no items qualify,
/// rather than reserving empty space for missing data.
private struct NowFooterStrip: View {
    let state: NotchDisplayState

    /// First slot: live $ today if available; otherwise live tokens
    /// today; otherwise nil (slot hidden). Lets flat-plan users see
    /// today's burn even when there's no overage spend to track.
    private var costOrTokensStat: (label: String, value: String, accent: Color)? {
        if let spend = self.state.spendToday, spend > 0 {
            return ("COST", String(format: "$%.2f", spend), NotchPalette.toneCalm)
        }
        if self.state.totalTokensToday > 0 {
            return ("TOKENS", compactTokens(self.state.totalTokensToday), NotchPalette.accent)
        }
        return nil
    }

    private var peakStat: (label: String, value: String, accent: Color)? {
        guard let peak = self.state.peakHourLabel, !peak.isEmpty else { return nil }
        return ("PEAK", peak, NotchPalette.toneWatch)
    }

    private var turnsStat: (label: String, value: String, accent: Color)? {
        guard self.state.turnsToday > 0 else { return nil }
        return ("TURNS", "\(self.state.turnsToday)", NotchPalette.secondaryText)
    }

    private var stats: [(label: String, value: String, accent: Color)] {
        [self.costOrTokensStat, self.peakStat, self.turnsStat].compactMap { $0 }
    }

    var body: some View {
        let items = self.stats
        if !items.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    if idx > 0 {
                        NowFooterDivider()
                    }
                    NowFooterStat(label: item.label, value: item.value, accent: item.accent)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct NowFooterStat: View {
    let label: String
    let value: String
    let accent: Color

    var body: some View {
        HStack(spacing: 5) {
            Text(self.label)
                .font(.geist(size: 8, weight: .bold))
                .foregroundStyle(NotchPalette.tertiaryText)
                .tracking(1.2)
            Text(self.value)
                .font(.geistMono(size: 10, weight: .semibold))
                .foregroundStyle(self.accent)
                .contentTransition(.numericText())
        }
    }
}

private struct NowFooterDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 10)
            .padding(.horizontal, 12)
    }
}

/// Concurrent-sessions badge for the alcove header — pulsing live dot,
/// count, "LIVE" label, then a deduped project list filling the
/// remaining space. Replaces the burn-rate signature; that lives in
/// the BURN tab now.
private struct LiveSessionsBadge: View {
    let count: Int
    let projects: [String]

    var body: some View {
        HStack(spacing: 5) {
            // Pulsing dot lives in its own subview so its repeating
            // state change doesn't invalidate this parent's body and
            // re-fire the count's numericText contentTransition.
            PulsingLiveDot()

            Text("\(self.count)")
                .font(.geistMono(size: 11, weight: .semibold))
                .foregroundStyle(NotchPalette.primaryText)
                .contentTransition(.numericText())
            Text("LIVE")
                .font(.geist(size: 9, weight: .bold))
                .foregroundStyle(NotchPalette.secondaryText)
                .tracking(1.0)

            if !self.dedupedProjects.isEmpty {
                Text("·")
                    .font(.geist(size: 10))
                    .foregroundStyle(NotchPalette.tertiaryText)
                Text(self.shownProjects)
                    .font(.geist(size: 10))
                    .foregroundStyle(NotchPalette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if self.overflowCount > 0 {
                    Text("+\(self.overflowCount)")
                        .font(.geistMono(size: 10, weight: .semibold))
                        .foregroundStyle(NotchPalette.tertiaryText)
                }
            }
        }
    }

    private var dedupedProjects: [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for name in self.projects where !seen.contains(name) {
            seen.insert(name)
            ordered.append(name)
        }
        return ordered
    }

    /// Show 2 names by default — enough to feel rich without crowding
    /// the limited header width. Overflow goes to the +N suffix.
    private var shownProjects: String {
        self.dedupedProjects.prefix(2).joined(separator: ", ")
    }

    private var overflowCount: Int {
        max(0, self.dedupedProjects.count - 2)
    }
}

/// Self-contained pulsing live dot. Owns its own `pulse` state so the
/// repeating animation invalidates only THIS view's body — not the
/// parent's — which would otherwise re-fire numericText transitions
/// on adjacent counts each pulse tick.
private struct PulsingLiveDot: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(NotchPalette.live)
                .frame(width: 6, height: 6)
            Circle()
                .stroke(NotchPalette.live.opacity(0.55), lineWidth: 1.2)
                .frame(width: 14, height: 14)
                .scaleEffect(self.pulse ? 1.4 : 0.6)
                .opacity(self.pulse ? 0 : 0.7)
        }
        .frame(width: 14, height: 14)
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                self.pulse = true
            }
        }
    }
}

private struct NowStatTile: View {
    let label: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(self.label)
                .font(.geist(size: 7, weight: .bold))
                .foregroundStyle(NotchPalette.tertiaryText)
                .tracking(1.2)
            Text(self.value)
                .font(.geistMono(size: 13, weight: .semibold))
                .foregroundStyle(self.accent)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                }
        }
    }
}

/// Strava-style hero block — STATE on top (big % + verdict +
/// recommendation), TRAJECTORY as the third line ("hits cap 14:32 ·
/// 12 turns left"). One cohesive block; the eye reads top-to-bottom
/// and lands on the actionable forecast right where it should.
private struct VerdictHero: View {
    let state: NotchDisplayState
    let model: MenuBarModel

    /// Session picker is only useful when (a) we're viewing Claude
    /// (only Claude is pinnable in the watcher path) and (b) there
    /// are 2+ unique live sessions to choose from.
    private var canPickClaudeSession: Bool {
        self.model.selectedProvider == .claude
            && self.uniqueClaudeSessions.count >= 2
    }

    private var uniqueClaudeSessions: [LiveSession] {
        var seen: Set<String> = []
        var result: [LiveSession] = []
        for session in self.state.liveClaudeSessions where !seen.contains(session.sessionId) {
            seen.insert(session.sessionId)
            result.append(session)
        }
        return result
    }

    private var titleText: String {
        if self.state.hasAdvisor { return self.state.advisorHealthTitle }
        if !self.state.hasContext {
            return self.state.depletedTitle != nil ? "Rate limited" : "Cold start"
        }
        return self.state.verdictTitle
    }

    private var subtitleText: String {
        if self.state.hasAdvisor { return self.state.advisorRecommendation }
        if !self.state.hasContext {
            return self.state.depletedTitle != nil ? "waiting for window to reset" : "open Claude Code or Codex to begin"
        }
        return self.state.verdictDetail
    }

    private var hasTrajectory: Bool {
        self.state.hasAdvisor &&
            (!self.state.advisorForecast.isEmpty || self.state.advisorProjectedTurns != nil)
    }

    /// % of the context window the last turn actually added.
    /// Pulled from the model's rolling turn-delta history (which
    /// `detectFireEvents` builds by diffing `contextUsedTokens`
    /// poll-over-poll) rather than the watcher's broken
    /// `lastTurnSharePercent` — that field reports cumulative
    /// state, not the per-turn delta.
    private var lastTurnDeltaPercent: Double? {
        guard let snap = self.model.selectedSnapshot,
              let ctx = snap.workContext,
              ctx.contextWindowTokens > 0
        else { return nil }
        let pattern = self.model.turnPattern(
            forSessionId: ctx.sessionId, provider: snap.kind)
        guard let lastDelta = pattern.samples.last
        else { return nil }
        return Double(lastDelta) / Double(ctx.contextWindowTokens) * 100
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(self.state.hasContext
                    ? "\(Int(self.state.contextPercent.rounded()))"
                    : "—")
                    .font(.geistMono(size: 40, weight: .semibold))
                    .foregroundStyle(NotchPalette.tone(self.state.contextTone))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("%")
                    .font(.geistMono(size: 16, weight: .medium))
                    .foregroundStyle(NotchPalette.tone(self.state.contextTone).opacity(0.6))
            }
            .fixedSize()

            VStack(alignment: .leading, spacing: 3) {
                Text(self.titleText)
                    .font(.geist(size: 17, weight: .bold))
                    .foregroundStyle(NotchPalette.primaryText)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                Text(self.subtitleText)
                    .font(.geist(size: 11))
                    .foregroundStyle(NotchPalette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Project · model — mirrors the menu bar's
                // FlatSessionContext directory + model line. Useful
                // when running multiple sessions or to confirm which
                // model the advisor's pricing assumes.
                if self.state.hasContext,
                   self.state.projectLabel != "—",
                   !self.state.projectLabel.isEmpty
                {
                    HStack(spacing: 5) {
                        Text(self.state.projectLabel)
                            .font(.geist(size: 10, weight: .semibold))
                            .foregroundStyle(NotchPalette.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let model = self.state.modelLabel, !model.isEmpty {
                            Text("·")
                                .font(.geist(size: 10))
                                .foregroundStyle(NotchPalette.tertiaryText)
                            Text(model)
                                .font(.geist(size: 10))
                                .foregroundStyle(NotchPalette.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }

                // Context facts — `~N msgs · used / total`. Lifted from
                // the menu bar's hero, where this answers the live
                // "how much room do I actually have?" question. The
                // % alone is abstract; the absolute numbers calibrate
                // the gut over time, and `~msgs` is the closest thing
                // to a runway estimate for the active conversation.
                if self.state.hasContext,
                   let ctx = self.model.selectedSnapshot?.workContext
                {
                    HStack(spacing: 5) {
                        if let msgs = ctx.estimatedMessagesRemaining {
                            Text("~\(msgs) msgs")
                                .font(.geistMono(size: 10, weight: .semibold))
                                .foregroundStyle(NotchPalette.secondaryText)
                                .contentTransition(.numericText())
                            Text("·")
                                .font(.geist(size: 10))
                                .foregroundStyle(NotchPalette.tertiaryText)
                        }
                        Text("\(compactTokens(ctx.contextUsedTokens)) / \(compactTokens(ctx.contextWindowTokens))")
                            .font(.geistMono(size: 10))
                            .foregroundStyle(NotchPalette.tertiaryText)
                        // Last-turn share — computed as the DELTA of
                        // contextUsedTokens between the previous and
                        // current poll, divided by the window size.
                        // The advisor's `lastTurnSharePercent` field
                        // is broken (it computes cumulative state,
                        // not delta), so we read from the model's
                        // turn-pattern history instead — that's what
                        // `detectFireEvents` records each time a new
                        // user message arrives.
                        if let lastDelta = self.lastTurnDeltaPercent,
                           lastDelta > 0
                        {
                            Text("·")
                                .font(.geist(size: 10))
                                .foregroundStyle(NotchPalette.tertiaryText)
                            Text("last turn \(Int(lastDelta.rounded()))%")
                                .font(.geistMono(size: 10))
                                .foregroundStyle(NotchPalette.tertiaryText)
                                .contentTransition(.numericText())
                        }
                    }
                }

                if self.hasTrajectory {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(NotchPalette.tone(self.state.advisorTone))

                        if let turns = self.state.advisorProjectedTurns {
                            Text("\(turns)")
                                .font(.geistMono(size: 11, weight: .semibold))
                                .foregroundStyle(NotchPalette.primaryText)
                                .contentTransition(.numericText())
                            Text("turn\(turns == 1 ? "" : "s") until cap")
                                .font(.geist(size: 11))
                                .foregroundStyle(NotchPalette.secondaryText)
                        }

                        if !self.state.advisorForecast.isEmpty {
                            if self.state.advisorProjectedTurns != nil {
                                Text("·")
                                    .font(.geist(size: 11))
                                    .foregroundStyle(NotchPalette.tertiaryText)
                            }
                            Text(self.state.advisorForecast)
                                .font(.geist(size: 11))
                                .foregroundStyle(NotchPalette.tertiaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .padding(.top, 1)
                }

                // resetPlan — advisor's "what to do until reset" tip.
                // Tertiary, sits as the quietest line of the hero.
                if self.state.hasAdvisor, !self.state.advisorResetPlan.isEmpty {
                    Text(self.state.advisorResetPlan)
                        .font(.geist(size: 10))
                        .foregroundStyle(NotchPalette.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Conversation pills — one per detected live Claude
            // session, max 5. Hover any pill to preview that session's
            // context (the alcove fetches and displays its data
            // without committing). Click toggles pin: same pill
            // clicked twice = unpin. Branch chip removed; this column
            // is now dedicated to switching between live sessions.
            if self.canPickClaudeSession {
                VStack(alignment: .trailing, spacing: 3) {
                    ForEach(self.uniqueClaudeSessions.prefix(5)) { session in
                        SessionPill(
                            session: session,
                            isPinned: self.model.pinnedClaudeSessionId == session.sessionId,
                            isPreview: self.model.previewClaudeSessionId == session.sessionId,
                            onHover: { hovering in
                                if hovering {
                                    self.model.setPreviewClaudeSessionId(session.sessionId)
                                } else if self.model.previewClaudeSessionId == session.sessionId {
                                    self.model.setPreviewClaudeSessionId(nil)
                                }
                            },
                            onClick: {
                                let isCurrentlyPinned = self.model.pinnedClaudeSessionId == session.sessionId
                                HapticGate.perform(
                                    isCurrentlyPinned ? .alignment : .levelChange)
                                self.model.setPinnedClaudeSessionId(
                                    isCurrentlyPinned ? nil : session.sessionId)
                            })
                    }
                }
                .fixedSize()
            }
        }
    }
}

/// One conversation pill in the hero's right column. Hover sets a
/// preview (alcove temporarily fetches that session's context); click
/// toggles a persistent pin. Three visual states layered:
///   - default: subtle 4% white capsule
///   - hovered/preview: brighter, accent border
///   - pinned: amber filled border, pin glyph appended
private struct SessionPill: View {
    let session: LiveSession
    let isPinned: Bool
    let isPreview: Bool
    let onHover: (Bool) -> Void
    let onClick: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    /// 0...1 fill of the confirm ring while the user holds a hover on
    /// an unpinned pill. Linear progress so the user can read time
    /// remaining accurately; the dopamine work happens at commit.
    @State private var holdProgress: Double = 0
    @State private var holdTask: Task<Void, Never>?
    /// Unified scale — drives hover lift, anticipation compress, and
    /// commit pop through a single state so spring physics blend
    /// cleanly across phases instead of fighting each other.
    @State private var scale: Double = 1.0
    /// Stroke weight of the confirm ring. Builds 1.5 → 2.6 across the
    /// hold to telegraph rising tension — small but felt.
    @State private var ringWeight: Double = 1.5
    /// 0...1 — drives a soft outward halo that blooms at commit and
    /// settles. Locked to the same spring window as the pop so it
    /// reads as one moment, not two.
    @State private var flashGlow: Double = 0

    /// Total dwell time. 520ms is the responsiveness sweet spot —
    /// short enough to feel snappy, long enough that the anticipation
    /// phase has room to telegraph the pop.
    private static let holdDuration: Double = 0.52
    /// Last 80ms of the hold = anticipation. Pill compresses inward
    /// from 1.04 → 0.99 so the commit pop has somewhere to spring
    /// from. This is what gives "premium" its weight.
    private static let anticipateLeadIn: Double = 0.08

    // Springs over timing curves — Apple's UI breathes on physics,
    // not bezier math. Response = "how fast it moves", damping =
    // "how much overshoot" (1.0 = critical, <1 = bounces).
    //
    // hoverSpring: snappy lift, no overshoot — feels alive but stable
    private static let hoverSpring: Animation =
        .spring(response: 0.30, dampingFraction: 0.78)
    // fillEase: linear so progress reads honestly. Pure tween, no
    // physics — the ring is a clock, not a gesture.
    private static let fillEase: Animation =
        .linear(duration: holdDuration)
    // drainSpring: decisive cancel, slightly overdamped to settle fast
    private static let drainSpring: Animation =
        .spring(response: 0.26, dampingFraction: 0.85)
    // anticipateSpring: very fast inward compress — the wind-up
    private static let anticipateSpring: Animation =
        .spring(response: 0.14, dampingFraction: 0.85)
    // commitSpring: the dopamine — ~12% overshoot. Lower damping
    // than the others so it has bounce without feeling rubbery.
    private static let commitSpring: Animation =
        .spring(response: 0.38, dampingFraction: 0.55)
    // settleSpring: slow glide back to rest. Stretches the moment so
    // the eye has time to enjoy the pop before it ends.
    private static let settleSpring: Animation =
        .spring(response: 0.52, dampingFraction: 0.80)
    // Glow lifecycle has its own rhythm, decoupled from the scale
    // spring. Ease-in (slow → fast) during the hold builds anticipation
    // silently; the climax is a quick snap to peak; settle is a long
    // ease-out fade so the light lingers and dies smoothly.
    //
    // glowBuild: gentle ease-in-out swell. Material's standard
    // easing (0.42, 0, 0.58, 1) — visible rise throughout the hold,
    // never plateauing near zero or rushing at the end. The glow
    // grows continuously so the eye sees momentum, not a snap.
    private static let glowBuild: Animation =
        .timingCurve(0.42, 0, 0.58, 1, duration: holdDuration)
    // glowPeak: smooth final push from the built-up value (0.65) to
    // full brightness (1.0). Same easing family as the build so the
    // transition is seamless — not a jarring curve change at commit.
    private static let glowPeak: Animation =
        .timingCurve(0.42, 0, 0.58, 1, duration: 0.24)
    // Two-stage fade — like Netflix's "ta-DUM" boom + resonance.
    // A single cubic-bezier can only go monotonically from start to
    // end, so it can't give us "fast drop to a mid value, then long
    // taper to zero". Splitting into two phases lets each stage have
    // its own curve and duration.
    //
    // glowFadeFast: the boom ending. Ease-out-expo, fast — drops
    // from peak (1.0) to a mid-level (0.30) so the eye reads
    // "moment over". This is the visual equivalent of Netflix's
    // synth attack ending.
    private static let glowFadeFast: Animation =
        .timingCurve(0.16, 1, 0.3, 1, duration: 0.22)
    // glowFadeTail: the resonance. Extreme tapered ease-out over
    // 1.7s. Curve shape (0.20, 0.75, 0.45, 1) — moderate initial
    // rate that asymptotes flat near the end. The afterglow lingers
    // and drifts to zero almost imperceptibly, mirroring how the
    // "dum" reverb hangs in the air after the boom.
    private static let glowFadeTail: Animation =
        .timingCurve(0.20, 0.75, 0.45, 1, duration: 1.7)

    private var isHighlighted: Bool {
        self.isPinned || self.isPreview || self.hovered
    }

    /// What the pill actually renders. Prefers the conversation's
    /// first-user-message (matches Claude Code's `/resume` picker)
    /// and falls back to the project folder name when no user
    /// message has landed yet.
    private var pillLabel: String {
        if let name = self.session.displayName, !name.isEmpty { return name }
        return self.session.projectName
    }

    var body: some View {
        Button(action: self.commitClick) {
            self.pillContent
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(self.pillBackground)
        }
        .buttonStyle(.plain)
        .scaleEffect(self.scale)
        .help(self.session.displayName.map { "\($0) · \(self.session.projectName)" }
            ?? self.session.projectName)
        .onHover(perform: self.handleHover)
    }

    @ViewBuilder
    private var pillContent: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(self.isPinned
                    ? NotchPalette.accent
                    : NotchPalette.live)
                .frame(width: 5, height: 5)

            Text(self.pillLabel)
                .font(.geistMono(size: 9, weight: self.isPinned ? .semibold : .medium))
                .foregroundStyle(self.isHighlighted
                    ? NotchPalette.primaryText
                    : NotchPalette.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var fillColor: Color {
        if self.isPinned { return NotchPalette.accent.opacity(0.14) }
        return self.isHighlighted
            ? Color.white.opacity(0.10)
            : Color.white.opacity(0.04)
    }

    private var strokeColor: Color {
        if self.isPinned { return NotchPalette.accent.opacity(0.55) }
        if self.isPreview { return NotchPalette.accent.opacity(0.30) }
        return Color.white.opacity(0.10)
    }

    @ViewBuilder
    private var pillBackground: some View {
        Capsule()
            .fill(self.fillColor)
            // Inner wash — at commit, accent color subtly tints the
            // fill so the pill itself warms rather than gets outlined.
            // Kept very low so the glow reads as a hint, not a flash.
            .overlay {
                Capsule()
                    .fill(NotchPalette.accent.opacity(self.flashGlow * 0.12))
            }
            .overlay {
                Capsule().stroke(self.strokeColor, lineWidth: 1)
            }
            // Hover-confirm ring — traces the capsule's perimeter as
            // the user dwells. Fully drawn = pin commit fires. Trim
            // sweeps clockwise from top-right which reads naturally
            // as "filling". Stroke weight grows alongside the trim so
            // tension builds visibly into the commit.
            .overlay {
                Capsule()
                    .trim(from: 0, to: self.holdProgress)
                    .stroke(
                        NotchPalette.accent,
                        style: StrokeStyle(
                            lineWidth: self.ringWeight,
                            lineCap: .round))
                    .opacity(self.holdProgress > 0.01 ? 1 : 0)
            }
            // Outer bloom — a filled capsule blurred and scaled out
            // behind the pill. Reads as light emanating from the pill
            // rather than a halo around it. Two layers at different
            // blur/scale give natural falloff — close core + soft
            // outer aura.
            .background {
                ZStack {
                    Capsule()
                        .fill(NotchPalette.accent.opacity(self.flashGlow * 0.18))
                        .blur(radius: 3)
                        .scaleEffect(1 + self.flashGlow * 0.04)
                    Capsule()
                        .fill(NotchPalette.accent.opacity(self.flashGlow * 0.09))
                        .blur(radius: 7)
                        .scaleEffect(1 + self.flashGlow * 0.08)
                }
            }
    }

    private func handleHover(_ hovering: Bool) {
        // Hover lift — the rest pose for an active pill. Spring so it
        // feels physical, low overshoot so it doesn't bounce.
        withAnimation(Self.hoverSpring) {
            self.hovered = hovering
            // Don't fight the commit pop — only set hover scale when
            // we're not in the middle of a flash (scale > 1.05 means
            // commit is driving). Settle handler resets to hover rest.
            if self.scale < 1.05 {
                self.scale = hovering ? 1.04 : 1.0
            }
        }
        self.onHover(hovering)
        self.handleHoldHover(hovering: hovering)
    }

    /// Click path — bypasses the dwell timer entirely so power users
    /// can commit instantly. Still fires the confirm pop so the
    /// visual feedback is consistent with the hover-confirm path.
    private func commitClick() {
        self.cancelHold(animated: false)
        self.fireConfirmPop()
        self.onClick()
    }

    /// Drives the hover-to-confirm choreography. Hover-in on an
    /// unpinned pill starts the linear ring fill + a sleep task that
    /// runs anticipation → commit at the right moments. Hover-out (or
    /// commit) cancels the task and drains the ring back to 0.
    /// Reduce-motion users skip the timer entirely.
    private func handleHoldHover(hovering: Bool) {
        // Pinned pills: no auto-confirm timer. Click is still required
        // to unpin so a stray hover can't undo intent.
        if self.isPinned {
            self.cancelHold(animated: true)
            return
        }
        // Reduce-motion: skip the progressive build entirely.
        if self.reduceMotion {
            self.cancelHold(animated: false)
            return
        }
        if hovering {
            // Linear progress (honest clock) + spring-driven tension
            // build on the stroke weight. Two animations on the same
            // duration window so they read as one gesture.
            withAnimation(Self.fillEase) {
                self.holdProgress = 1
                self.ringWeight = 2.6
            }
            // Glow swells continuously across the hold — visible
            // throughout, building momentum into commit. By the time
            // commit fires, the glow is already at 0.65 brightness
            // and just needs a final smooth push to peak. This is
            // what gives "none to full" continuity instead of a snap.
            withAnimation(Self.glowBuild) {
                self.flashGlow = 0.65
            }
            self.holdTask?.cancel()
            self.holdTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(
                    Int(Self.holdDuration * 1000)))
                if Task.isCancelled { return }
                HapticGate.perform(.levelChange)
                self.onClick()
                self.fireConfirmPop()
            }
        } else {
            self.cancelHold(animated: true)
        }
    }

    /// Commit moment — pure light, no scale. Glow snaps to peak,
    /// holds briefly, then fades through the two-stage Netflix-style
    /// decay (fast drop + long resonance tail). No physical pop, no
    /// settle spring; the visual is entirely carried by the light.
    private func fireConfirmPop() {
        withAnimation(Self.glowPeak) {
            self.flashGlow = 1.0
            self.holdProgress = 0
            self.ringWeight = 1.5
        }
        Task { @MainActor in
            // Hold peak so the brain registers "yes, that happened"
            // while the light is still bright.
            try? await Task.sleep(for: .milliseconds(220))
            // Stage 1 — fast initial drop signals the climax is over.
            withAnimation(Self.glowFadeFast) {
                self.flashGlow = 0.30
            }
            try? await Task.sleep(for: .milliseconds(220))
            // Stage 2 — extreme tapered tail drifts to zero over
            // 1.7s. The resonance that won't quit.
            withAnimation(Self.glowFadeTail) {
                self.flashGlow = 0
            }
        }
    }

    /// `animated` controls whether the drain tweens or snaps —
    /// click-commit calls in with animated=false because the pop
    /// already owns the visual moment and a competing drain would
    /// muddy it.
    private func cancelHold(animated: Bool) {
        self.holdTask?.cancel()
        self.holdTask = nil
        if animated {
            withAnimation(Self.drainSpring) {
                self.holdProgress = 0
                self.ringWeight = 1.5
            }
            // Glow drains on its own gentle ease-out so any pre-built
            // glow from a partial hold doesn't cut off abruptly.
            withAnimation(.easeOut(duration: 0.22)) {
                self.flashGlow = 0
            }
        } else {
            self.holdProgress = 0
            self.ringWeight = 1.5
            self.flashGlow = 0
        }
    }
}

/// "Can't detect auth" card — shows when Claude is the active provider
/// but the OAuth credential isn't surfacing windows. The 5h burst and
/// 7d caps depend on it; without OAuth we can't render those at all.
/// Direct port of the menu bar's `OAuthMissingHint`, recolored to the
/// notch palette's amber accent so it feels native to the alcove.
private struct NotchOAuthMissingHint: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchPalette.accent.opacity(0.85))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text("Can't detect auth")
                    .font(.geist(size: 11, weight: .semibold))
                    .foregroundStyle(NotchPalette.primaryText)
                Text("5h burst & 7d windows need Claude Code OAuth — open Keychain Access, find \u{201C}Claude Code-credentials\u{201D}, and allow burnrate.")
                    .font(.geist(size: 10))
                    .foregroundStyle(NotchPalette.tertiaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(NotchPalette.accent.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(NotchPalette.accent.opacity(0.25), lineWidth: 1)
                }
        }
    }
}

/// Personalized forecast block — the menu bar's gold ported into the
/// alcove. Surfaces three things you can't get from the hero alone:
///   - 5-tier verdict copy anchored to YOUR pattern, not a generic
///     "watch / tight" health label
///   - Bucket chips: how many small / medium / large turns fit in the
///     remaining context, with sizes derived from the user's history
///   - Transparency line: sample count, avg turn size, trend arrow.
///     Lets the user trust the forecast — and when sample count is
///     low, the "learning your pace" tag flags it as fragile.
///
/// Only renders when there's both a workContext and a pattern with at
/// least one sample. Otherwise the hero already says everything.
private struct PersonalizedForecastBlock: View {
    let model: MenuBarModel

    private var workContext: WorkContextSnapshot? {
        self.model.selectedSnapshot?.workContext
    }

    private var pattern: MenuBarModel.TurnPattern? {
        guard let snap = self.model.selectedSnapshot else { return nil }
        let p = self.model.turnPattern(
            forSessionId: snap.workContext?.sessionId,
            provider: snap.kind)
        return p.hasEnoughData ? p : nil
    }

    private var avgTurnsLeft: Int {
        guard let ctx = self.workContext, let p = self.pattern, p.avg > 0 else { return 0 }
        return max(0, ctx.contextRemainingTokens / p.avg)
    }

    private var p90TurnsLeft: Int {
        guard let ctx = self.workContext, let p = self.pattern, p.p90 > 0 else { return 0 }
        return max(0, ctx.contextRemainingTokens / p.p90)
    }

    /// 5-tier verdict — same logic as the menu bar's
    /// `PersonalizedForecast.verdict`. Tones mapped from popover
    /// danger/warning/lavender to the notch palette's electric
    /// tight/watch/calm so the block matches the alcove's punchier
    /// surface.
    private var verdict: (icon: String, tone: UsageTone, copy: String)? {
        guard let ctx = self.workContext, let p = self.pattern else { return nil }
        let pct = Int(ctx.contextUsedPercent.rounded())
        if p.trend == .up, self.avgTurnsLeft <= 2 {
            return ("flame.fill", .tight,
                    "Recent turns ran larger than usual. \(pct)% used.")
        }
        if self.p90TurnsLeft == 0 {
            return ("exclamationmark.triangle.fill", .tight,
                    "No room for a typical big ask. Compact soon.")
        }
        if self.avgTurnsLeft == 0 {
            return ("exclamationmark.triangle.fill", .watch,
                    "No room for another average turn at \(pct)% used.")
        }
        if self.avgTurnsLeft <= 2 {
            return ("exclamationmark.triangle.fill", .watch,
                    "Tight — \(self.avgTurnsLeft) avg turn\(self.avgTurnsLeft == 1 ? "" : "s") left.")
        }
        return ("info.circle", .calm,
                "~\(self.avgTurnsLeft) avg turns left at your pace.")
    }

    private var smallBucket: Int {
        max(2_000, Int(Double(self.pattern?.avg ?? 0) * 0.4))
    }
    private var mediumBucket: Int {
        max(6_000, self.pattern?.avg ?? 0)
    }
    private var largeBucket: Int {
        let avg = self.pattern?.avg ?? 0
        let p90 = self.pattern?.p90 ?? 0
        return max(20_000, max(p90, Int(Double(avg) * 2.5)))
    }

    var body: some View {
        if let ctx = self.workContext, let p = self.pattern, let v = self.verdict {
            VStack(alignment: .leading, spacing: 4) {
                // Verdict line
                HStack(spacing: 5) {
                    Image(systemName: v.icon)
                        .font(.system(size: 9))
                        .foregroundStyle(NotchPalette.tone(v.tone))
                    Text(v.copy)
                        .font(.geist(size: 10, weight: .semibold))
                        .foregroundStyle(NotchPalette.tone(v.tone))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }

                // Bucket chips — small / medium / large with sizes
                // derived from this user's pattern. Zero counts go red
                // so "0 large" reads instantly as "no big asks fit".
                HStack(spacing: 0) {
                    BucketChipNotch(
                        count: max(0, ctx.contextRemainingTokens / self.smallBucket),
                        label: "small",
                        size: "~\(compactTokens(self.smallBucket))")
                    BucketSepNotch()
                    BucketChipNotch(
                        count: max(0, ctx.contextRemainingTokens / self.mediumBucket),
                        label: "medium",
                        size: "~\(compactTokens(self.mediumBucket))")
                    BucketSepNotch()
                    BucketChipNotch(
                        count: max(0, ctx.contextRemainingTokens / self.largeBucket),
                        label: "large",
                        size: "~\(compactTokens(self.largeBucket))")
                    Spacer(minLength: 0)
                }

                // Transparency line — sample count, avg, trend.
                // The trend arrow is colored: ↑ red (turns running
                // heavier), ↓ green (lighter). This is the signal you
                // can't get from any single % number.
                HStack(spacing: 5) {
                    Text("based on your last \(p.samples.count) turn\(p.samples.count == 1 ? "" : "s")")
                        .font(.geist(size: 9))
                        .foregroundStyle(NotchPalette.tertiaryText)
                    Text("·")
                        .font(.geist(size: 9))
                        .foregroundStyle(NotchPalette.tertiaryText)
                    Text("avg \(compactTokens(p.avg))")
                        .font(.geistMono(size: 9))
                        .foregroundStyle(NotchPalette.tertiaryText)
                    if p.trend == .up {
                        Text("↑")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(NotchPalette.toneTight)
                    } else if p.trend == .down {
                        Text("↓")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(NotchPalette.toneCalm)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct BucketChipNotch: View {
    let count: Int
    let label: String
    let size: String

    var body: some View {
        HStack(spacing: 3) {
            Text("\(self.count)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(self.count == 0
                    ? NotchPalette.toneTight
                    : NotchPalette.primaryText)
                .contentTransition(.numericText())
            Text(self.label)
                .font(.geist(size: 9))
                .foregroundStyle(NotchPalette.tertiaryText)
            Text("(\(self.size))")
                .font(.geistMono(size: 8))
                .foregroundStyle(NotchPalette.tertiaryText.opacity(0.7))
        }
    }
}

private struct BucketSepNotch: View {
    var body: some View {
        Text("·")
            .font(.geist(size: 10))
            .foregroundStyle(NotchPalette.tertiaryText)
            .padding(.horizontal, 6)
    }
}

/// Pinnable session picker — a small chip with a Menu attached. Shows
/// the current project name, with a chevron when on auto and a pin
/// glyph when locked. Tapping opens a list of all live Claude
/// sessions; selecting one calls back via `onPin(sessionId)`. The
/// "Auto" entry passes nil to clear the pin and let the watcher fall
/// back to latest-mtime detection.
private struct SessionPickerChip: View {
    let currentLabel: String
    let sessions: [LiveSession]
    let pinnedId: String?
    let onPin: (String?) -> Void

    var body: some View {
        Menu {
            Button {
                self.onPin(nil)
            } label: {
                Label(
                    "Auto (latest active)",
                    systemImage: self.pinnedId == nil ? "checkmark" : "")
            }
            Divider()
            ForEach(self.sessions) { session in
                Button {
                    self.onPin(session.sessionId)
                } label: {
                    Label(
                        session.projectName,
                        systemImage: self.pinnedId == session.sessionId ? "pin.fill" : "")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: self.pinnedId != nil ? "pin.fill" : "rectangle.stack")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(self.pinnedId != nil
                        ? NotchPalette.accent
                        : NotchPalette.tertiaryText)
                Text(self.currentLabel)
                    .font(.geistMono(size: 9, weight: .medium))
                    .foregroundStyle(NotchPalette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(NotchPalette.tertiaryText.opacity(0.7))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule()
                    .fill(Color.white.opacity(0.04))
                    .overlay {
                        Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1)
                    }
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Small icon + text chip used for model/branch context in the NOW
/// hero's top-right corner. Subtle background, fixed-size — never
/// fights for attention against the verdict.
private struct ContextChip: View {
    let text: String
    let icon: String
    let accent: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: self.icon)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(self.accent)
            Text(self.text)
                .font(.geistMono(size: 9, weight: .medium))
                .foregroundStyle(NotchPalette.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background {
            Capsule()
                .fill(Color.white.opacity(0.04))
                .overlay {
                    Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
    }
}

/// Compact meter row for a rate-limit window. Label + bar + % + reset
/// time, all on one line. Modeled on the menu bar's `WindowRow`.
private struct WindowMeterRow: View {
    let label: String
    let percent: Double
    let tone: UsageTone
    let resetText: String
    let isActive: Bool
    /// Optional forecast — when present and meaningful, renders a
    /// secondary line under the main row showing "X% ahead of pace ·
    /// runs out in T" or "trending to Y% by reset". Only fiveHour
    /// and weekly currently produce forecast data; opus/sonnet pass
    /// nil and skip the sub-line.
    var forecast: NotchDisplayState.WindowForecastSummary? = nil
    /// Raw reset Date — used to format "back at HH:mm" in the
    /// depleted sub-line. When percent ≥ 99, the depleted line wins
    /// over the forecast line.
    var resetsAt: Date? = nil

    private var isDepleted: Bool { self.isActive && self.percent >= 99 }
    private var hasForecast: Bool { self.forecast != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Text(self.label.uppercased())
                    .font(.geist(size: 9, weight: .bold))
                    .foregroundStyle(NotchPalette.tertiaryText)
                    .tracking(1.0)
                    .frame(width: 76, alignment: .leading)
                    .lineLimit(1)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.07))
                        Capsule()
                            .fill(NotchPalette.tone(self.tone))
                            .frame(width: geo.size.width * min(1, max(0, self.percent / 100)))
                    }
                }
                .frame(height: 4)

                Text(self.isActive ? "\(Int(self.percent.rounded()))%" : "—")
                    .font(.geistMono(size: 11, weight: .semibold))
                    .foregroundStyle(self.isActive
                        ? NotchPalette.tone(self.tone)
                        : NotchPalette.tertiaryText)
                    .frame(width: 36, alignment: .trailing)
                    .contentTransition(.numericText())

                Text(self.isActive ? self.resetText : "—")
                    .font(.geistMono(size: 9))
                    .foregroundStyle(NotchPalette.tertiaryText)
                    .frame(width: 52, alignment: .trailing)
                    .lineLimit(1)
            }

            // Sub-line — depleted wins over forecast. Indented to
            // align under the meter portion (76pt label + 10pt gap).
            if self.isDepleted {
                NotchDepletedLine(resetsAt: self.resetsAt)
            } else if let f = self.forecast {
                NotchWindowForecastLine(percent: self.percent, forecast: f)
            }
        }
    }
}

/// "DEPLETED · back at HH:mm" line shown under a window row when
/// percent ≥ 99. Mirrors the menu bar's `DepletedLine` but uses the
/// notch palette's coral instead of red lavender.
private struct NotchDepletedLine: View {
    let resetsAt: Date?

    private var resetClock: String {
        guard let resetsAt else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: resetsAt)
    }

    var body: some View {
        HStack(spacing: 6) {
            Spacer().frame(width: 86) // align under meter, past label
            Text("DEPLETED")
                .font(.geist(size: 8, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(NotchPalette.toneTight)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(NotchPalette.toneTight.opacity(0.14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(NotchPalette.toneTight.opacity(0.35), lineWidth: 1)
                        }
                }
            Text("back at \(self.resetClock)")
                .font(.geist(size: 9))
                .foregroundStyle(NotchPalette.secondaryText)
            Spacer(minLength: 0)
        }
    }
}

/// "X% ahead of pace · runs out in T" sub-line. Mirrors the menu
/// bar's `ForecastLine`. Only renders when there's meaningful new
/// info beyond the percent already shown above.
private struct NotchWindowForecastLine: View {
    let percent: Double
    let forecast: NotchDisplayState.WindowForecastSummary

    private var trendsOver: Bool {
        (self.forecast.projectedAtResetPercent ?? 0) > 100
    }

    private var hasMeaningfulProjection: Bool {
        guard let proj = self.forecast.projectedAtResetPercent else { return false }
        return abs(proj - self.percent) >= 1
    }

    var body: some View {
        HStack(spacing: 5) {
            Spacer().frame(width: 86)

            Text("\(Int(self.forecast.aheadOfPacePercent.rounded()))% ahead of pace")
                .font(.geist(size: 9, weight: .semibold))
                .foregroundStyle(self.trendsOver
                    ? NotchPalette.toneTight
                    : NotchPalette.toneWatch)

            if self.hasMeaningfulProjection {
                Text("·")
                    .font(.geist(size: 9))
                    .foregroundStyle(NotchPalette.tertiaryText)

                if let runsOut = self.forecast.runsOutText {
                    Text(runsOut)
                        .font(.geist(size: 9))
                        .foregroundStyle(NotchPalette.toneTight)
                } else if let proj = self.forecast.projectedAtResetPercent {
                    Text("trending to \(Int(proj.rounded()))% by reset")
                        .font(.geist(size: 9))
                        .foregroundStyle(NotchPalette.tertiaryText)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

/// Three big stats strip across the top of SESSION — turns / tokens /
/// active. When spend data is available it adds a fourth column.
/// Big-number-with-tiny-label rhythm matches the menu bar header.
private struct TodayStrip: View {
    let state: NotchDisplayState

    var body: some View {
        HStack(spacing: 14) {
            TodayStat(
                value: self.state.hasTodayData ? "\(self.state.turnsToday)" : "—",
                label: "turns")
            TodayStripPipe()
            TodayStat(
                value: self.state.hasTodayData
                    ? compactTokens(self.state.totalTokensToday)
                    : "—",
                label: "tokens")
            TodayStripPipe()
            TodayStat(
                value: self.state.hasTodayData
                    ? formatMinutes(self.state.activeMinutesToday)
                    : "—",
                label: "active")
            if let spend = self.state.spendToday, spend > 0 {
                TodayStripPipe()
                TodayStat(
                    value: String(format: "$%.2f", spend),
                    label: "spend")
            }
            Spacer(minLength: 0)
        }
    }

    private func formatMinutes(_ value: Int) -> String {
        if value < 60 { return "\(value)m" }
        let h = value / 60
        let m = value % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

private struct TodayStat: View {
    let value: String
    let label: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(self.value)
                .font(.geistMono(size: 18, weight: .semibold))
                .foregroundStyle(NotchPalette.primaryText)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(self.label)
                .font(.geist(size: 9))
                .foregroundStyle(NotchPalette.tertiaryText)
        }
    }
}

private struct TodayStripPipe: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 16)
    }
}

/// One row in the advisor block. Tracking-spaced label on the left
/// (fixed width for column rhythm), then a two-line value/detail stack.
/// Mirrors the menu bar's `AdvisorInfoLine` but compact for the alcove.
private struct AdvisorInfoRow: View {
    let label: String
    let value: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(self.label)
                .font(.geist(size: 8, weight: .bold))
                .foregroundStyle(NotchPalette.tertiaryText)
                .tracking(1.4)
                .frame(width: 46, alignment: .leading)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 1) {
                Text(self.value)
                    .font(.geist(size: 11, weight: .semibold))
                    .foregroundStyle(NotchPalette.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !self.detail.isEmpty {
                    Text(self.detail)
                        .font(.geist(size: 9))
                        .foregroundStyle(NotchPalette.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One card on the PACE overview — ring viz + percent + label + status
/// sub-line. Lays out as equal flex inside a horizontal row of three.
/// Animated water-fill backdrop for the NOW hero. Vertical fill —
/// water rises bottom-up to height = card.height × context%. The TOP
/// of the water is a sine wave that drifts horizontally over time,
/// classic "addictive water loading bar" effect. Two waves overlay
/// at different speeds and amplitudes for a sense of depth.
///
/// Falls back to a static gradient fill on `prefers-reduced-motion`.
/// Animation only ticks while the alcove is open (parent gates with
/// `isHovering`) so TimelineView doesn't redraw in the background.
private struct HeroGradientBackdrop: View {
    let percent: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Animates from 0 → target on every appearance so each hover
    /// shows the water "pouring in" up to the current context %.
    /// Tracks `percent` changes smoothly while the alcove stays open.
    @State private var animatedProgress: Double = 0

    private var targetProgress: Double {
        min(1, max(0, self.percent / 100))
    }

    /// Continuously interpolated water color — blends across thresholds
    /// instead of stepping. Two segments: 0–55% blends calm → watch,
    /// 55–100% blends watch → tight. So at 30% you see mint with a hint
    /// of amber creeping in; at 75% amber with coral starting to show.
    /// The `UsageTone` bands (55, 82) still drive the *meaning* in the
    /// rest of the UI — this is purely the water's visual color.
    private var waterColor: Color {
        let p = max(0, min(1, self.animatedProgress))
        // RGB tuples for each tone — pulled directly from NotchPalette.
        let calm = (r: 0.36, g: 0.92, b: 0.78)
        let watch = (r: 1.00, g: 0.78, b: 0.30)
        let tight = (r: 1.00, g: 0.42, b: 0.38)

        let rgb: (r: Double, g: Double, b: Double)
        if p <= 0.55 {
            let t = p / 0.55
            rgb = Self.lerpRGB(calm, watch, t)
        } else {
            let t = (p - 0.55) / 0.45
            rgb = Self.lerpRGB(watch, tight, t)
        }
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private static func lerpRGB(
        _ a: (r: Double, g: Double, b: Double),
        _ b: (r: Double, g: Double, b: Double),
        _ rawT: Double) -> (r: Double, g: Double, b: Double)
    {
        let t = max(0, min(1, rawT))
        return (
            r: a.r * (1 - t) + b.r * t,
            g: a.g * (1 - t) + b.g * t,
            b: a.b * (1 - t) + b.b * t)
    }

    var body: some View {
        ZStack {
            // Subtle base wash so the un-filled portion of the card
            // isn't pure black against the alcove backdrop.
            Color.white.opacity(0.025)

            if self.reduceMotion {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            self.waterColor.opacity(0.24),
                            self.waterColor.opacity(0.36),
                        ],
                        startPoint: .top,
                        endPoint: .bottom)
                        .frame(height: geo.size.height * self.animatedProgress)
                        .frame(height: geo.size.height, alignment: .bottom)
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    // Two waves at slightly different speeds and
                    // wavelengths overlap to create depth — the
                    // "addictive" rolling-water feel comes from this
                    // interference pattern.
                    let phaseSlow = Angle(radians: t * 1.10)
                    let phaseFast = Angle(radians: t * 1.65)

                    ZStack {
                        // Back wave — slower, deeper amplitude, more
                        // transparent. Provides the body of the water.
                        Wave(
                            offset: phaseSlow,
                            percent: self.animatedProgress,
                            amplitudeFactor: 0.10,
                            frequency: 1.7)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        self.waterColor.opacity(0.20),
                                        self.waterColor.opacity(0.30),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom))

                        // Front wave — faster, shallower amplitude,
                        // more opaque. Sits over the back wave to
                        // create a parallax / depth illusion.
                        Wave(
                            offset: phaseFast,
                            percent: self.animatedProgress,
                            amplitudeFactor: 0.07,
                            frequency: 2.2)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        self.waterColor.opacity(0.26),
                                        self.waterColor.opacity(0.36),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom))
                    }
                }
            }

            // Readability scrim — sits ABOVE the waves but BEHIND the
            // verdict text (which lives outside this backdrop view).
            // A faint dark wash pulls the water's saturation down just
            // enough that white text retains contrast at any fill
            // level, especially when the water hits coral red.
            Color.black.opacity(0.10)
        }
        .onAppear {
            // Pour-in: start at 0, animate to target. Spring makes the
            // water level overshoot a hair before settling — gives the
            // fill a tactile "splash" feel without bouncing visibly.
            let from = 0.0
            let to = self.targetProgress
            self.animatedProgress = from
            let anim: Animation = self.reduceMotion
                ? .linear(duration: 0.05)
                : .spring(duration: 0.85, bounce: 0.20)
            withAnimation(anim) {
                self.animatedProgress = to
            }
            self.scheduleThresholdHaptics(from: from, to: to, duration: 0.85)
        }
        .onChange(of: self.percent) { oldPercent, _ in
            // Track live percent updates while the alcove stays open
            // (e.g., a refresh tick lands during a long hover).
            let from = self.animatedProgress
            let to = self.targetProgress
            let anim: Animation = self.reduceMotion
                ? .linear(duration: 0.05)
                : .spring(duration: 0.55, bounce: 0.12)
            withAnimation(anim) {
                self.animatedProgress = to
            }
            // Only haptic on the rising-fill animation, not when
            // alcove first appears (covered by onAppear above).
            _ = oldPercent
            self.scheduleThresholdHaptics(from: from, to: to, duration: 0.55)
        }
    }

    /// Fire a light haptic when the water crosses each tone threshold
    /// (0.55, 0.82) on its way up. SwiftUI's withAnimation doesn't
    /// expose intermediate `@State` values, so we predict the crossing
    /// time with a power-curve approximation of the spring's rising
    /// edge and schedule the haptics via `Task.sleep`. Only fires on
    /// rising crossings — context dropping doesn't tick.
    private func scheduleThresholdHaptics(from: Double, to: Double, duration: Double) {
        guard !self.reduceMotion, to > from else { return }
        let thresholds: [Double] = [0.55, 0.82]
        for threshold in thresholds {
            guard to > threshold, from < threshold else { continue }
            // Spring rises quickly at the start then settles; biasing
            // the linear normalized time by ^0.7 places the haptic at
            // roughly when the eye sees the level cross. Close enough.
            let normalized = (threshold - from) / (to - from)
            let crossFraction = pow(max(0.0001, normalized), 0.7)
            let delaySeconds = max(0.04, crossFraction * duration)
            let delayMs = Int(delaySeconds * 1000)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(delayMs))
                HapticGate.perform(.alignment)
            }
        }
    }
}

/// Sine-wave shape used to draw the water surface. The shape fills
/// the bottom portion of `rect` up to `percent` height, with the top
/// edge undulating as a sine wave whose phase is driven by `offset`
/// (animated externally via TimelineView).
///
/// `amplitudeFactor` is a fraction of `rect.height` — typical 0.05–0.12.
/// `frequency` is the number of full wavelengths across `rect.width`.
private struct Wave: Shape {
    var offset: Angle
    var percent: Double
    var amplitudeFactor: Double
    var frequency: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(self.offset.degrees, self.percent) }
        set {
            self.offset = .degrees(newValue.first)
            self.percent = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let waveHeight = self.amplitudeFactor * Double(rect.height)
        // Water surface y-position. Inverted axis: percent=0 → bottom
        // of the rect, percent=1 → top (with `waveHeight` padding so
        // the wave doesn't clip when full).
        let yOffset = (1.0 - self.percent)
            * (Double(rect.height) - waveHeight * 2.0)
            + waveHeight

        let segments = max(60, Int(rect.width / 3.0))
        let firstY = yOffset + waveHeight * sin(self.offset.radians)
        path.move(to: CGPoint(x: 0, y: firstY))

        // Trace the sine wave from left to right.
        for i in 1...segments {
            let x = Double(i) / Double(segments) * Double(rect.width)
            let radians = (x / Double(rect.width)) * 2.0 * .pi * self.frequency
                + self.offset.radians
            let y = yOffset + waveHeight * sin(radians)
            path.addLine(to: CGPoint(x: x, y: y))
        }

        // Close the bottom: down the right edge, across the bottom,
        // back up to the start point.
        path.addLine(to: CGPoint(x: Double(rect.width), y: Double(rect.height)))
        path.addLine(to: CGPoint(x: 0, y: Double(rect.height)))
        path.closeSubpath()

        return path
    }
}

// MARK: - WINDOWS tool

// MARK: - TODAY tool

/// TODAY tab — the daily activity log. Plan + project header, the big
/// today strip (turns / tokens / active / spend), peak hour, and an
/// inline FireBanner if a "playing with fire" moment is fresh.
private struct TodayTool: View {
    let state: NotchDisplayState

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            // Plan capsule + provider/project meta row.
            HStack(spacing: 6) {
                if let plan = self.state.planName, !plan.isEmpty {
                    Text(plan)
                        .font(.geist(size: 10, weight: .semibold))
                        .foregroundStyle(NotchPalette.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background {
                            Capsule().fill(NotchPalette.accent.opacity(0.15))
                                .overlay {
                                    Capsule().stroke(NotchPalette.accent.opacity(0.30), lineWidth: 1)
                                }
                        }
                }

                if !self.state.providerLabel.isEmpty {
                    Text(self.state.providerLabel)
                        .font(.geist(size: 10))
                        .foregroundStyle(NotchPalette.secondaryText)
                }

                if !self.state.projectLabel.isEmpty, self.state.projectLabel != "—" {
                    Text("·")
                        .font(.geist(size: 10))
                        .foregroundStyle(NotchPalette.tertiaryText)
                    Text(self.state.projectLabel)
                        .font(.geist(size: 10))
                        .foregroundStyle(NotchPalette.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }

            // The headline numbers — bigger here than on BURN since
            // TODAY is where the user comes for the daily rollup.
            TodayStrip(state: self.state)

            // Hairline below the strip then a 4-tile derived-stats
            // grid: peak hour, streak, $/turn, tokens/turn.
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            HStack(spacing: 6) {
                NowStatTile(
                    label: "PEAK",
                    value: self.state.peakHourLabel ?? "—",
                    accent: self.state.peakHourLabel != nil
                        ? NotchPalette.toneWatch
                        : NotchPalette.tertiaryText)
                NowStatTile(
                    label: "STREAK",
                    value: self.state.streakDays > 0
                        ? "\(self.state.streakDays)d"
                        : "—",
                    accent: self.state.streakDays > 0
                        ? NotchPalette.toneCalm
                        : NotchPalette.tertiaryText)
                NowStatTile(
                    label: "$ / TURN",
                    value: self.state.dollarsPerTurnToday
                        .map { String(format: "$%.2f", $0) } ?? "—",
                    accent: NotchPalette.toneCalm)
                NowStatTile(
                    label: "TKN/TURN",
                    value: self.state.tokensPerTurnToday > 0
                        ? compactTokens(self.state.tokensPerTurnToday)
                        : "—",
                    accent: NotchPalette.accent)
            }

            // Bottom — recent fire moment, OR active session footer.
            if self.state.fireActive {
                FireBanner(
                    turnTokens: self.state.fireTurnTokens,
                    contextPercent: self.state.fireContextPercent)
            } else if self.state.isLive,
                      !self.state.sessionDuration.isEmpty
            {
                HStack(spacing: 6) {
                    Circle()
                        .fill(NotchPalette.live)
                        .frame(width: 5, height: 5)
                    Text("LIVE SESSION")
                        .font(.geist(size: 8, weight: .bold))
                        .foregroundStyle(NotchPalette.tertiaryText)
                        .tracking(1.4)
                    Text(self.state.sessionDuration)
                        .font(.geistMono(size: 10, weight: .semibold))
                        .foregroundStyle(NotchPalette.primaryText)
                    if self.state.sessionTurns > 0 {
                        Text("·")
                            .font(.geist(size: 10))
                            .foregroundStyle(NotchPalette.tertiaryText)
                        Text("\(self.state.sessionTurns) turn\(self.state.sessionTurns == 1 ? "" : "s")")
                            .font(.geistMono(size: 10))
                            .foregroundStyle(NotchPalette.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - BURN tool

private struct BurnTool: View {
    let state: NotchDisplayState

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            // LIVE STAT GRID — 4-tile rate dashboard.
            HStack(spacing: 6) {
                NowStatTile(
                    label: "$ / MIN",
                    value: self.state.dollarsPerMinute > 0
                        ? String(format: "$%.2f", self.state.dollarsPerMinute)
                        : "—",
                    accent: self.state.dollarsPerMinute > 0
                        ? NotchPalette.toneCalm
                        : NotchPalette.tertiaryText)
                NowStatTile(
                    label: "TKN/MIN",
                    value: self.state.tokensPerMinute > 0
                        ? compactTokens(self.state.tokensPerMinute)
                        : "—",
                    accent: self.state.tokensPerMinute > 0
                        ? NotchPalette.accent
                        : NotchPalette.tertiaryText)
                NowStatTile(
                    label: "$ / TURN",
                    value: self.state.dollarsPerTurnToday
                        .map { String(format: "$%.2f", $0) } ?? "—",
                    accent: NotchPalette.toneCalm)
                NowStatTile(
                    label: "TKN/TURN",
                    value: self.state.tokensPerTurnToday > 0
                        ? compactTokens(self.state.tokensPerTurnToday)
                        : "—",
                    accent: NotchPalette.accent)
            }

            // LAST TURN — how much of the session this turn ate.
            if self.state.hasAdvisor, self.state.advisorLastTurnShare > 0 {
                LastTurnMeter(percent: self.state.advisorLastTurnShare)
            }

            // ─── COST section ───
            // Mirrors menu bar's Cost panel: synthetic $ + tokens for
            // today, last 30 days, and lifetime. Computed from a
            // rolling 30-day per-token rate (preferred) with a
            // lifetime-rate fallback so flat-plan users without
            // overage spend can still see what their tokens are
            // worth at retail rates.
            BurnSectionDivider(label: "COST")
            VStack(alignment: .leading, spacing: 6) {
                CostHistoryRow(
                    period: "Today",
                    cost: self.state.syntheticCostToday,
                    tokens: self.state.totalTokensToday)
                CostHistoryRow(
                    period: "Last 30 days",
                    cost: self.state.cost30d,
                    tokens: self.state.tokens30d)
                CostHistoryRow(
                    period: "Lifetime",
                    cost: self.state.costLifetime,
                    tokens: self.state.tokensLifetime)
            }

            // ─── MONTH section ───
            BurnSectionDivider(label: "MONTH")
            if let used = self.state.spendUsed,
               let limit = self.state.spendLimit, limit > 0
            {
                SpendBar(used: used, limit: limit)
                if let projected = self.state.projectedMonthSpend {
                    let overrun = projected > limit
                    HStack(spacing: 5) {
                        Image(systemName: overrun
                            ? "arrow.up.right.circle.fill"
                            : "arrow.right.circle")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(overrun
                                ? NotchPalette.toneTight
                                : NotchPalette.tertiaryText)
                        Text("on pace: ")
                            .font(.geist(size: 10))
                            .foregroundStyle(NotchPalette.tertiaryText)
                        Text(String(format: "$%.0f", projected))
                            .font(.geistMono(size: 10, weight: .semibold))
                            .foregroundStyle(overrun
                                ? NotchPalette.toneTight
                                : NotchPalette.primaryText)
                        Text("by month-end · \(self.state.daysRemainingInMonth)d left")
                            .font(.geist(size: 10))
                            .foregroundStyle(NotchPalette.tertiaryText)
                        Spacer(minLength: 0)
                    }
                }
            } else if let rate = self.state.dailySpendRate {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(NotchPalette.tertiaryText)
                    Text("7-day avg")
                        .font(.geist(size: 10))
                        .foregroundStyle(NotchPalette.tertiaryText)
                    Text(String(format: "$%.2f / day", rate))
                        .font(.geistMono(size: 10, weight: .semibold))
                        .foregroundStyle(NotchPalette.primaryText)
                    Spacer(minLength: 0)
                }
            } else {
                Text("warming up — needs ~2 days of spend history")
                    .font(.geist(size: 10))
                    .foregroundStyle(NotchPalette.tertiaryText)
            }
        }
    }
}

// MARK: - PATTERNS / WRAP / HEALTH tools
//
// These three reuse the menu bar's tab views directly so the alcove
// stays in feature parity with the menu bar without a duplicate
// implementation. Each is wrapped in a fixed-height frame so the
// inner ScrollView scrolls within the alcove drawer instead of
// overflowing past the maxDrawerHeight cap.
//
// The horizontal padding is negated (-16) because the menu bar views
// add their own contentPadding while AlcoveContent already pads 32pt
// — without the negation we'd lose ~32pt of inner width to nothing.

/// Drawer height the inner ScrollView is constrained to. Sits below
/// `NotchMorphHost.maxDrawerHeight` (420) by enough to leave room for
/// the alcove's tool strip and outer paddings.
private let alcoveScrollableHeight: CGFloat = 320

/// Wrap a menu-bar tab view so it fits inside the alcove drawer:
/// fixed height + edge negation so it occupies the full inner width.
private struct AlcoveTabHost<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        self.content()
            .padding(.horizontal, -16)
            .frame(height: alcoveScrollableHeight)
    }
}

private struct PatternsTool: View {
    let model: MenuBarModel

    var body: some View {
        if let snapshot = self.model.selectedSnapshot {
            AlcoveTabHost { PatternsView(snapshot: snapshot) }
        } else {
            EmptyTool(message: "No patterns yet — open Claude Code or Codex")
        }
    }
}

private struct WrapTool: View {
    let model: MenuBarModel

    var body: some View {
        if let snapshot = self.model.selectedSnapshot {
            AlcoveTabHost { WrapView(snapshot: snapshot) }
        } else {
            EmptyTool(message: "No wrap yet — use it for a few days")
        }
    }
}

private struct HealthTool: View {
    let model: MenuBarModel

    var body: some View {
        if let snapshot = self.model.selectedSnapshot {
            AlcoveTabHost { HealthView(snapshot: snapshot) }
        } else {
            EmptyTool(message: "No health data — waiting for your first session")
        }
    }
}

/// Section header used inside BURN to introduce TODAY / MONTH zones.
/// Tracking-spaced label on the left, hairline filling the rest.
private struct BurnSectionDivider: View {
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Text(self.label)
                .font(.geist(size: 8, weight: .bold))
                .foregroundStyle(NotchPalette.tertiaryText)
                .tracking(1.4)
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }
}

/// One row in the COST history block. Period label on the left, $
/// total in mono accent, dot, then token total in tertiary text.
/// Mirrors the menu bar's `CostRow` cost-formatting tiers.
private struct CostHistoryRow: View {
    let period: String
    let cost: Double?
    let tokens: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(self.period)
                .font(.geist(size: 11))
                .foregroundStyle(NotchPalette.secondaryText)
                .frame(width: 96, alignment: .leading)
            Text(self.costLabel)
                .font(.geistMono(size: 13, weight: .semibold))
                .foregroundStyle(NotchPalette.accent)
                .contentTransition(.numericText())
            if self.tokens > 0 {
                Text("·")
                    .font(.geist(size: 10))
                    .foregroundStyle(NotchPalette.tertiaryText)
                Text("\(compactTokens(self.tokens)) tokens")
                    .font(.geistMono(size: 10))
                    .foregroundStyle(NotchPalette.tertiaryText)
            }
            Spacer(minLength: 0)
        }
    }

    private var costLabel: String {
        guard let value = self.cost else { return "—" }
        if value == 0 { return "$0" }
        if value >= 1_000 { return String(format: "$%.1fk", value / 1_000) }
        if value >= 100 { return String(format: "$%.0f", value) }
        if value >= 1 { return String(format: "$%.2f", value) }
        return String(format: "$%.3f", value)
    }
}

/// Inline stat used inside BURN's TODAY section. Smaller than the big
/// top-grid tiles; reads like a stat line under a section header.
private struct BurnSectionStat: View {
    let label: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(self.value)
                .font(.geistMono(size: 14, weight: .semibold))
                .foregroundStyle(self.accent)
                .contentTransition(.numericText())
                .lineLimit(1)
            Text(self.label)
                .font(.geist(size: 9))
                .foregroundStyle(NotchPalette.tertiaryText)
        }
    }
}

private struct BigStat: View {
    let label: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(self.label)
                .font(.geist(size: 8, weight: .bold))
                .foregroundStyle(NotchPalette.tertiaryText)
                .tracking(1.2)
            Text(self.value)
                .font(.geistMono(size: 26, weight: .semibold))
                .foregroundStyle(self.accent)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BurnRow: View {
    let label: String
    let value: String
    let sublabel: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(self.label)
                    .font(.geist(size: 8, weight: .bold))
                    .foregroundStyle(NotchPalette.tertiaryText)
                    .tracking(1.2)
                if let sublabel {
                    Text(sublabel)
                        .font(.geist(size: 9))
                        .foregroundStyle(NotchPalette.tertiaryText)
                }
            }
            Spacer()
            Text(self.value)
                .font(.geistMono(size: 14, weight: .semibold))
                .foregroundStyle(NotchPalette.primaryText)
                .contentTransition(.numericText())
        }
    }
}

/// Compact meter showing the last user turn's new-context share.
/// Mirrors the menu bar Stamina section's `FlatMeter` for "Last turn"
/// — gives instant feedback on whether the most recent turn was a
/// nibble or a chunk. Tone shifts red when a single turn dominates.
private struct LastTurnMeter: View {
    let percent: Double

    private var tone: UsageTone {
        if self.percent >= 35 { return .tight }
        if self.percent >= 18 { return .watch }
        return .calm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("NEW CTX")
                    .font(.geist(size: 8, weight: .bold))
                    .foregroundStyle(NotchPalette.tertiaryText)
                    .tracking(1.2)
                Spacer()
                Text("\(compactShare(self.percent)) of window")
                    .font(.geistMono(size: 9))
                    .foregroundStyle(NotchPalette.secondaryText)
                    .contentTransition(.numericText())
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(NotchPalette.tone(self.tone))
                        .frame(width: geo.size.width * min(1, self.percent / 100))
                }
            }
            .frame(height: 4)
        }
    }
}

private struct SpendBar: View {
    let used: Double
    let limit: Double

    private var percent: Double {
        guard self.limit > 0 else { return 0 }
        return min(200, max(0, self.used / self.limit * 100))
    }

    private var tone: UsageTone {
        UsageTone(percent: min(100, self.percent))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("MONTHLY SPEND")
                    .font(.geist(size: 8, weight: .bold))
                    .foregroundStyle(NotchPalette.tertiaryText)
                    .tracking(1.2)
                Spacer()
                Text("\(Int(self.percent.rounded()))% of $\(Int(self.limit))")
                    .font(.geistMono(size: 9))
                    .foregroundStyle(NotchPalette.secondaryText)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(NotchPalette.tone(self.tone))
                        .frame(width: geo.size.width * min(1, self.percent / 100))
                }
            }
            .frame(height: 4)
        }
    }
}

private struct FireBanner: View {
    let turnTokens: Int
    let contextPercent: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchPalette.danger)
                .symbolEffect(.pulse, options: .repeating)
            VStack(alignment: .leading, spacing: 0) {
                Text("PLAYING WITH FIRE")
                    .font(.geist(size: 8, weight: .bold))
                    .foregroundStyle(NotchPalette.danger)
                    .tracking(1.4)
                Text("\(compactTokens(self.turnTokens)) tokens at \(Int(self.contextPercent.rounded()))%")
                    .font(.geist(size: 10))
                    .foregroundStyle(NotchPalette.primaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(NotchPalette.danger.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(NotchPalette.danger.opacity(0.28), lineWidth: 1)
                }
        }
    }
}

private struct NotchThresholdToast: View {
    let alert: NotchThresholdAlert

    private var tint: Color {
        NotchPalette.tone(self.alert.tone)
    }

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(self.tint.opacity(0.18))
                Image(systemName: self.alert.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(self.tint)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(self.alert.title)
                    .font(.geist(size: 10, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(NotchPalette.primaryText)
                    .lineLimit(1)
                Text(self.alert.detail)
                    .font(.geist(size: 10, weight: .medium))
                    .foregroundStyle(NotchPalette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
        .padding(.trailing, 11)
        .padding(.vertical, 7)
        .frame(width: 310, alignment: .leading)
        .background {
            Capsule()
                .fill(Color.black.opacity(0.92))
                .overlay {
                    Capsule()
                        .stroke(self.tint.opacity(0.42), lineWidth: 1)
                }
        }
        .shadow(color: Color.black.opacity(0.35), radius: 18, y: 8)
    }
}

// MARK: - Empty tool placeholder

private struct EmptyTool: View {
    let message: String

    var body: some View {
        HStack {
            Spacer()
            Text(self.message)
                .font(.geist(size: 11))
                .foregroundStyle(NotchPalette.tertiaryText)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.vertical, 30)
    }
}

// MARK: - Dev panel (choreography + spring pickers, hidden behind wrench)

private struct DevPanel: View {
    let model: MenuBarModel
    let onTriggerDebugAlert: (NotchThresholdAlert) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ToastDebugSection(onTrigger: self.onTriggerDebugAlert)
            CalibrationSection(model: self.model)
            HapticToggleSection(model: self.model)
            ExpandStylePicker(model: self.model)
        }
    }
}

private struct ToastDebugSection: View {
    let onTrigger: (NotchThresholdAlert) -> Void
    @State private var cycleIndex = 0

    private static let fixtures: [NotchThresholdAlert] = [
        NotchThresholdAlert(
            id: "debug-burst-5",
            title: "BURST IN 5m",
            detail: "Slow down; 5h cap is projected to hit.",
            symbol: "flame.fill",
            tone: .tight),
        NotchThresholdAlert(
            id: "debug-burst-15",
            title: "BURST IN 15m",
            detail: "Projection says the burst window is closing.",
            symbol: "speedometer",
            tone: .watch),
        NotchThresholdAlert(
            id: "debug-burst-hot",
            title: "BURST HOT",
            detail: "95% used · final turns only",
            symbol: "bolt.trianglebadge.exclamationmark.fill",
            tone: .tight),
        NotchThresholdAlert(
            id: "debug-context-75",
            title: "CONTEXT HEATING",
            detail: "75% used · keep the next ask focused",
            symbol: "eye.fill",
            tone: .watch),
        NotchThresholdAlert(
            id: "debug-context-86",
            title: "CONTEXT TIGHT",
            detail: "86% used · compact soon",
            symbol: "text.badge.exclamationmark",
            tone: .tight),
        NotchThresholdAlert(
            id: "debug-weekly",
            title: "WEEKLY CAP HOT",
            detail: "93% used · reset in 2d",
            symbol: "calendar.badge.exclamationmark",
            tone: .watch),
        NotchThresholdAlert(
            id: "debug-spend",
            title: "SPEND CAP TRACKING",
            detail: "on pace for $118 of $100",
            symbol: "dollarsign.circle.fill",
            tone: .watch),
        NotchThresholdAlert(
            id: "debug-big-turn",
            title: "BIG TURN",
            detail: "42K tokens · 78% context",
            symbol: "flame.fill",
            tone: .tight),
        NotchThresholdAlert(
            id: "debug-depleted",
            title: "BURST DEPLETED",
            detail: "back in 18m",
            symbol: "lock.fill",
            tone: .tight),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("TOAST LAB")
                    .font(.geist(size: 8, weight: .bold))
                    .foregroundStyle(NotchPalette.tertiaryText)
                    .tracking(1.2)
                Spacer()
                Button(action: self.triggerNext) {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text("CYCLE")
                            .font(.geistMono(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(NotchPalette.accent))
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 82, maximum: 112), spacing: 6)
                ],
                alignment: .leading,
                spacing: 6)
            {
                ForEach(Self.fixtures) { alert in
                    Button(action: { self.onTrigger(self.unique(alert)) }) {
                        HStack(spacing: 5) {
                            Image(systemName: alert.symbol)
                                .font(.system(size: 8, weight: .bold))
                            Text(self.shortLabel(for: alert))
                                .font(.geistMono(size: 8, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(NotchPalette.tone(alert.tone))
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .padding(.horizontal, 6)
                        .background {
                            Capsule()
                                .fill(Color.white.opacity(0.035))
                                .overlay {
                                    Capsule()
                                        .stroke(NotchPalette.tone(alert.tone).opacity(0.25), lineWidth: 1)
                                }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func triggerNext() {
        guard !Self.fixtures.isEmpty else { return }
        let alert = Self.fixtures[self.cycleIndex % Self.fixtures.count]
        self.cycleIndex += 1
        self.onTrigger(self.unique(alert))
    }

    private func unique(_ alert: NotchThresholdAlert) -> NotchThresholdAlert {
        NotchThresholdAlert(
            id: "\(alert.id)-\(UUID().uuidString)",
            title: alert.title,
            detail: alert.detail,
            symbol: alert.symbol,
            tone: alert.tone)
    }

    private func shortLabel(for alert: NotchThresholdAlert) -> String {
        alert.title
            .replacingOccurrences(of: "CONTEXT ", with: "CTX ")
            .replacingOccurrences(of: "WEEKLY CAP ", with: "WEEKLY ")
            .replacingOccurrences(of: "SPEND CAP ", with: "SPEND ")
            .replacingOccurrences(of: "BURST DEPLETED", with: "DEPLETED")
    }
}

/// Master haptic toggle. OFF by default. The body lists every alcove
/// surface that fires a haptic so the user knows what they're opting
/// into — important because trackpad haptics carry more weight than
/// a sound or animation, and people deserve to know upfront.
private struct HapticToggleSection: View {
    let model: MenuBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("HAPTICS")
                    .font(.geist(size: 8, weight: .bold))
                    .foregroundStyle(NotchPalette.tertiaryText)
                    .tracking(1.2)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { self.model.hapticsEnabled },
                    set: { self.model.setHapticsEnabled($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(NotchPalette.accent)
                    .controlSize(.small)
            }
            Text("Trackpad feedback for: alcove open/close, pinning a conversation pill, switching provider, fire-banner trigger, and the tight-context heartbeat at 82%+. Off by default.")
                .font(.geist(size: 10))
                .foregroundStyle(NotchPalette.tertiaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Dev-panel section that launches interactive calibration. Clicking
/// the button enters calibration mode (`model.notchCalibrating = true`)
/// which auto-closes the alcove so the user can grab the silhouette and
/// drag its corners. A floating badge appears below the silhouette with
/// dimensions and a DONE button. Reset clears any override and falls
/// back to auto-detected size.
private struct CalibrationSection: View {
    let model: MenuBarModel

    private var detectedSize: CGSize {
        if let frame = NSScreen.main?.notchFrame {
            return frame.size
        }
        return CGSize(width: 200, height: 24)
    }

    private var currentWidth: Double {
        self.model.notchWidthOverride ?? Double(self.detectedSize.width)
    }
    private var currentHeight: Double {
        self.model.notchHeightOverride ?? Double(self.detectedSize.height)
    }
    private var isOverridden: Bool {
        self.model.notchWidthOverride != nil || self.model.notchHeightOverride != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("CALIBRATION")
                    .font(.geist(size: 8, weight: .bold))
                    .foregroundStyle(NotchPalette.tertiaryText)
                    .tracking(1.2)
                Spacer()
                Text("\(Int(self.currentWidth.rounded()))×\(Int(self.currentHeight.rounded())) · detected \(Int(self.detectedSize.width))×\(Int(self.detectedSize.height))")
                    .font(.geistMono(size: 9))
                    .foregroundStyle(self.isOverridden
                        ? NotchPalette.accent
                        : NotchPalette.tertiaryText)
            }

            HStack(spacing: 8) {
                Button(action: { self.model.setNotchCalibrating(true) }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                        Text("CALIBRATE NOTCH")
                            .font(.geistMono(size: 10, weight: .bold))
                            .tracking(1.0)
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(NotchPalette.accent))
                }
                .buttonStyle(.plain)

                Button(action: {
                    self.model.setNotchWidthOverride(nil)
                    self.model.setNotchHeightOverride(nil)
                }) {
                    Text("RESET")
                        .font(.geistMono(size: 10, weight: .semibold))
                        .foregroundStyle(NotchPalette.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            Capsule()
                                .fill(Color.white.opacity(0.04))
                                .overlay {
                                    Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1)
                                }
                        }
                }
                .buttonStyle(.plain)
                .opacity(self.isOverridden ? 1 : 0.35)
                .disabled(!self.isOverridden)

                Spacer(minLength: 0)
            }

            Text("Drag the corners on the closed notch to fit your hardware.")
                .font(.geist(size: 9))
                .foregroundStyle(NotchPalette.tertiaryText)
        }
    }
}

// MARK: - Animations & Transitions

struct BlurTransitionModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 0 : 1)
            .blur(radius: isActive ? 4 : 0)
            .scaleEffect(isActive ? 0.98 : 1)
    }
}

// MARK: - Calibration handle + badge (used by NotchMorphHost)

private struct CalibrationHandle: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(NotchPalette.accent)
                .frame(width: 14, height: 14)
            Circle()
                .stroke(Color.black.opacity(0.4), lineWidth: 1)
                .frame(width: 14, height: 14)
        }
        .shadow(color: NotchPalette.accent.opacity(0.6), radius: 5)
        .contentShape(Circle())
    }
}

private struct CalibrationBadge: View {
    let width: CGFloat
    let height: CGFloat
    let onDone: () -> Void
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Text("W ")
                    .font(.geist(size: 8, weight: .bold))
                    .foregroundStyle(NotchPalette.tertiaryText)
                    .tracking(0.8)
                Text("\(Int(self.width.rounded()))")
                    .font(.geistMono(size: 11, weight: .semibold))
                    .foregroundStyle(NotchPalette.primaryText)
                    .contentTransition(.numericText())
                Text("  H ")
                    .font(.geist(size: 8, weight: .bold))
                    .foregroundStyle(NotchPalette.tertiaryText)
                    .tracking(0.8)
                Text("\(Int(self.height.rounded()))")
                    .font(.geistMono(size: 11, weight: .semibold))
                    .foregroundStyle(NotchPalette.primaryText)
                    .contentTransition(.numericText())
            }

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 1, height: 14)

            Button(action: self.onReset) {
                Text("RESET")
                    .font(.geistMono(size: 9, weight: .semibold))
                    .foregroundStyle(NotchPalette.secondaryText)
            }
            .buttonStyle(.plain)

            Button(action: self.onDone) {
                Text("DONE")
                    .font(.geistMono(size: 9, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(NotchPalette.accent))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(Color.black)
                .overlay {
                    Capsule().stroke(NotchPalette.accent.opacity(0.55), lineWidth: 1)
                }
        }
    }
}

private struct ExpandStylePicker: View {
    let model: MenuBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("CHOREOGRAPHY")
                        .font(.geist(size: 8, weight: .bold))
                        .foregroundStyle(NotchPalette.tertiaryText)
                        .tracking(1.2)
                    Spacer()
                    Text(self.model.alcoveChoreography.label)
                        .font(.geistMono(size: 9, weight: .semibold))
                        .foregroundStyle(NotchPalette.accent)
                }

                ChipFlow(items: AlcoveChoreography.allCases.map(\.label),
                         selected: self.model.alcoveChoreography.label) { label in
                    if let pick = AlcoveChoreography.allCases.first(where: { $0.label == label }) {
                        self.model.setAlcoveChoreography(pick)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("SPRING")
                    .font(.geist(size: 8, weight: .bold))
                    .foregroundStyle(NotchPalette.tertiaryText)
                    .tracking(1.2)

                HStack(spacing: 5) {
                    ForEach(AlcoveSpring.allCases) { spring in
                        ChipButton(
                            label: spring.label,
                            isSelected: self.model.alcoveSpring == spring,
                            action: { self.model.setAlcoveSpring(spring) })
                    }
                }
            }
        }
    }
}

private struct ChipFlow: View {
    let items: [String]
    let selected: String
    let onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(self.items, id: \.self) { label in
                ChipButton(
                    label: label,
                    isSelected: label == self.selected,
                    action: { self.onTap(label) })
            }
        }
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + self.spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + self.spacing
            rowHeight = max(rowHeight, size.height)
            totalHeight = y + rowHeight
        }

        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + self.spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + self.spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct ChipButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Text(self.label)
                .font(.geistMono(size: 9, weight: self.isSelected ? .semibold : .medium))
                .foregroundStyle(self.isSelected
                    ? NotchPalette.primaryText
                    : NotchPalette.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    if self.isSelected {
                        Capsule()
                            .fill(NotchPalette.accent.opacity(0.28))
                            .overlay {
                                Capsule().stroke(NotchPalette.accent.opacity(0.55), lineWidth: 1)
                            }
                    } else {
                        Capsule()
                            .fill(Color.white.opacity(0.04))
                            .overlay {
                                Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1)
                            }
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Alcove top row (in-alcove header beside the notch silhouette)

/// Renders the project label + provider on the left side of the notch
/// silhouette and the turn count + session duration on the right side,
/// inside the expanded alcove. Reserves a transparent gap in the middle
/// matching the hardware notch so the black notch shape protrudes
/// cleanly through. Replaces the old below-the-notch AlcoveHeader.
private struct AlcoveTopRow: View {
    let state: NotchDisplayState
    let model: MenuBarModel
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    @State private var pulse = false
    @State private var providerHovered = false

    /// Provider toggle is only useful when both Codex and Claude have
    /// snapshots — otherwise there's nothing to switch to.
    private var canSwitchProvider: Bool {
        self.model.overview.snapshots.count > 1
    }

    /// Session picker shows when (a) we're viewing Claude (only Claude
    /// is pinnable in the watcher path) and (b) there are 2+ unique
    /// live Claude sessions to choose from. Single-session users see
    /// a plain label.
    private var canPickClaudeSession: Bool {
        self.model.selectedProvider == .claude
            && self.uniqueClaudeSessions.count >= 2
    }

    /// Dedupe the live Claude session list by sessionId so the menu
    /// doesn't show the same project twice if a session restarted.
    private var uniqueClaudeSessions: [LiveSession] {
        var seen: Set<String> = []
        var result: [LiveSession] = []
        for session in self.state.liveClaudeSessions where !seen.contains(session.sessionId) {
            seen.insert(session.sessionId)
            result.append(session)
        }
        return result
    }

    var body: some View {
        HStack(spacing: 0) {
            // LEFT zone — flex-fills the left half of the alcove and
            // right-aligns its content so the chip butts up against
            // the notch silhouette. The plan tier badge replaces the
            // old live-dot + project label since "what plan am I on"
            // is the more anchoring question; live state surfaces
            // through the live pill column on the hero instead.
            HStack(spacing: 6) {
                if let plan = self.model.selectedSnapshot?.planName {
                    Text(plan.uppercased())
                        .font(.geistMono(size: 9, weight: .bold))
                        .foregroundStyle(NotchPalette.accent)
                        .tracking(1.2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background {
                            Capsule()
                                .fill(NotchPalette.accent.opacity(0.16))
                                .overlay {
                                    Capsule()
                                        .stroke(NotchPalette.accent.opacity(0.42), lineWidth: 1)
                                }
                        }
                }

                if !self.state.providerLabel.isEmpty {
                    Text("·")
                        .font(.geist(size: 11))
                        .foregroundStyle(NotchPalette.tertiaryText)

                    Button(action: {
                        if self.canSwitchProvider {
                            // Firmer pattern — provider switch is a
                            // committed action, not a hover-debounce.
                            HapticGate.perform(.levelChange)
                            self.model.cycleProvider()
                        }
                    }) {
                        HStack(spacing: 4) {
                            ProviderMark(
                                kind: self.model.selectedProvider,
                                size: 13)
                                .foregroundStyle(self.canSwitchProvider && self.providerHovered
                                    ? NotchPalette.primaryText
                                    : NotchPalette.secondaryText)
                            if self.canSwitchProvider {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(self.providerHovered
                                        ? NotchPalette.accent
                                        : NotchPalette.tertiaryText.opacity(0.6))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(self.canSwitchProvider
                        ? "Switch to \(self.model.selectedProvider == .claude ? "Codex" : "Claude Code")"
                        : self.state.providerLabel)
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.12)) {
                            self.providerHovered = hovering
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 12)

            // Notch reservation — invisible spacer matching the
            // silhouette size; the black mask sits over this from the
            // parent ZStack.
            Color.clear
                .frame(width: self.notchWidth, height: self.notchHeight)

            // RIGHT zone — concurrent live sessions counter with
            // project names filling the available width. The most-
            // glance-worthy "what's actually burning right now" stat.
            // Burn rate stuff (tokens/min, $/min) lives in BURN tab.
            HStack(spacing: 5) {
                if self.state.liveSessionCount > 0 {
                    LiveSessionsBadge(
                        count: self.state.liveSessionCount,
                        projects: self.state.liveSessionProjects)
                }
                if let cue = self.state.ambientCueColor {
                    Circle()
                        .fill(cue)
                        .frame(width: 5, height: 5)
                        .padding(.leading, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
        }
    }
}

// MARK: - Notch shape

private struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(self.topCornerRadius, self.bottomCornerRadius) }
        set {
            self.topCornerRadius = newValue.first
            self.bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = self.topCornerRadius
        let bot = self.bottomCornerRadius

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bot))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bot, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top - bot, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bot),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        return path
    }
}

// MARK: - NSScreen extensions

private extension NSScreen {
    var hasNotchAuxiliaryAreas: Bool {
        self.auxiliaryTopLeftArea?.width != nil
            && self.auxiliaryTopRightArea?.width != nil
    }

    var notchFrame: NSRect? {
        guard let leftPad = self.auxiliaryTopLeftArea?.width,
              let rightPad = self.auxiliaryTopRightArea?.width
        else { return nil }
        let height = self.safeAreaInsets.top
        let width = self.frame.width - leftPad - rightPad
        return NSRect(
            x: self.frame.midX - (width / 2),
            y: self.frame.maxY - height,
            width: width,
            height: height)
    }
}
