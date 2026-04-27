import BurnrateCore
import Foundation
import UserNotifications

final class UsageNotificationController {
    static let alertModeKey = "burnrate.notification.mode"

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let prefix = "burnrate.notification"

    /// Per-window memory used to detect window rolls. We need to know
    /// "the previous time we saw this window" + "what level it was" so
    /// that when the next refresh shows a fresh `resetsAt`, we can fire
    /// a reset celebration if the prior state was depleted. In-memory
    /// only — the cost of losing this on app restart is just one missed
    /// celebration, which is fine.
    private struct WindowMemory {
        let resetsAt: Date?
        let lastLevel: ThresholdLevel?
    }
    private var windowMemory: [String: WindowMemory] = [:]

    func prepare() async {
        do {
            _ = try await self.center.requestAuthorization(options: [.alert, .sound])
        } catch {
            // Notification permission failures should never block usage refresh.
        }
    }

    func evaluate(_ overview: UsageOverview) async {
        for snapshot in overview.snapshots {
            await self.evaluate(snapshot)
        }
    }

    private func evaluate(_ snapshot: ProviderUsageSnapshot) async {
        if let context = snapshot.workContext {
            await self.evaluateContext(context, kind: snapshot.kind)
        }

        if let primary = snapshot.primaryWindow {
            await self.evaluateWindow(primary, metric: .session, kind: snapshot.kind)
        }

        if let weekly = snapshot.windows.first(where: { $0.title.localizedCaseInsensitiveContains("weekly") }) {
            await self.evaluateWindow(weekly, metric: .weekly, kind: snapshot.kind)
        }
    }

    private func evaluateContext(_ context: WorkContextSnapshot, kind: ProviderKind) async {
        let percent = context.contextUsedPercent
        let level = ThresholdLevel.context(percent)
        let body = level.map { self.contextBody(context: context, level: $0) } ?? ""
        await self.emitIfNeeded(
            kind: kind,
            metric: .context,
            level: level,
            percent: percent,
            resetIdentity: nil,
            title: "\(Self.providerLabel(kind)) context is \(Int(percent.rounded()))% full",
            body: body)
    }

    private func evaluateWindow(_ window: UsageWindow, metric: NotificationMetric, kind: ProviderKind) async {
        let memoryKey = "\(kind.rawValue).\(metric.rawValue)"
        let previous = self.windowMemory[memoryKey]

        // Window-roll detection: if we last saw this window depleted and
        // its `resetsAt` has now jumped meaningfully forward, the window
        // has rolled — fire a reset celebration. The 30-min threshold
        // is well below either window length (5h / 7d) and well above
        // typical clock jitter, so it can't false-positive on noise.
        if let prev = previous,
           prev.lastLevel == .depleted,
           let prevReset = prev.resetsAt,
           let currentReset = window.resetsAt,
           currentReset.timeIntervalSince(prevReset) > 30 * 60
        {
            await self.emitReset(kind: kind, metric: metric, window: window)
        }

        let level = ThresholdLevel.window(window.usedPercent, metric: metric)
        self.windowMemory[memoryKey] = WindowMemory(resetsAt: window.resetsAt, lastLevel: level)

        let body = level.map { self.windowBody(window: window, metric: metric, level: $0) } ?? ""
        let title: String
        if level == .depleted {
            title = "\(Self.providerLabel(kind)) \(metric.titleSuffix) depleted"
        } else {
            title = "\(Self.providerLabel(kind)) \(metric.titleSuffix) is \(Int(window.usedPercent.rounded()))% used"
        }
        await self.emitIfNeeded(
            kind: kind,
            metric: metric,
            level: level,
            percent: window.usedPercent,
            resetIdentity: window.resetsAt,
            title: title,
            body: body)
    }

    private func emitIfNeeded(
        kind: ProviderKind,
        metric: NotificationMetric,
        level: ThresholdLevel?,
        percent: Double,
        resetIdentity: Date?,
        title: String,
        body: String) async
    {
        // Provider-scoped key so a Codex notification can't suppress a
        // Claude one for the same metric. Codex retains its existing
        // ".codex.<metric>" shape (rawValue is "codex"), so users with
        // prior dedup state don't re-receive notifications.
        let key = "\(self.prefix).\(kind.rawValue).\(metric.rawValue)"
        guard let level else {
            self.defaults.removeObject(forKey: key)
            return
        }

        let mode = UsageAlertMode(rawValue: self.defaults.string(forKey: Self.alertModeKey) ?? "") ?? .all
        // Depleted is treated as critical for alert-mode gating so users
        // on "critical only" still hear about hard rate-limits.
        let isCriticalLike = level >= .critical
        guard mode.allows(isCritical: isCriticalLike) else { return }

        let resetBucket = resetIdentity.map { String(Int($0.timeIntervalSince1970 / 300)) } ?? "live"
        let signature = "\(level.rawValue):\(resetBucket)"
        guard self.defaults.string(forKey: key) != signature else { return }

        let settings = await self.center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = isCriticalLike ? .default : nil
        content.interruptionLevel = isCriticalLike ? .timeSensitive : .active

        let request = UNNotificationRequest(
            identifier: "\(self.prefix).\(kind.rawValue).\(metric.rawValue).\(level.rawValue)",
            content: content,
            trigger: nil)

        do {
            try await self.center.add(request)
            self.defaults.set(signature, forKey: key)
        } catch {
            // Ignore notification delivery failures; the menu bar UI remains authoritative.
        }
    }

    private func contextBody(context: WorkContextSnapshot, level: ThresholdLevel) -> String {
        let remaining = context.estimatedMessagesRemaining.map { "~\($0) turns left at this pace" } ?? "pace is still being learned"
        switch level {
        case .watch:
            return "\(remaining). Keep the next ask focused."
        case .hot:
            return "\(remaining). Consider summarizing before a large change."
        case .critical, .depleted:
            // Context never resolves to .depleted via thresholds, but
            // covering it keeps the switch exhaustive.
            return "\(remaining). Wrap this thread or start fresh soon."
        }
    }

    private func windowBody(window: UsageWindow, metric: NotificationMetric, level: ThresholdLevel) -> String {
        let reset = Self.resetText(window.resetsAt)
        let resetClock = Self.resetClock(window.resetsAt)
        switch (metric, level) {
        case (.session, .watch):
            return "The 5h burst is heating up; \(reset)."
        case (.session, .hot):
            return "Use focused turns until reset; \(reset)."
        case (.session, .critical):
            return "You are near the 5h burst edge; \(reset)."
        case (.session, .depleted):
            return "5h window full — back at \(resetClock)."
        case (.weekly, .watch):
            return "Weekly usage is elevated; \(reset)."
        case (.weekly, .hot):
            return "Weekly room is getting tight; \(reset)."
        case (.weekly, .critical):
            return "Weekly limit is nearly exhausted; \(reset)."
        case (.weekly, .depleted):
            return "Weekly cap reached — back at \(resetClock)."
        case (.context, _):
            return reset
        }
    }

    /// Reset-celebration emit. Bypasses the level/threshold path because
    /// it's an event, not a state. Dedup is keyed off the *new* reset
    /// time so the same roll can't fire twice if multiple refreshes
    /// observe it.
    private func emitReset(kind: ProviderKind, metric: NotificationMetric, window: UsageWindow) async {
        let key = "\(self.prefix).reset.\(kind.rawValue).\(metric.rawValue)"
        let signature = window.resetsAt.map { String(Int($0.timeIntervalSince1970 / 300)) } ?? "live"
        guard self.defaults.string(forKey: key) != signature else { return }

        // Reset celebrations are positive-but-quiet — respect "off"
        // mode, but skip them in "critical only" mode (they're not a
        // problem, so people who only want urgent alerts shouldn't see
        // them).
        let mode = UsageAlertMode(rawValue: self.defaults.string(forKey: Self.alertModeKey) ?? "") ?? .all
        guard mode == .all else { return }

        let settings = await self.center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(Self.providerLabel(kind)) \(metric.titleSuffix) reset"
        content.body = self.resetBody(metric: metric)
        content.interruptionLevel = .active

        let request = UNNotificationRequest(
            identifier: "\(self.prefix).\(kind.rawValue).\(metric.rawValue).reset",
            content: content,
            trigger: nil)

        do {
            try await self.center.add(request)
            self.defaults.set(signature, forKey: key)
        } catch {
            // Ignore notification delivery failures; menu bar remains authoritative.
        }
    }

    private func resetBody(metric: NotificationMetric) -> String {
        switch metric {
        case .session: "5 hours of headroom restored — back online."
        case .weekly: "Weekly window rolled — full budget back."
        case .context: "Window reset."
        }
    }

    private static func providerLabel(_ kind: ProviderKind) -> String {
        switch kind {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    private static func resetText(_ date: Date?) -> String {
        guard let date else { return "reset time unavailable" }
        let remaining = max(0, Int(date.timeIntervalSinceNow / 60))
        if remaining < 60 { return "resets in \(remaining)m" }
        let hours = remaining / 60
        if hours < 24 { return "resets in \(hours)h" }
        return "resets in \(hours / 24)d"
    }

    /// Clock-face formatter for the depleted message: "back at 14:32".
    /// More actionable than a duration when the user needs to schedule
    /// around a hard rate-limit.
    private static func resetClock(_ date: Date?) -> String {
        guard let date else { return "reset time unavailable" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

enum UsageAlertMode: String, CaseIterable {
    case all
    case critical
    case off

    var title: String {
        switch self {
        case .all: "Alerts all"
        case .critical: "Alerts critical"
        case .off: "Alerts off"
        }
    }

    var next: UsageAlertMode {
        switch self {
        case .all: .critical
        case .critical: .off
        case .off: .all
        }
    }

    func allows(isCritical: Bool) -> Bool {
        switch self {
        case .all: true
        case .critical: isCritical
        case .off: false
        }
    }
}

private enum NotificationMetric: String {
    case context
    case session
    case weekly

    /// Provider-agnostic suffix composed into the notification title at
    /// call site, e.g. "Claude 5h window is 85% used".
    var titleSuffix: String {
        switch self {
        case .context: "context"
        case .session: "5h window"
        case .weekly: "weekly window"
        }
    }
}

private enum ThresholdLevel: String, Comparable {
    case watch
    case hot
    case critical
    /// Window is fully exhausted — user is hard rate-limited until the
    /// reset clock. Window-only; context never gets `.depleted` because
    /// context isn't a rate limit, just a buffer that gets uncomfortable.
    case depleted

    static func < (lhs: ThresholdLevel, rhs: ThresholdLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    static func context(_ percent: Double) -> ThresholdLevel? {
        switch percent {
        case 92...: .critical
        case 82...: .hot
        case 70...: .watch
        default: nil
        }
    }

    static func window(_ percent: Double, metric: NotificationMetric) -> ThresholdLevel? {
        switch metric {
        case .context:
            return self.context(percent)
        case .session:
            if percent >= 99 { return .depleted }
            if percent >= 95 { return .critical }
            if percent >= 85 { return .hot }
            if percent >= 70 { return .watch }
            return nil
        case .weekly:
            if percent >= 99 { return .depleted }
            if percent >= 96 { return .critical }
            if percent >= 88 { return .hot }
            if percent >= 75 { return .watch }
            return nil
        }
    }

    private var rank: Int {
        switch self {
        case .watch: 0
        case .hot: 1
        case .critical: 2
        case .depleted: 3
        }
    }
}
