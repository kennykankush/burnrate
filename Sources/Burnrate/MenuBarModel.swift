import BurnrateCore
import Darwin
import Foundation
import Observation
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case now
    case surface
    case patterns
    case wrap
    case health

    var id: String { self.rawValue }

    var label: String {
        switch self {
        case .now: "Now"
        case .surface: "Map"
        case .patterns: "Patterns"
        case .wrap: "Wrap"
        case .health: "Health"
        }
    }

    var symbol: String {
        switch self {
        case .now: "flame"
        case .surface: "map"
        case .patterns: "square.grid.2x2"
        case .wrap: "calendar"
        case .health: "stethoscope"
        }
    }

    /// Keyboard shortcut bound on each tab button. ⌘1\u{2013}⌘5 follows
    /// the macOS convention used by Mail, Safari, etc.
    var keyEquivalent: Character {
        switch self {
        case .now: "1"
        case .surface: "2"
        case .patterns: "3"
        case .wrap: "4"
        case .health: "5"
        }
    }
}

/// Choreography of the notch alcove's open animation. Every case spawns
/// the alcove FROM the notch silhouette outward — no slides-from-outside.
/// Inspired by Disney's 12 principles (anticipation, squash & stretch,
/// follow-through), Dynamic Island morph patterns, and NotchNook/Alcove
/// references.
enum AlcoveChoreography: String, CaseIterable, Identifiable {
    case morph         // 1. Width + height grow together. Default.
    case cascade       // 2. Height drops first, width fans after.
    case curtain       // 3. Width spreads first, height drops after.
    case iris          // 4. Pre-full, scales up from notch.
    case unfold        // 5. Width pre-set, height grows. Drawer.
    case bloom         // 6. Corners morph first, dims catch up.
    case swell         // 7. Width overshoots, settles back.
    case drip          // 8. Width fast, height with gravity bounce.
    case squeeze       // 9. Anticipation: w pre-contracts, then expands.
    case press         // 10. Anticipation: corners tighten, then release.
    case stagger       // 11. 3-phase: corners → width → height.
    case ripple        // 12. Bottom corner morphs first, then top, then dims.
    case balloon       // 13. Both axes overshoot equally.
    case wobble        // 14. Opens, oscillates over/under target, settles.
    case echo          // 15. Opens fast, briefly recedes, settles wide.
    case fall          // 16. Height falls with gravity overshoot, settles.
    case rebound       // 17. Height drops past, springs back hard.
    case jelly         // 18. Width stretches wide while height still small.
    case fountain      // 19. Height grows fast, width fans with overshoot.
    case liquid        // 20. Both axes overshoot in sequence, settle together.

    var id: String { self.rawValue }

    var label: String {
        switch self {
        case .morph: "morph"
        case .cascade: "cascade"
        case .curtain: "curtain"
        case .iris: "iris"
        case .unfold: "unfold"
        case .bloom: "bloom"
        case .swell: "swell"
        case .drip: "drip"
        case .squeeze: "squeeze"
        case .press: "press"
        case .stagger: "stagger"
        case .ripple: "ripple"
        case .balloon: "balloon"
        case .wobble: "wobble"
        case .echo: "echo"
        case .fall: "fall"
        case .rebound: "rebound"
        case .jelly: "jelly"
        case .fountain: "fountain"
        case .liquid: "liquid"
        }
    }

    /// Approximate total duration. Used to schedule the content fade-in
    /// so it lands as the geometry settles.
    var totalDuration: Double {
        switch self {
        case .morph: return 0.34
        case .cascade, .curtain: return 0.42
        case .iris, .unfold: return 0.36
        case .bloom: return 0.46
        case .swell: return 0.50
        case .drip: return 0.50
        case .squeeze, .press: return 0.46
        case .stagger: return 0.50
        case .ripple: return 0.50
        case .balloon: return 0.50
        case .wobble: return 0.58
        case .echo: return 0.54
        case .fall: return 0.50
        case .rebound: return 0.58
        case .jelly: return 0.54
        case .fountain: return 0.50
        case .liquid: return 0.60
        }
    }
}

/// Spring intensity that wraps every choreography. Independent dial —
/// you can pair any choreography with any spring to taste.
enum AlcoveSpring: String, CaseIterable, Identifiable {
    /// Confident default. Low overshoot, NotchNook feel.
    case smooth
    /// Very fast, no bounce. Linear/Raycast snap.
    case snappy
    /// Visible overshoot. Playful.
    case bouncy
    /// Slow, gentle. Big calm reveal.
    case soft
    /// Dramatic overshoot. Toy-like.
    case elastic
    /// Quick + bouncy. Punchy.
    case pop

    var id: String { self.rawValue }

    var label: String {
        switch self {
        case .smooth: "smooth"
        case .snappy: "snappy"
        case .bouncy: "bouncy"
        case .soft: "soft"
        case .elastic: "elastic"
        case .pop: "pop"
        }
    }

    /// Base spring curve. Choreographies may layer additional per-axis
    /// curves on top (e.g. drip's gravity-pulled height bounce).
    func baseSpring(for choreography: AlcoveChoreography) -> Animation {
        switch self {
        case .smooth:  return .spring(duration: 0.32, bounce: 0.15)
        case .snappy:  return .spring(duration: 0.22, bounce: 0)
        case .bouncy:  return .spring(duration: 0.40, bounce: 0.32)
        case .soft:    return .spring(duration: 0.50, bounce: 0.06)
        case .elastic: return .spring(duration: 0.58, bounce: 0.46)
        case .pop:     return .spring(duration: 0.30, bounce: 0.28)
        }
    }

    /// Multiplier applied to per-choreography duration when scheduling
    /// content fade-in. Bouncy/elastic springs settle later.
    var contentDelayMultiplier: Double {
        switch self {
        case .smooth:  return 0.85
        case .snappy:  return 0.70
        case .bouncy:  return 1.05
        case .soft:    return 1.10
        case .elastic: return 1.20
        case .pop:     return 0.95
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
    case codexSurface
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
        case .codexSurface: "MAP"
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
        case .fiveHour: "5h burst used"
        case .weekly: "Weekly used"
        case .codexSurface: "Codex map"
        case .dollarsPerMin: "USD / minute"
        case .tokensPerMin: "Tokens / minute"
        case .streak: "Streak"
        case .cacheHit: "Cache hit %"
        }
    }
}

/// How much the menu-bar anchor should show. The notch is the primary
/// product surface now, so the status item can stay as quiet as the user
/// wants while still giving quick access to settings.
enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Hashable {
    case iconOnly
    case iconAndMetric
    case metricStack

    var id: String { self.rawValue }

    var label: String {
        switch self {
        case .iconOnly: "Icon"
        case .iconAndMetric: "Icon + value"
        case .metricStack: "Two-line"
        }
    }

    var menuTitle: String {
        switch self {
        case .iconOnly: "Icon only"
        case .iconAndMetric: "Icon and value"
        case .metricStack: "Two-line metric"
        }
    }
}

/// Symbol style for the menu-bar anchor. SF Symbols are resolved at
/// runtime so users can change the visible mark without changing what
/// the notch itself shows.
enum MenuBarIconStyle: String, CaseIterable, Identifiable, Hashable {
    case flame
    case provider
    case gauge
    case notch
    case command

    var id: String { self.rawValue }

    var label: String {
        switch self {
        case .flame: "Flame"
        case .provider: "Provider"
        case .gauge: "Gauge"
        case .notch: "Notch"
        case .command: "Command"
        }
    }

    func symbol(for provider: ProviderKind) -> String {
        switch self {
        case .flame:
            return "flame.fill"
        case .provider:
            switch provider {
            case .codex: return "terminal.fill"
            case .claude: return "sparkles"
            }
        case .gauge:
            return "gauge"
        case .notch:
            return "capsule.fill"
        case .command:
            return "command"
        }
    }
}

/// What the status item should render right now. The `label` is the
/// abbreviated top-line text; `value` is the bottom-line value.
struct MenuBarDisplay: Equatable {
    let label: String
    let value: String
    let detail: String?

    init(label: String, value: String, detail: String? = nil) {
        self.label = label
        self.value = value
        self.detail = detail
    }

    var toolTip: String {
        if let detail, !detail.isEmpty {
            return "\(self.label) \(self.value) - \(detail)"
        }
        return "\(self.label) \(self.value)"
    }

    static let placeholder = MenuBarDisplay(label: "—", value: "—")
}

private final class LocalFileChangeWatcher: @unchecked Sendable {
    private var sources: [URL: DispatchSourceFileSystemObject] = [:]
    private let queue = DispatchQueue(label: "fyi.burnrate.identity-file-watcher")

    func update(urls: Set<URL>, onChange: @escaping @Sendable () -> Void) {
        let current = Set(self.sources.keys)
        for url in current.subtracting(urls) {
            self.remove(url)
        }
        for url in urls.subtracting(current) {
            self.add(url, onChange: onChange)
        }
    }

    func cancelAll() {
        for source in self.sources.values {
            source.cancel()
        }
        self.sources.removeAll()
    }

    private func add(_ url: URL, onChange: @escaping @Sendable () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .delete, .rename],
            queue: self.queue)
        source.setEventHandler(handler: onChange)
        source.setCancelHandler {
            close(fd)
        }
        self.sources[url] = source
        source.resume()
    }

    private func remove(_ url: URL) {
        guard let source = self.sources.removeValue(forKey: url) else { return }
        source.cancel()
    }
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
    private var lastPreviewRefreshAt: Date?
    var fireEvent: FireEvent?
    var alertMode: UsageAlertMode = UsageAlertMode(rawValue: UserDefaults.standard.string(forKey: UsageNotificationController.alertModeKey) ?? "") ?? .all
    var isLaunchAtLoginEnabled: Bool = LaunchAtLoginManager.isEnabled
    var selectedMenuBarModule: MenuBarModule = MenuBarModule(rawValue: UserDefaults.standard.string(forKey: MenuBarModel.menuBarModuleKey) ?? "") ?? .context
    var menuBarDisplayMode: MenuBarDisplayMode = MenuBarDisplayMode(
        rawValue: UserDefaults.standard.string(forKey: MenuBarModel.menuBarDisplayModeKey) ?? ""
    ) ?? .iconAndMetric
    var menuBarIconStyle: MenuBarIconStyle = MenuBarIconStyle(
        rawValue: UserDefaults.standard.string(forKey: MenuBarModel.menuBarIconStyleKey) ?? ""
    ) ?? .flame
    /// User-controlled toggle for the notch widget. Default is the
    /// negation of "is the user even on a notched MacBook" so notch-less
    /// users never see a stray rounded pill at the top of their screen.
    /// On notched hardware the default is true.
    var notchEnabled: Bool = MenuBarModel.loadNotchEnabledDefault()
    var alcoveChoreography: AlcoveChoreography = AlcoveChoreography(
        rawValue: UserDefaults.standard.string(forKey: MenuBarModel.alcoveChoreographyKey) ?? ""
    ) ?? .morph
    var alcoveSpring: AlcoveSpring = AlcoveSpring(
        rawValue: UserDefaults.standard.string(forKey: MenuBarModel.alcoveSpringKey) ?? ""
    ) ?? .smooth
    /// Master toggle for every haptic the alcove fires. Default OFF
    /// — macOS trackpad haptics are surprisingly insistent against
    /// the alcove's silent visual choreography. Opt-in for users
    /// who want the extra feedback. Read by `HapticGate.enabled` at
    /// every haptic call site.
    var hapticsEnabled: Bool = UserDefaults.standard.bool(
        forKey: MenuBarModel.hapticsEnabledKey)
    /// Manual width override for the notch silhouette. Nil = auto-detect
    /// via NSScreen.notchFrame. Used by the calibration UI in the dev
    /// panel for users where auto-detect is wrong (or who want to nudge
    /// the silhouette a few pixels for visual fit).
    var notchWidthOverride: Double? = MenuBarModel.loadOptionalDouble(forKey: MenuBarModel.notchWidthOverrideKey)
    var notchHeightOverride: Double? = MenuBarModel.loadOptionalDouble(forKey: MenuBarModel.notchHeightOverrideKey)
    /// Optional Claude session ID the user has pinned via the alcove
    /// picker. When set, the watcher reads that specific jsonl
    /// instead of the most-recently-touched one. Persisted across
    /// launches so the pin survives restarts.
    var pinnedClaudeSessionId: String? = UserDefaults.standard.string(
        forKey: MenuBarModel.pinnedClaudeSessionIdKey)
    /// Same interaction model as Claude, but for Codex rollout jsonl
    /// files. Codex exposes conversation metadata through
    /// `~/.codex/state_5.sqlite`, so the notch can lock onto a named
    /// Codex thread instead of always following the newest rollout.
    var pinnedCodexSessionId: String? = UserDefaults.standard.string(
        forKey: MenuBarModel.pinnedCodexSessionIdKey)
    /// Transient — set while the user hovers a session pill so the
    /// alcove previews that session's context without committing to
    /// a pin. Takes priority over `pinnedClaudeSessionId` when set;
    /// clears when hover exits. Not persisted.
    var previewClaudeSessionId: String? = nil
    var previewCodexSessionId: String? = nil
    /// Transient: true while the user is actively dragging the calibration
    /// handles on the notch silhouette. Not persisted. The presenter uses
    /// this to skip its expensive panel-rebuild path during drag ticks.
    var notchCalibrating: Bool = false

    /// Fires after every refresh tick (success or failure) so the
    /// non-SwiftUI status bar label can re-render. SwiftUI views in the
    /// popover observe `@Observable` directly and don't need this hook.
    var onSnapshotChanged: (@MainActor () -> Void)?

    static let activeTabKey = "burnrate.activeTab"
    static let menuBarModuleKey = "burnrate.menuBarModule"
    static let menuBarDisplayModeKey = "burnrate.menuBarDisplayMode"
    static let menuBarIconStyleKey = "burnrate.menuBarIconStyle"
    static let notchEnabledKey = "burnrate.notchEnabled"
    static let alcoveChoreographyKey = "burnrate.alcoveChoreography"
    static let alcoveSpringKey = "burnrate.alcoveSpring"
    static let hapticsEnabledKey = HapticGate.key
    static let notchWidthOverrideKey = "burnrate.notchWidthOverride"
    static let notchHeightOverrideKey = "burnrate.notchHeightOverride"
    static let pinnedClaudeSessionIdKey = "burnrate.pinnedClaudeSessionId"
    static let pinnedCodexSessionIdKey = "burnrate.pinnedCodexSessionId"

    private static func loadOptionalDouble(forKey key: String) -> Double? {
        UserDefaults.standard.object(forKey: key) as? Double
    }

    private static func loadNotchEnabledDefault() -> Bool {
        if let raw = UserDefaults.standard.object(forKey: MenuBarModel.notchEnabledKey) as? Bool {
            return raw
        }
        // Phase 1 default: off until user opts in. Even on notched
        // hardware we don't want to surprise users with a new always-on
        // surface on first launch after upgrade.
        return false
    }

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

    /// Per-conversation turn-delta patterns. Each pinned/active
    /// session accumulates its own rolling history, so bucket sizes
    /// + trend reflect *that conversation's* rhythm rather than a
    /// global "you-as-a-user" average. Keyed by `sessionId`.
    var turnPatternsBySession: [String: TurnPattern] = [:]

    /// Provider-wide aggregate, used as a cold-start fallback when a
    /// session hasn't accumulated enough samples yet (< 3). Built
    /// from the union of every observed turn for that provider.
    var turnPatternsByProvider: [ProviderKind: TurnPattern] = [:]

    /// Resolves the right turn-pattern for a given session. Prefers
    /// session-scoped data once the conversation has accumulated at
    /// least 3 turns (enough to be meaningful); otherwise falls back
    /// to the provider-wide aggregate so brand-new sessions still
    /// get a usable forecast immediately.
    func turnPattern(
        forSessionId sessionId: String?,
        provider: ProviderKind) -> TurnPattern
    {
        if let sid = sessionId,
           let session = self.turnPatternsBySession[sid],
           session.samples.count >= 3
        {
            return session
        }
        return self.turnPatternsByProvider[provider] ?? .empty
    }

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
        /// Signed fair-pace delta. Positive means you're ahead of the
        /// even-use line; negative means you have reserve.
        let paceDeltaPercent: Double

        /// Model A — gap between current usage and even-pacing expectation
        /// at this point in the window. A snapshot, not a prediction.
        let aheadOfPacePercent: Double
        let fairPaceReservePercent: Double

        /// Model B — projected usage at reset assuming the recent burn
        /// rate (last ~hour of samples) continues. Nil when we don't have
        /// enough history yet.
        let projectedAtResetPercent: Double?
        let projectedReservePercent: Double?

        /// When current usage is projected to hit 100%, if the projection
        /// puts us over budget. Nil otherwise.
        let runsOutAt: Date?

        var projectedOverPercent: Int? {
            guard let projectedAtResetPercent,
                  projectedAtResetPercent > 100
            else { return nil }
            return max(1, Int((projectedAtResetPercent - 100).rounded()))
        }
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
    private let identityFileWatcher = LocalFileChangeWatcher()
    private let previewContextWatcher = LocalFileChangeWatcher()
    private var hasStarted = false
    private var refreshTask: Task<Void, Never>?
    private var previewRefreshTask: Task<Void, Never>?
    private var previewContextRefreshTask: Task<Void, Never>?
    private var watchedIdentityRefreshTask: Task<Void, Never>?
    private var fireExpiryTask: Task<Void, Never>?
    private var queuedRefreshAfterCurrent = false
    private var queuedRefreshNeedsFull = false
    private var queuedRefreshProvider: ProviderKind?
    /// Per-session prev-state trackers — keyed by sessionId, not
    /// provider, so switching between concurrent sessions doesn't
    /// produce nonsense diffs (session A at 50K → session B at 20K
    /// would otherwise look like a -30K delta).
    private var prevUserMessageCount: [String: Int] = [:]
    private var prevContextUsedTokens: [String: Int] = [:]
    /// Per-session rolling deltas — drives the session-scoped
    /// pattern. The provider-wide pattern is built from the union
    /// of these.
    private var turnDeltaHistoryBySession: [String: [Int]] = [:]
    private var turnDeltaHistoryByProvider: [ProviderKind: [Int]] = [:]
    private static let maxTurnHistory = 8

    /// Cap on per-window history. At a 30-second refresh cadence, 120
    /// samples = the last 60 minutes — long enough to compute a stable
    /// recent burn rate, short enough that the projection follows
    /// behavioural shifts within an hour.
    private static let maxWindowHistory = 120
    private static let watchReconcileInterval: Duration = .seconds(30)
    private static let backgroundFullRefreshInterval: TimeInterval = 300
    private static let watchedIdentityRefreshDebounce: Duration = .milliseconds(900)
    private static let watchedIdentityMinimumSpacing: TimeInterval = 12
    private static let previewContextRefreshDebounce: Duration = .milliseconds(350)
    private static let previewContextMinimumSpacing: TimeInterval = 1.5

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
        self.onSnapshotChanged?()
    }

    func setMenuBarDisplayMode(_ mode: MenuBarDisplayMode) {
        self.menuBarDisplayMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.menuBarDisplayModeKey)
        self.onSnapshotChanged?()
    }

    func setMenuBarIconStyle(_ style: MenuBarIconStyle) {
        self.menuBarIconStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: Self.menuBarIconStyleKey)
        self.onSnapshotChanged?()
    }

    func setNotchEnabled(_ enabled: Bool) {
        self.notchEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.notchEnabledKey)
        // Trigger downstream re-rendering so the NotchPresenter activates
        // or deactivates immediately. Reuses the existing snapshot hook —
        // semantics are "something visible changed, re-render."
        self.onSnapshotChanged?()
    }

    func setAlcoveChoreography(_ choreography: AlcoveChoreography) {
        self.alcoveChoreography = choreography
        UserDefaults.standard.set(choreography.rawValue, forKey: Self.alcoveChoreographyKey)
        self.onSnapshotChanged?()
    }

    func setHapticsEnabled(_ value: Bool) {
        self.hapticsEnabled = value
        UserDefaults.standard.set(value, forKey: Self.hapticsEnabledKey)
        self.onSnapshotChanged?()
    }

    func setAlcoveSpring(_ spring: AlcoveSpring) {
        self.alcoveSpring = spring
        UserDefaults.standard.set(spring.rawValue, forKey: Self.alcoveSpringKey)
        self.onSnapshotChanged?()
    }

    func setNotchWidthOverride(_ value: Double?) {
        self.notchWidthOverride = value
        if let value {
            UserDefaults.standard.set(value, forKey: Self.notchWidthOverrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.notchWidthOverrideKey)
        }
        self.onSnapshotChanged?()
    }

    func setPinnedClaudeSessionId(_ value: String?) {
        self.setPinnedSessionId(value, provider: .claude)
    }

    func setPinnedSessionId(_ value: String?, provider: ProviderKind) {
        switch provider {
        case .claude:
            self.pinnedClaudeSessionId = value
            if let value {
                UserDefaults.standard.set(value, forKey: Self.pinnedClaudeSessionIdKey)
                self.pinnedCodexSessionId = nil
                UserDefaults.standard.removeObject(forKey: Self.pinnedCodexSessionIdKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.pinnedClaudeSessionIdKey)
            }
        case .codex:
            self.pinnedCodexSessionId = value
            if let value {
                UserDefaults.standard.set(value, forKey: Self.pinnedCodexSessionIdKey)
                self.pinnedClaudeSessionId = nil
                UserDefaults.standard.removeObject(forKey: Self.pinnedClaudeSessionIdKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.pinnedCodexSessionIdKey)
            }
        }
        self.selectedProvider = provider
        // Force-refresh — bypasses the isRefreshing guard so the
        // alcove updates instantly even if a poll happens to be in
        // flight when the user clicks.
        Task { @MainActor in await self.refreshFocusedPreview(provider: provider) }
    }

    /// Set/clear the hover-preview session. Takes priority over the
    /// pinned session in the watcher path; clearing falls back to pin
    /// (or auto-detect when no pin set). Triggers a force-refresh so
    /// the alcove fetches that session's data immediately.
    func setPreviewClaudeSessionId(_ value: String?) {
        self.setPreviewSessionId(value, provider: .claude)
    }

    func setPreviewSessionId(_ value: String?, provider: ProviderKind) {
        // Avoid spamming refreshes when hover events fire repeatedly
        // for the same target.
        switch provider {
        case .claude:
            guard self.previewClaudeSessionId != value else { return }
            self.previewClaudeSessionId = value
            if value != nil {
                self.previewCodexSessionId = nil
            }
        case .codex:
            guard self.previewCodexSessionId != value else { return }
            self.previewCodexSessionId = value
            if value != nil {
                self.previewClaudeSessionId = nil
            }
        }
        if value != nil {
            self.selectedProvider = provider
        }
        self.updatePreviewContextWatchTarget(provider: provider, sessionId: value)
        // Cancel the previous preview fetch so rapid hover scrubbing
        // doesn't queue up stale results that would flicker through
        // the UI as each one completes. The refresh body itself also
        // guards on target-match before writing — belt + suspenders.
        self.previewRefreshTask?.cancel()
        self.previewRefreshTask = Task { @MainActor [weak self] in
            if Task.isCancelled { return }
            await self?.refreshFocusedPreview(provider: provider)
        }
    }

    func setNotchHeightOverride(_ value: Double?) {
        self.notchHeightOverride = value
        if let value {
            UserDefaults.standard.set(value, forKey: Self.notchHeightOverrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.notchHeightOverrideKey)
        }
        self.onSnapshotChanged?()
    }

    func resetNotchSizeOverrides() {
        self.notchWidthOverride = nil
        self.notchHeightOverride = nil
        UserDefaults.standard.removeObject(forKey: Self.notchWidthOverrideKey)
        UserDefaults.standard.removeObject(forKey: Self.notchHeightOverrideKey)
        self.onSnapshotChanged?()
    }

    func setNotchCalibrating(_ value: Bool) {
        self.notchCalibrating = value
        self.onSnapshotChanged?()
    }

    /// Live writes during a calibration drag. Updates the in-memory
    /// override values so SwiftUI re-renders the notch silhouette at the
    /// new size, but skips persisting + the snapshot hook so the
    /// NotchPresenter doesn't tear the NSPanel down on every drag tick.
    /// Persistence happens once on commit.
    func setNotchSizeLive(width: Double, height: Double) {
        self.notchWidthOverride = width
        self.notchHeightOverride = height
    }

    func commitNotchCalibration() {
        if let w = self.notchWidthOverride {
            UserDefaults.standard.set(w, forKey: Self.notchWidthOverrideKey)
        }
        if let h = self.notchHeightOverride {
            UserDefaults.standard.set(h, forKey: Self.notchHeightOverrideKey)
        }
        self.notchCalibrating = false
        self.onSnapshotChanged?()
    }

    private func firstDepletedWindow() -> UsageWindow? {
        for snap in self.overview.snapshots {
            if let depleted = snap.windows.first(where: { $0.usedPercent >= 99 && $0.resetsAt != nil }) {
                return depleted
            }
        }
        return nil
    }

    /// Compute the display pair for any module, regardless of which is
    /// currently selected. Used by the alcove dashboard to render a
    /// multi-row mini-summary, and by the menu-bar item to resolve the
    /// user's pick.
    func value(for module: MenuBarModule) -> MenuBarDisplay? {
        guard let snap = self.selectedSnapshot else { return nil }
        switch module {
        case .context:
            guard let context = snap.workContext else { return nil }
            return MenuBarDisplay(label: module.label, value: "\(Int(context.contextUsedPercent.rounded()))%")
        case .turnsLeft:
            guard let context = snap.workContext, context.contextRemainingTokens > 0 else { return nil }
            let pattern = self.turnPattern(forSessionId: context.sessionId, provider: snap.kind)
            guard pattern.avg > 0 else { return nil }
            let turns = max(0, context.contextRemainingTokens / pattern.avg)
            return MenuBarDisplay(label: module.label, value: "\(turns)")
        case .fiveHour:
            guard let window = snap.windows.first(where: Self.is5hWindow) else { return nil }
            return Self.capDisplay(for: module, window: window)
        case .weekly:
            guard let window = snap.windows.first(where: Self.is7dWindow) else { return nil }
            return Self.capDisplay(for: module, window: window)
        case .codexSurface:
            guard let surface = snap.codexSurface else { return nil }
            return MenuBarDisplay(
                label: module.label,
                value: "\(surface.readySourceCount)/\(surface.sources.count)")
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

    private static func capDisplay(for module: MenuBarModule, window: UsageWindow) -> MenuBarDisplay {
        let used = Int(window.usedPercent.rounded())
        let left = Int(window.remainingPercent.rounded())
        let reset = DisplayText.reset(window.resetsAt) ?? "reset unknown"
        return MenuBarDisplay(
            label: module.label,
            value: "\(used)%",
            detail: "\(used)% used, \(left)% left, \(reset)")
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
        self.updateIdentityWatchTargets(for: self.overview)
        // The popover observes @Observable directly so it re-renders for
        // free, but the notch's NotchDisplayState only refreshes from
        // the snapshot hook — fire it so the alcove flips providers too.
        self.onSnapshotChanged?()
    }

    func start() {
        guard !self.hasStarted else { return }
        self.hasStarted = true
        self.loadOverageHistory()
        self.refreshTask = Task {
            await self.notificationController.prepare()
            await self.refreshFastInitialOverview()
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled, !self.isPreviewingSession {
                await self.refresh(force: true)
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.watchReconcileInterval)
                guard !self.isPreviewingSession else { continue }

                // Keep the lightweight identity watchers attached to
                // the latest known sessions every 30s. The expensive
                // analytics pass runs much less often as a safety net.
                self.updateIdentityWatchTargets(for: self.overview)
                let shouldRunFullRefresh = self.lastRefreshAt
                    .map { Date().timeIntervalSince($0) >= Self.backgroundFullRefreshInterval }
                    ?? true
                if shouldRunFullRefresh {
                    await self.refresh()
                }
            }
        }
    }

    private var isPreviewingSession: Bool {
        self.previewClaudeSessionId != nil || self.previewCodexSessionId != nil
    }

    func refresh(force: Bool = false, focusedProvider: ProviderKind? = nil) async {
        // Never overlap full snapshot loads. Preview/pin actions can
        // arrive while a refresh is already in flight; queue exactly
        // one follow-up instead of spawning competing URL/file scans.
        if self.isRefreshing {
            if force {
                self.queuedRefreshAfterCurrent = true
                if focusedProvider == nil {
                    self.queuedRefreshNeedsFull = true
                    self.queuedRefreshProvider = nil
                } else if !self.queuedRefreshNeedsFull {
                    self.queuedRefreshProvider = focusedProvider
                }
            }
            return
        }
        self.isRefreshing = true
        defer {
            self.isRefreshing = false
            if self.queuedRefreshAfterCurrent {
                let queuedProvider = self.queuedRefreshNeedsFull ? nil : self.queuedRefreshProvider
                self.queuedRefreshAfterCurrent = false
                self.queuedRefreshNeedsFull = false
                self.queuedRefreshProvider = nil
                Task { @MainActor in await self.refresh(force: true, focusedProvider: queuedProvider) }
            }
        }

        do {
            let recentRate = self.recentDailySpendRate(now: Date())
            // Preview wins over pin — hover lets you scrub through
            // sessions without committing. Click then commits.
            let targetClaudeSession = self.previewClaudeSessionId
                ?? self.pinnedClaudeSessionId
            let targetCodexSession = self.previewCodexSessionId
                ?? self.pinnedCodexSessionId
            let overview = try await self.source.loadOverview(
                recentDailySpend: recentRate,
                pinnedClaudeSessionId: targetClaudeSession,
                pinnedCodexSessionId: targetCodexSession,
                focusedProvider: focusedProvider,
                existingOverview: self.overview)
            // Latest-wins: if hover moved while we were fetching,
            // discard this result. A newer preview task already
            // fired with the right target — letting this stale
            // snapshot through would flicker the UI through old
            // sessions as the queue drains.
            let currentTarget = self.previewClaudeSessionId
                ?? self.pinnedClaudeSessionId
            let currentCodexTarget = self.previewCodexSessionId
                ?? self.pinnedCodexSessionId
            guard targetClaudeSession == currentTarget,
                  targetCodexSession == currentCodexTarget
            else { return }
            await self.applyOverview(
                overview,
                recordSamples: true,
                evaluateNotifications: true,
                markFullRefresh: true)
        } catch {
            self.lastError = UsageError.from(error)
            self.onSnapshotChanged?()
        }
    }

    private func refreshFastInitialOverview() async {
        let overview = await self.source.loadFastOverview(
            pinnedClaudeSessionId: self.pinnedClaudeSessionId,
            pinnedCodexSessionId: self.pinnedCodexSessionId)
        await self.applyOverview(
            overview,
            recordSamples: false,
            evaluateNotifications: false,
            markFullRefresh: false)
    }

    private func refreshFocusedPreview(provider: ProviderKind) async {
        let targetClaudeSession = self.previewClaudeSessionId
            ?? self.pinnedClaudeSessionId
        let targetCodexSession = self.previewCodexSessionId
            ?? self.pinnedCodexSessionId
        let baseOverview = self.overview
        // Use a throwaway source so hover/peek is never queued behind
        // the long-lived source's full analytics actor work.
        let source = UsageSnapshotSource()

        do {
            let overview: UsageOverview
            if baseOverview.snapshots.isEmpty {
                overview = await source.loadFastOverview(
                    pinnedClaudeSessionId: targetClaudeSession,
                    pinnedCodexSessionId: targetCodexSession)
            } else {
                overview = try await source.loadOverview(
                    pinnedClaudeSessionId: targetClaudeSession,
                    pinnedCodexSessionId: targetCodexSession,
                    focusedProvider: provider,
                    existingOverview: baseOverview)
            }

            let currentClaudeTarget = self.previewClaudeSessionId
                ?? self.pinnedClaudeSessionId
            let currentCodexTarget = self.previewCodexSessionId
                ?? self.pinnedCodexSessionId
            guard targetClaudeSession == currentClaudeTarget,
                  targetCodexSession == currentCodexTarget
            else { return }

            await self.applyOverview(
                overview,
                recordSamples: false,
                evaluateNotifications: false,
                markFullRefresh: false)
        } catch {
            self.lastError = UsageError.from(error)
            self.onSnapshotChanged?()
        }
    }

    private func applyOverview(
        _ overview: UsageOverview,
        recordSamples: Bool,
        evaluateNotifications: Bool,
        markFullRefresh: Bool) async
    {
        self.detectFireEvents(in: overview)
        let now = Date()
        self.recordWindowSamples(from: overview, now: now)
        if recordSamples {
            self.recordOverageSamples(from: overview, now: now)
        }
        self.overview = overview
        if evaluateNotifications {
            await self.notificationController.evaluate(overview)
        }
        if overview.snapshot(for: self.selectedProvider) == nil,
           let first = overview.snapshots.first
        {
            self.selectedProvider = first.kind
        }
        self.lastError = nil
        if markFullRefresh {
            self.lastRefreshAt = Date()
        } else {
            self.lastPreviewRefreshAt = Date()
        }
        self.updateIdentityWatchTargets(for: overview)
        self.onSnapshotChanged?()
    }

    private func updateIdentityWatchTargets(for overview: UsageOverview) {
        let urls = Self.identityWatchURLs(
            for: overview,
            selectedProvider: self.selectedProvider,
            pinnedClaudeSessionId: self.pinnedClaudeSessionId,
            previewClaudeSessionId: self.previewClaudeSessionId)
        let provider = self.selectedProvider
        self.identityFileWatcher.update(urls: urls) { [weak self] in
            Task { @MainActor in
                self?.scheduleWatchedIdentityRefresh(provider: provider)
            }
        }
    }

    private func updatePreviewContextWatchTarget(provider: ProviderKind, sessionId: String?) {
        guard let sessionId else {
            switch provider {
            case .codex:
                if self.previewCodexSessionId == nil {
                    self.previewContextWatcher.cancelAll()
                    self.previewContextRefreshTask?.cancel()
                    self.previewContextRefreshTask = nil
                }
            case .claude:
                if self.previewClaudeSessionId == nil {
                    self.previewContextWatcher.cancelAll()
                    self.previewContextRefreshTask?.cancel()
                    self.previewContextRefreshTask = nil
                }
            }
            return
        }

        let urls = Self.previewContextWatchURLs(provider: provider, sessionId: sessionId)
        guard !urls.isEmpty else { return }
        self.previewContextWatcher.update(urls: urls) { [weak self] in
            Task { @MainActor in
                self?.schedulePreviewContextRefresh(provider: provider, sessionId: sessionId)
            }
        }
    }

    private func schedulePreviewContextRefresh(provider: ProviderKind, sessionId: String) {
        switch provider {
        case .codex:
            guard self.previewCodexSessionId == sessionId else { return }
        case .claude:
            guard self.previewClaudeSessionId == sessionId else { return }
        }

        self.previewContextRefreshTask?.cancel()
        self.previewContextRefreshTask = Task { @MainActor [weak self] in
            let lastRefreshAt = self?.lastPreviewRefreshAt ?? .distantPast
            let remainingSpacing = Self.previewContextMinimumSpacing
                - Date().timeIntervalSince(lastRefreshAt)
            let spacingDelay = max(0, remainingSpacing)
            if spacingDelay > 0 {
                try? await Task.sleep(for: .milliseconds(Int(spacingDelay * 1_000)))
            }
            try? await Task.sleep(for: Self.previewContextRefreshDebounce)
            if Task.isCancelled { return }
            switch provider {
            case .codex:
                guard self?.previewCodexSessionId == sessionId else { return }
            case .claude:
                guard self?.previewClaudeSessionId == sessionId else { return }
            }
            await self?.refreshFocusedPreview(provider: provider)
        }
    }

    private func scheduleWatchedIdentityRefresh(provider: ProviderKind) {
        // File-system events can arrive in short bursts while Claude
        // rewrites session metadata or Codex commits a title update.
        // Coalesce them and then do the normal full refresh exactly once.
        guard provider == self.selectedProvider else { return }
        guard !self.isPreviewingSession else { return }
        self.watchedIdentityRefreshTask?.cancel()
        self.watchedIdentityRefreshTask = Task { @MainActor [weak self] in
            let lastRefreshAt = self?.lastRefreshAt ?? .distantPast
            let remainingSpacing = Self.watchedIdentityMinimumSpacing
                - Date().timeIntervalSince(lastRefreshAt)
            let spacingDelay = max(0, remainingSpacing)
            if spacingDelay > 0 {
                try? await Task.sleep(for: .milliseconds(Int(spacingDelay * 1_000)))
            }
            try? await Task.sleep(for: Self.watchedIdentityRefreshDebounce)
            if Task.isCancelled { return }
            await self?.refresh(force: true, focusedProvider: provider)
        }
    }

    private static func identityWatchURLs(
        for overview: UsageOverview,
        selectedProvider: ProviderKind,
        pinnedClaudeSessionId: String?,
        previewClaudeSessionId: String?) -> Set<URL>
    {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        var urls: Set<URL> = []

        switch selectedProvider {
        case .codex:
            let codexDB = home.appendingPathComponent(".codex/state_5.sqlite")
            if fileManager.fileExists(atPath: codexDB.path) {
                urls.insert(codexDB)
            }

            let sessionsRoot = home.appendingPathComponent(".codex/sessions")
            urls.formUnion(Self.recentJSONLParentURLs(
                root: sessionsRoot,
                limit: 6,
                thresholdSeconds: 1_800))
        case .claude:
            let claudeRoot = Self.claudeRoot()
            let sessionsDir = claudeRoot.appendingPathComponent("sessions")
            if fileManager.fileExists(atPath: sessionsDir.path) {
                urls.insert(sessionsDir)
            }

            var claudeSessionIds: Set<String> = []
            if let pinnedClaudeSessionId { claudeSessionIds.insert(pinnedClaudeSessionId) }
            if let previewClaudeSessionId { claudeSessionIds.insert(previewClaudeSessionId) }
            if let claudeSnapshot = overview.snapshot(for: .claude) {
                if let id = claudeSnapshot.workContext?.sessionId { claudeSessionIds.insert(id) }
                if let id = claudeSnapshot.claudeSession?.sessionId { claudeSessionIds.insert(id) }
                for session in claudeSnapshot.liveSessions {
                    claudeSessionIds.insert(session.sessionId)
                }
            }
            urls.formUnion(Self.claudeSessionMetadataURLs(
                sessionIds: claudeSessionIds,
                root: claudeRoot))
            urls.formUnion(Self.recentJSONLParentURLs(
                root: claudeRoot.appendingPathComponent("projects"),
                limit: 6,
                thresholdSeconds: 600))
        }

        return urls
    }

    private static func recentJSONLParentURLs(
        root: URL,
        limit: Int,
        thresholdSeconds: TimeInterval) -> Set<URL>
    {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])
        else { return [] }

        let cutoff = Date().addingTimeInterval(-thresholdSeconds)
        var candidates: [(url: URL, modified: Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            guard modified >= cutoff else { continue }
            candidates.append((url, modified))
        }
        return Set(candidates
            .sorted { $0.modified > $1.modified }
            .prefix(limit)
            .map { $0.url.deletingLastPathComponent() })
    }

    private static func previewContextWatchURLs(provider: ProviderKind, sessionId: String) -> Set<URL> {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        var urls: Set<URL> = []

        switch provider {
        case .codex:
            let codexDB = home.appendingPathComponent(".codex/state_5.sqlite")
            if fileManager.fileExists(atPath: codexDB.path) {
                urls.insert(codexDB)
            }
            urls.formUnion(Self.matchingJSONLURLs(
                sessionId: sessionId,
                root: home.appendingPathComponent(".codex/sessions"),
                allowRolloutSuffix: true))
        case .claude:
            let claudeRoot = Self.claudeRoot()
            urls.formUnion(Self.claudeSessionMetadataURLs(
                sessionIds: [sessionId],
                root: claudeRoot))
            urls.formUnion(Self.matchingJSONLURLs(
                sessionId: sessionId,
                root: claudeRoot.appendingPathComponent("projects"),
                allowRolloutSuffix: false))
        }

        return urls
    }

    private static func matchingJSONLURLs(
        sessionId: String,
        root: URL,
        allowRolloutSuffix: Bool) -> Set<URL>
    {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])
        else { return [] }

        var result: Set<URL> = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let basename = url.deletingPathExtension().lastPathComponent
            if basename == sessionId || (allowRolloutSuffix && Self.rolloutSessionId(from: url) == sessionId) {
                result.insert(url)
            }
        }
        return result
    }

    private static func rolloutSessionId(from url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
        guard name.count >= 36 else { return nil }
        let suffix = String(name.suffix(36))
        let pattern = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#
        guard suffix.range(of: pattern, options: .regularExpression) != nil else {
            return nil
        }
        return suffix
    }

    private static func claudeSessionMetadataURLs(sessionIds: Set<String>, root: URL) -> Set<URL> {
        guard !sessionIds.isEmpty else { return [] }
        let sessionsDir = root.appendingPathComponent("sessions")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])
        else { return [] }

        var result: Set<URL> = []
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessionId = json["sessionId"] as? String,
                  sessionIds.contains(sessionId)
            else { continue }
            result.insert(url)
        }
        return result
    }

    private static func claudeRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }

    /// Detect per-turn token deltas, feed the rolling-window pattern, and
    /// fire "playing with fire" moments when conditions align.
    private func detectFireEvents(in newOverview: UsageOverview) {
        for snap in newOverview.snapshots {
            guard let context = snap.workContext else { continue }

            // `WorkContextSnapshot.sessionId` is the active session
            // whose context we're observing this poll (preview > pin
            // > auto-detected on Claude; Codex's single live thread).
            // Single source of truth across providers.
            guard let sid = context.sessionId else { continue }

            // Bootstrap session-scoped pattern from the
            // averageGrowthTokens estimate so the bucket forecast
            // appears immediately for new conversations instead of
            // needing 3+ observed deltas. The provider-wide pattern
            // (cold-start fallback) gets the same bootstrap.
            if (self.turnPatternsBySession[sid]?.samples.isEmpty ?? true),
               let bootstrap = context.averageGrowthTokens, bootstrap > 0
            {
                let seed = TurnPattern(
                    samples: [bootstrap],
                    avg: bootstrap,
                    p90: bootstrap,
                    trend: .flat)
                self.turnPatternsBySession[sid] = seed
                if self.turnPatternsByProvider[snap.kind]?.samples.isEmpty ?? true {
                    self.turnPatternsByProvider[snap.kind] = seed
                }
            }

            let newCount = context.userMessageCount
            let newUsed = context.contextUsedTokens
            defer {
                self.prevUserMessageCount[sid] = newCount
                self.prevContextUsedTokens[sid] = newUsed
            }
            guard let prevCount = self.prevUserMessageCount[sid],
                  let prevUsed = self.prevContextUsedTokens[sid],
                  newCount > prevCount
            else { continue }
            let turnDelta = max(0, newUsed - prevUsed)

            // Record this turn — writes both session-scoped and
            // provider-wide rolling histories.
            self.recordTurn(sessionId: sid, provider: snap.kind, delta: turnDelta)

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

    private func recordTurn(sessionId: String, provider: ProviderKind, delta: Int) {
        // Skip near-zero deltas (likely from compaction or session restarts) —
        // they pollute the average without representing real user activity.
        guard delta >= 500 else { return }

        // Session-scoped history — the primary source for buckets +
        // trend when the conversation has enough samples.
        var sessionHistory = self.turnDeltaHistoryBySession[sessionId] ?? []
        sessionHistory.append(delta)
        if sessionHistory.count > Self.maxTurnHistory {
            sessionHistory.removeFirst(sessionHistory.count - Self.maxTurnHistory)
        }
        self.turnDeltaHistoryBySession[sessionId] = sessionHistory
        self.turnPatternsBySession[sessionId] = Self.computePattern(samples: sessionHistory)

        // Provider-wide history — cold-start fallback for sessions
        // that haven't reached 3 samples yet. Built from the same
        // turn deltas so it's an honest summary of the user's
        // recent pace across all conversations.
        var providerHistory = self.turnDeltaHistoryByProvider[provider] ?? []
        providerHistory.append(delta)
        if providerHistory.count > Self.maxTurnHistory {
            providerHistory.removeFirst(providerHistory.count - Self.maxTurnHistory)
        }
        self.turnDeltaHistoryByProvider[provider] = providerHistory
        self.turnPatternsByProvider[provider] = Self.computePattern(samples: providerHistory)
    }

    /// Builds avg / p90 / trend stats from a turn-delta sample
    /// list. Extracted from `recordTurn` so the same logic is shared
    /// between session-scoped and provider-wide pattern updates.
    private static func computePattern(samples: [Int]) -> TurnPattern {
        guard !samples.isEmpty else { return .empty }
        let avg = samples.reduce(0, +) / samples.count
        let p90: Int = {
            if samples.count <= 4 { return samples.max() ?? 0 }
            let sorted = samples.sorted()
            let idx = Int(Double(sorted.count - 1) * 0.9)
            return sorted[idx]
        }()
        let trend: TurnPattern.Trend = {
            // Need ≥6 samples (3 vs 3) before we'll claim a trend.
            // Median-of-half is robust to a single outlier in either
            // half, which a 4-sample mean comparison wouldn't be.
            guard samples.count >= 6 else { return .flat }
            let half = samples.count / 2
            let older = Self.median(of: Array(samples.prefix(half)))
            let recent = Self.median(of: Array(samples.suffix(half)))
            guard older > 0 else { return .flat }
            if Double(recent) >= Double(older) * 1.4 { return .up }
            if Double(recent) <= Double(older) * 0.7 { return .down }
            return .flat
        }()
        return TurnPattern(samples: samples, avg: avg, p90: p90, trend: trend)
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

        // Don't surface anything for sub-2% fair-pace drift unless
        // we have a meaningful recent-rate projection.
        if abs(aheadOfPace) < 2,
           projected == nil
        {
            return nil
        }

        return WindowForecast(
            paceDeltaPercent: aheadOfPace,
            aheadOfPacePercent: max(0, aheadOfPace),
            fairPaceReservePercent: max(0, -aheadOfPace),
            projectedAtResetPercent: projected,
            projectedReservePercent: projected.map { max(0, 100 - $0) },
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
