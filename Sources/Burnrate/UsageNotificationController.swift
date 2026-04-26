import BurnrateCore
import Foundation
import UserNotifications

final class UsageNotificationController {
    static let alertModeKey = "burnrate.notification.mode"

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let prefix = "burnrate.notification.codex"

    func prepare() async {
        do {
            _ = try await self.center.requestAuthorization(options: [.alert, .sound])
        } catch {
            // Notification permission failures should never block usage refresh.
        }
    }

    func evaluate(_ overview: UsageOverview) async {
        guard let codex = overview.snapshot(for: .codex) else { return }

        if let context = codex.workContext {
            await self.evaluateContext(context)
        }

        if let primary = codex.primaryWindow {
            await self.evaluateWindow(primary, metric: .session)
        }

        if let weekly = codex.windows.first(where: { $0.title.localizedCaseInsensitiveContains("weekly") }) {
            await self.evaluateWindow(weekly, metric: .weekly)
        }
    }

    private func evaluateContext(_ context: WorkContextSnapshot) async {
        let percent = context.contextUsedPercent
        let level = ThresholdLevel.context(percent)
        let body = level.map { self.contextBody(context: context, level: $0) } ?? ""
        await self.emitIfNeeded(
            metric: .context,
            level: level,
            percent: percent,
            resetIdentity: nil,
            title: "Codex context is \(Int(percent.rounded()))% full",
            body: body)
    }

    private func evaluateWindow(_ window: UsageWindow, metric: NotificationMetric) async {
        let level = ThresholdLevel.window(window.usedPercent, metric: metric)
        let body = level.map { self.windowBody(window: window, metric: metric, level: $0) } ?? ""
        await self.emitIfNeeded(
            metric: metric,
            level: level,
            percent: window.usedPercent,
            resetIdentity: window.resetsAt,
            title: "\(metric.title) is \(Int(window.usedPercent.rounded()))% used",
            body: body)
    }

    private func emitIfNeeded(
        metric: NotificationMetric,
        level: ThresholdLevel?,
        percent: Double,
        resetIdentity: Date?,
        title: String,
        body: String) async
    {
        let key = "\(self.prefix).\(metric.rawValue)"
        guard let level else {
            self.defaults.removeObject(forKey: key)
            return
        }

        let mode = UsageAlertMode(rawValue: self.defaults.string(forKey: Self.alertModeKey) ?? "") ?? .all
        guard mode.allows(isCritical: level == .critical) else { return }

        let resetBucket = resetIdentity.map { String(Int($0.timeIntervalSince1970 / 300)) } ?? "live"
        let signature = "\(level.rawValue):\(resetBucket)"
        guard self.defaults.string(forKey: key) != signature else { return }

        let settings = await self.center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = level == .critical ? .default : nil
        content.interruptionLevel = level == .critical ? .timeSensitive : .active

        let request = UNNotificationRequest(
            identifier: "\(self.prefix).\(metric.rawValue).\(level.rawValue)",
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
        case .critical:
            return "\(remaining). Wrap this thread or start fresh soon."
        }
    }

    private func windowBody(window: UsageWindow, metric: NotificationMetric, level: ThresholdLevel) -> String {
        let reset = Self.resetText(window.resetsAt)
        switch (metric, level) {
        case (.session, .watch):
            return "The 5h burst is heating up; \(reset)."
        case (.session, .hot):
            return "Use focused turns until reset; \(reset)."
        case (.session, .critical):
            return "You are near the 5h burst edge; \(reset)."
        case (.weekly, .watch):
            return "Weekly usage is elevated; \(reset)."
        case (.weekly, .hot):
            return "Weekly room is getting tight; \(reset)."
        case (.weekly, .critical):
            return "Weekly limit is nearly exhausted; \(reset)."
        case (.context, _):
            return reset
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

    var title: String {
        switch self {
        case .context: "Codex context"
        case .session: "Codex 5h window"
        case .weekly: "Codex weekly window"
        }
    }
}

private enum ThresholdLevel: String, Comparable {
    case watch
    case hot
    case critical

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
            if percent >= 95 { return .critical }
            if percent >= 85 { return .hot }
            if percent >= 70 { return .watch }
            return nil
        case .weekly:
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
        }
    }
}
