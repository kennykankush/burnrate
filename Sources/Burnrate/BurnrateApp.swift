import BurnrateCore
import SwiftUI

@main
struct BurnrateApp {
    static func main() async {
        if CommandLine.arguments.contains("--inspect-claude") {
            await InspectClaude.run()
            exit(0)
        }
        BurnrateAppScene.main()
    }
}

struct BurnrateAppScene: App {
    @NSApplicationDelegateAdaptor(BurnrateAppDelegate.self) private var appDelegate

    var body: some Scene {
        // The status item is owned by the AppDelegate via
        // `StatusBarController` so we get a custom 2-line label, right-
        // click context menu, and no MenuBarExtra height cap. The
        // Settings scene stays so SwiftUI gives the app a proper main
        // menu (otherwise quit/about behave oddly).
        Settings { EmptyView() }
    }
}

@MainActor
final class BurnrateAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private let model = MenuBarModel()
    private var statusController: StatusBarController?
    private var notchPresenter: NotchPresenter?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon. This is a status-bar app.
        NSApp.setActivationPolicy(.accessory)

        FontRegistration.registerBundledFonts()
        self.statusController = StatusBarController(model: self.model)
        self.notchPresenter = NotchPresenter(model: self.model)

        // Both the status bar label and the notch compact view need to
        // re-render on every refresh tick. Chain them off the same hook
        // so the model only needs one callback. `refresh()` (not
        // `updateDisplay`) so the toggle-on/off path also runs through
        // here when `setNotchEnabled` fires the hook.
        let existingHook = self.model.onSnapshotChanged
        self.model.onSnapshotChanged = { [weak self] in
            existingHook?()
            self?.notchPresenter?.refresh()
        }

        // Kick the refresh loop here, not from the popover's .onAppear.
        // The notch alcove needs to render real data the moment the
        // user hovers it — even if they've never opened the popover.
        self.model.start()
    }
}

enum InspectClaude {
    static func run() async {
        let watcher = ClaudeUsageWatcher()
        guard let snap = await watcher.loadSnapshot(now: Date()) else {
            print("[claude] no snapshot — ~/.claude likely empty")
            return
        }
        print("=== Claude snapshot ===")
        print("plan:        \(snap.planName ?? "—")")
        print("account:     \(snap.accountLabel ?? "—")")
        print("project:     \(snap.projectLabel ?? "—")")
        print("streakDays:  \(snap.streakDays)")
        // Dump the raw OAuth tier so we can see what Anthropic returns
        if let creds = ClaudeOAuthCredentialReader.read(claudeRoot: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")) {
            if let usage = await ClaudeOAuthUsageFetcher().fetch(credentials: creds) {
                print("oauth.rateLimitTier: \(usage.rateLimitTier ?? "—")")
                if let extra = usage.extraUsage {
                    print("oauth.extraUsage: enabled=\(extra.isEnabled) used=\(extra.usedCredits)/\(extra.monthlyLimit) \(extra.currency)")
                }
            }
        }
        print("windows:")
        for w in snap.windows {
            print("  - \(w.title): \(Int(w.usedPercent))% resets=\(w.resetsAt.map { ISO8601DateFormatter().string(from: $0) } ?? "—")")
        }
        print("today: req=\(snap.today.requests) input=\(snap.today.inputTokens) output=\(snap.today.outputTokens) min=\(snap.today.activeMinutes) peak=\(snap.today.peakHourLabel ?? "—")")
        if let live = snap.claudeSession {
            print("liveSession:")
            print("  sessionId:    \(live.sessionId ?? "—")")
            print("  project:      \(live.projectName ?? "—") (\(live.projectPath ?? "—"))")
            print("  threadTitle:  \(live.threadTitle ?? "—")")
            print("  branch:       \(live.gitBranch ?? "—")")
            print("  model:        \(live.modelName ?? "—") (cli \(live.cliVersion ?? "—"))")
            print("  permission:   \(live.permissionMode ?? "—")")
            print("  msgs:         user=\(live.userMessageCount) assistant=\(live.assistantMessageCount)")
            print("  tools:        \(live.toolCalls) calls — \(live.toolHistogram.prefix(5).map { "\($0.name)=\($0.count)" }.joined(separator: ", "))")
            print("  tokens:       in=\(live.totalInputTokens) out=\(live.totalOutputTokens) cacheR=\(live.cacheReadInputTokens) cacheC=\(live.cacheCreateInputTokens)")
            print("  lastTurn:     in=\(live.lastInputTokens) out=\(live.lastOutputTokens) cacheR=\(live.lastCacheReadTokens)")
            print("  webSearch:    \(live.webSearches) webFetch: \(live.webFetches)")
            print("  sidechain:    \(live.sidechainTokens) tokens")
            print("  activeTask:   \(live.activeTaskTitle ?? "—")")
            print("  chain:        \(live.activeTaskChain.joined(separator: " → "))")
            if let advisor = live.advisor {
                print("  advisor:      health=\(advisor.health.rawValue) → \(advisor.recommendation)")
                print("                why=\(advisor.primaryDriver) — \(advisor.driverDetail)")
                print("                forecast=\(advisor.forecast)")
                print("                newCtx=\(DisplayText.contextShare(advisor.lastTurnSharePercent)) burn/min=\(advisor.tokensPerMinute)")
            }
        }
        if let agg = snap.claudeAggregate {
            print("aggregate:")
            print("  totalSessions: \(agg.totalSessions)")
            print("  totalMessages: \(agg.totalMessages)")
            print("  daysSince:     \(agg.daysSinceFirstSession ?? -1)")
            print("  streak:        \(agg.streakDays)")
            print("  longest:       \(agg.longestSessionMinutes) min, \(agg.longestSessionMessageCount) msgs")
            print("  hourCounts:    \(agg.hourCounts)")
            print("  modelMix:      \(agg.modelMix.map { "\($0.modelName)=\(Int($0.percent))%" }.joined(separator: ", "))")
            print("  recentDays:    \(agg.recentDayTokens.suffix(7).map { "\(DateFormatter.shortDate.string(from: $0.date))=\($0.totalTokens)" }.joined(separator: ", "))")
            print("  speculation:   \(agg.speculationTimeSavedMs)ms")
            if let band = agg.peakHourBand {
                print("  peakBand:      \(band.start)-\(band.end) (\(Int(band.sharePercent))%)")
            }
        }
        if let f = snap.claudeFacets {
            print("facets:")
            print("  outcome:       \(f.outcome ?? "—")")
            print("  helpfulness:   \(f.helpfulness ?? "—")")
            print("  sessionType:   \(f.sessionType ?? "—")")
            print("  goal:          \(f.underlyingGoal ?? "—")")
            print("  summary:       \(f.briefSummary ?? "—")")
            print("  friction:      \(f.frictionCounts.map { "\($0.name)=\($0.count)" }.joined(separator: ", "))")
        }
        print("patternCards:")
        for c in snap.patternCards {
            print("  - [\(c.kind.rawValue)/\(c.tone.rawValue)] \(c.title)")
            print("      \(c.body)")
            if let foot = c.footnote { print("      (\(foot))") }
        }
        print("health:")
        for h in snap.healthIndicators {
            print("  - [\(h.status.rawValue)] \(h.label): \(h.detail)")
        }
    }
}

private extension DateFormatter {
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd"
        return f
    }()
}
