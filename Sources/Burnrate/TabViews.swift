import BurnrateCore
import SwiftUI

// MARK: - Now tab

struct NowView: View {
    let snapshot: ProviderUsageSnapshot
    let overview: UsageOverview
    let turnPattern: MenuBarModel.TurnPattern?
    let model: MenuBarModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Full-bleed top strip — Liquid Glass material with a purple
                // radial wash on top, fades into the popover surface below.
                AccountTodayStrip(snapshot: self.snapshot)
                    .padding(.horizontal, DesignSystem.Layout.contentPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        ZStack {
                            Rectangle().fill(.ultraThinMaterial)
                            RadialGradient(
                                colors: [
                                    Brand.Palette.brandPurple.opacity(0.55),
                                    Brand.Palette.brandPurple.opacity(0.18),
                                    Color.clear,
                                ],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: 380)
                            LinearGradient(
                                colors: [Color.clear, Color.black.opacity(0.22)],
                                startPoint: .top,
                                endPoint: .bottom)
                        }
                    }

                // Remaining sections, standard padding.
                //
                // Order: Session (context) → Windows → BurnWatch.
                // Context is the primary constraint for most live work
                // (you usually run out of context-window before you run
                // out of 5h burst), so it sits directly under the
                // header to answer "how many turns can I do?" with the
                // shortest scan.
                VStack(alignment: .leading, spacing: 12) {
                    SessionSection(snapshot: self.snapshot, pattern: self.turnPattern)

                    if !self.snapshot.windows.isEmpty {
                        NowDivider()
                        WindowsSection(snapshot: self.snapshot, model: self.model)
                    }

                    NowDivider()
                    BurnWatchCard(snapshot: self.snapshot)
                }
                .padding(.horizontal, DesignSystem.Layout.contentPadding)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Account + Today header strip

private struct AccountTodayStrip: View {
    let snapshot: ProviderUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row — plan capsule + status meta (small, quieter)
            HStack(spacing: 8) {
                if let plan = self.snapshot.planName {
                    Text(plan)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.brandLavender)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background {
                            Capsule().fill(DesignSystem.Colors.brandLavender.opacity(0.18))
                        }
                }

                HStack(spacing: 5) {
                    ForEach(self.statusItems, id: \.self) { item in
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundStyle(DesignSystem.Colors.tertiaryText)
                        Text(item)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(DesignSystem.Colors.tertiaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }

            // Big stat row — 299 turns | 297K tokens | 3h 25m active
            HStack(spacing: 0) {
                BigStat(value: "\(self.snapshot.today.requests)", label: "turns")
                BigStatPipe()
                BigStat(value: DisplayText.compact(self.snapshot.today.totalTokens), label: "tokens")
                BigStatPipe()
                BigStat(value: DisplayText.minutes(self.snapshot.today.activeMinutes), label: "active")
                if let spend = self.snapshot.today.spend {
                    BigStatPipe()
                    BigStat(value: DisplayText.money(spend.used, currency: spend.currencyCode), label: "spend")
                }
                Spacer(minLength: 0)
            }
        }
        // Decorative mountain in an overlay so it doesn't reserve layout
        // space — the strip's height is purely the stat content.
        .overlay(alignment: .topTrailing) {
            Brand.image(.maxMountain)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 270, height: 110)
                .mask {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.5), .black, .black],
                        startPoint: .leading,
                        endPoint: .trailing)
                }
                .opacity(0.88)
                .allowsHitTesting(false)
                .offset(x: 36, y: 3)
        }
    }

    private var statusItems: [String] {
        var items: [String] = []
        if self.snapshot.kind == .claude { items.append("OAuth") }
        if self.isLive { items.append("live") }
        if let project = self.projectLabel { items.append(project) }
        return items
    }

    private var isLive: Bool {
        if let last = self.snapshot.claudeSession?.lastActivityAt {
            return Date().timeIntervalSince(last) < 300
        }
        if let last = self.snapshot.codexSession?.lastActivityAt {
            return Date().timeIntervalSince(last) < 300
        }
        return false
    }

    private var projectLabel: String? {
        if let proj = self.snapshot.projectLabel { return proj }
        if let dir = self.snapshot.workContext?.directory {
            return URL(fileURLWithPath: dir).lastPathComponent
        }
        return self.snapshot.claudeSession?.projectName
    }
}

private struct BigStat: View {
    let value: String
    let label: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(self.value)
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.5), value: self.value)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(self.label)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
        }
    }
}

private struct BigStatPipe: View {
    var body: some View {
        Rectangle()
            .fill(DesignSystem.Colors.stroke.opacity(0.55))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 12)
    }
}

private struct NowDivider: View {
    var body: some View {
        LinearGradient(
            colors: [
                DesignSystem.Colors.brandLavender.opacity(0.0),
                DesignSystem.Colors.brandLavender.opacity(0.28),
                DesignSystem.Colors.brandLavender.opacity(0.0),
            ],
            startPoint: .leading,
            endPoint: .trailing)
            .frame(height: 1)
            .padding(.vertical, 4)
    }
}

private struct InlineSectionLabel: View {
    let title: String

    var body: some View {
        Text(self.title.uppercased())
            .font(.geist(size: 10, weight: .semibold))
            .foregroundStyle(DesignSystem.Colors.brandLavender)
            .tracking(1.4)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background {
                Capsule().fill(DesignSystem.Colors.brandLavender.opacity(0.18))
            }
    }
}

private struct WindowsSection: View {
    let snapshot: ProviderUsageSnapshot
    let model: MenuBarModel

    private var hasOAuthWindows: Bool {
        self.snapshot.windows.contains { $0.id.hasPrefix("claude-oauth-") }
    }

    private var showsAuthHint: Bool {
        self.snapshot.kind == .claude && !self.hasOAuthWindows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InlineSectionLabel(title: "Windows")
            VStack(spacing: 6) {
                ForEach(self.snapshot.windows) { window in
                    WindowRow(window: window, forecast: self.model.forecast(for: window))
                }
                if self.showsAuthHint {
                    OAuthMissingHint()
                }
            }
        }
    }
}

private struct OAuthMissingHint: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.brandLavender.opacity(0.85))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text("Can't detect auth")
                    .font(.geist(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                Text("5h burst & 7d windows need Claude Code OAuth — open Keychain Access, find \u{201C}Claude Code-credentials\u{201D}, and allow burnrate.")
                    .font(.geist(size: 10))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DesignSystem.Colors.brandLavender.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(DesignSystem.Colors.brandLavender.opacity(0.2), lineWidth: 1)
                }
        }
    }
}

private struct WindowRow: View {
    let window: UsageWindow
    let forecast: MenuBarModel.WindowForecast?

    private var tone: UsageTone { UsageTone(percent: self.window.usedPercent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(self.windowLabel)
                    .font(.geist(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                    .frame(width: 84, alignment: .leading)
                    .lineLimit(1)
                    .help(self.windowExplanation)

                MeterBar(tone: self.tone, usedPercent: self.window.usedPercent)
                    .frame(maxWidth: .infinity)

                Text("\(Int(self.window.usedPercent.rounded()))%")
                    .font(.geistMono(size: 11, weight: .semibold))
                    .foregroundStyle(self.tone.color)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.5), value: self.window.usedPercent)
                    .frame(width: 32, alignment: .trailing)

                Text(DisplayText.resetShort(self.window.resetsAt))
                    .font(.geistMono(size: 9))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    .frame(width: 36, alignment: .trailing)
                    .lineLimit(1)
            }

            // When the window is depleted, the forecast is moot — show
            // an unmistakable DEPLETED pill + reset clock in its place.
            // 99% matches the threshold used by the notification
            // controller so the in-app state and the notification fire
            // together.
            if self.window.usedPercent >= 99 {
                DepletedLine(resetsAt: self.window.resetsAt)
            } else if let forecast = self.forecast {
                ForecastLine(window: self.window, forecast: forecast)
            }
        }
    }

    private var windowLabel: String {
        switch self.window.title {
        case "5h": "5h burst"
        case "7d": "7d window"
        case "7d Opus": "7d · Opus"
        case "7d Sonnet": "7d · Sonnet"
        default: self.window.title
        }
    }

    private var windowExplanation: String {
        let id = self.window.id
        if id.contains("5h") || id.hasSuffix("primary") || self.window.title.localizedCaseInsensitiveContains("session") {
            return "5-hour rolling burst window. Resets in real time, not on the clock — every turn ages out exactly 5h after it landed."
        }
        if id.contains("7d-opus") || self.window.title.localizedCaseInsensitiveContains("opus") {
            return "Per-model 7-day cap on Opus usage. Some plans split Opus and Sonnet into separate weekly buckets."
        }
        if id.contains("7d-sonnet") || self.window.title.localizedCaseInsensitiveContains("sonnet") {
            return "Per-model 7-day cap on Sonnet usage. Some plans split Opus and Sonnet into separate weekly buckets."
        }
        if id.contains("7d") || id.contains("weekly") || self.window.title.localizedCaseInsensitiveContains("week") {
            return "7-day rolling cap. Resets exactly 7 days from when you crossed the threshold, not on Monday."
        }
        if id.contains("context") || self.window.title.localizedCaseInsensitiveContains("context") {
            return "Tokens used in the active session's context window. Resets when you /clear, /compact, or open a fresh thread."
        }
        return self.windowLabel
    }
}

private struct DepletedLine: View {
    let resetsAt: Date?

    private var resetClock: String {
        guard let resetsAt else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: resetsAt)
    }

    var body: some View {
        HStack(spacing: 6) {
            Spacer().frame(width: 84)
            Text("DEPLETED")
                .font(.geist(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(DesignSystem.Colors.danger)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(DesignSystem.Colors.danger.opacity(0.14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(DesignSystem.Colors.danger.opacity(0.35), lineWidth: 1)
                        }
                }
            Text("back at \(self.resetClock)")
                .font(.geist(size: 9))
                .foregroundStyle(DesignSystem.Colors.secondaryText)
            Spacer(minLength: 0)
        }
    }
}

private struct ForecastLine: View {
    let window: UsageWindow
    let forecast: MenuBarModel.WindowForecast

    private var trendsOver: Bool {
        (self.forecast.projectedAtResetPercent ?? 0) > 100
    }

    var body: some View {
        HStack(spacing: 5) {
            Spacer().frame(width: 84)

            // Snapshot reading — always shown when forecast surfaces.
            Text("\(Int(self.forecast.aheadOfPacePercent.rounded()))% ahead of pace")
                .font(.geist(size: 9, weight: .semibold))
                .foregroundStyle(self.trendsOver ? DesignSystem.Colors.danger : DesignSystem.Colors.warning)

            // Forecast clause — only when we have meaningful new info to add.
            if let projected = self.forecast.projectedAtResetPercent,
               abs(projected - self.window.usedPercent) >= 1
            {
                Text("·")
                    .font(.geist(size: 9))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)

                if let runsOut = self.forecast.runsOutAt {
                    Text("runs out in \(DisplayText.runsOut(runsOut))")
                        .font(.geist(size: 9))
                        .foregroundStyle(DesignSystem.Colors.danger)
                } else {
                    Text("trending to \(Int(projected.rounded()))% by reset")
                        .font(.geist(size: 9))
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Stat strip (header row of compact metrics)

private struct StatStrip: View {
    let snapshot: ProviderUsageSnapshot

    var body: some View {
        HStack(spacing: 0) {
            StatStripItem(
                label: self.snapshot.kind == .claude ? "Plan" : "Tier",
                value: self.snapshot.planName ?? "—",
                accent: DesignSystem.Colors.brandLavender)

            StatStripDivider()

            StatStripItem(
                label: "$/min",
                value: self.spendPerMinuteLabel,
                mono: true,
                accent: self.spendTone.color)

            StatStripDivider()

            StatStripItem(
                label: self.snapshot.primaryWindow?.title ?? "window",
                value: "\(Int(self.snapshot.primaryUsedPercent.rounded()))%",
                mono: true,
                accent: UsageTone(percent: self.snapshot.primaryUsedPercent).color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .brandGlass(cornerRadius: DesignSystem.Layout.cardRadius)
    }

    private var spendPerMinuteLabel: String {
        if let usd = self.snapshot.claudeSession?.advisor?.usdPerMinute, usd > 0 {
            return String(format: "$%.2f", usd)
        }
        if let perMin = self.snapshot.codexSession?.insight?.tokensPerMinute, perMin > 0 {
            return DisplayText.compact(perMin)
        }
        return "—"
    }

    private var spendTone: UsageTone {
        if let usd = self.snapshot.claudeSession?.advisor?.usdPerMinute {
            return usd > 0.30 ? .tight : (usd > 0.15 ? .watch : .calm)
        }
        return .calm
    }
}

private struct StatStripItem: View {
    let label: String
    let value: String
    var mono: Bool = false
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(self.label.uppercased())
                .font(.geist(size: 9, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .lineLimit(1)
            Text(self.value)
                .font(self.mono ? .geistMono(size: 14, weight: .semibold) : .geist(size: 14, weight: .semibold))
                .foregroundStyle(self.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                // Native digit-tick transition when values refresh — the macOS
                // Tahoe counter morph (system-rendered, GPU-accelerated).
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.5), value: self.value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatStripDivider: View {
    var body: some View {
        Rectangle()
            .fill(DesignSystem.Colors.stroke.opacity(0.5))
            .frame(width: 1, height: 28)
    }
}

// MARK: - Burn Watch section (flat, no card chrome)

private struct BurnWatchCard: View {
    let snapshot: ProviderUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            InlineSectionLabel(title: "Stamina")

            if let advisor = self.snapshot.claudeSession?.advisor {
                FlatAdvisorContent(
                    health: advisor.health,
                    recommendation: advisor.recommendation,
                    primaryDriver: advisor.primaryDriver,
                    driverDetail: advisor.driverDetail,
                    forecast: advisor.forecast,
                    resetPlan: advisor.resetPlan,
                    lastTurnSharePercent: advisor.lastTurnSharePercent,
                    tokensPerMinute: advisor.tokensPerMinute,
                    usdPerMinute: advisor.usdPerMinute,
                    cacheSharePercent: self.snapshot.claudeSession?.cacheSharePercent)
            } else if let insight = self.snapshot.codexSession?.insight {
                FlatAdvisorContent(
                    health: insight.health,
                    recommendation: insight.recommendation,
                    primaryDriver: insight.primaryDriver,
                    driverDetail: insight.driverDetail,
                    forecast: insight.forecast,
                    resetPlan: insight.resetPlan,
                    lastTurnSharePercent: insight.lastTurnSharePercent,
                    tokensPerMinute: insight.tokensPerMinute,
                    usdPerMinute: nil,
                    cacheSharePercent: self.snapshot.codexSession?.cacheSharePercent)
            } else {
                BurnWatchEmpty()
            }
        }
    }
}

private struct FlatAdvisorContent: View {
    let health: CodexThreadHealth
    let recommendation: String
    let primaryDriver: String
    let driverDetail: String
    let forecast: String
    let resetPlan: String
    let lastTurnSharePercent: Double
    let tokensPerMinute: Int
    let usdPerMinute: Double?
    let cacheSharePercent: Double?

    private var tone: UsageTone { UsageTone(health: self.health) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Hero verdict — typographic focal point of the section
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: self.iconName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(self.tone.color)
                    .contentTransition(.symbolEffect(.replace))
                Text(self.health.title)
                    .font(.geist(size: 28, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }

            Text(self.recommendation)
                .font(.geist(size: 12))
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                AdvisorInfoLine(value: self.primaryDriver, detail: self.driverDetail)
                AdvisorInfoLine(value: self.forecast, detail: self.resetPlan)
            }

            HStack(spacing: 14) {
                FlatMeter(
                    label: "New ctx",
                    value: DisplayText.contextShare(self.lastTurnSharePercent),
                    percent: self.lastTurnSharePercent,
                    tone: self.tone)

                if let usd = self.usdPerMinute, usd > 0 {
                    FlatMeter(
                        label: "$/min",
                        value: String(format: "$%.2f", usd),
                        percent: min(100, usd / 0.50 * 100),
                        tone: usd > 0.30 ? .tight : (usd > 0.15 ? .watch : .calm))
                } else {
                    FlatMeter(
                        label: "Burn/min",
                        value: DisplayText.compact(self.tokensPerMinute),
                        percent: min(100, Double(self.tokensPerMinute) / 1_200 * 100),
                        tone: self.tone)
                }

                if let cache = self.cacheSharePercent, cache > 0 {
                    FlatMeter(
                        label: "Cache",
                        value: "\(Int(cache.rounded()))%",
                        percent: cache,
                        tone: .calm)
                }
            }
        }
    }

    private var iconName: String {
        switch self.health {
        case .efficient: "bolt.badge.checkmark"
        case .healthy: "checkmark.seal"
        case .watch: "eye"
        case .tight: "exclamationmark.triangle"
        case .stuck: "wrench.and.screwdriver"
        }
    }
}

private struct AdvisorInfoLine: View {
    let value: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle()
                .fill(DesignSystem.Colors.brandLavender.opacity(0.6))
                .frame(width: 4, height: 4)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(self.value)
                    .font(.geist(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                    .lineLimit(1)
                Text(self.detail)
                    .font(.geist(size: 10))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct FlatMeter: View {
    let label: String
    let value: String
    let percent: Double
    let tone: UsageTone

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(self.label.uppercased())
                    .font(.geist(size: 8, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    .tracking(0.6)
                Spacer(minLength: 0)
                Text(self.value)
                    .font(.geistMono(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.45), value: self.value)
            }
            MeterBar(tone: self.tone, usedPercent: self.percent)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BurnWatchEmpty: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.stars")
                .font(.system(size: 14))
                .foregroundStyle(DesignSystem.Colors.brandLavender)
            VStack(alignment: .leading, spacing: 1) {
                Text("All quiet")
                    .font(.geist(size: 13, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                Text("no live session right now — pop back when you're coding")
                    .font(.geist(size: 10))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Session section (flat, no card chrome)

private struct SessionSection: View {
    let snapshot: ProviderUsageSnapshot
    let pattern: MenuBarModel.TurnPattern?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InlineSectionLabel(title: "Session")

            if let context = self.snapshot.workContext {
                FlatSessionContext(context: context, pattern: self.pattern)
            } else if self.snapshot.claudeSession == nil && self.snapshot.codexSession == nil {
                Text("No active session right now")
                    .font(.geist(size: 11))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
            }
        }
    }
}

private struct FlatSessionContext: View {
    let context: WorkContextSnapshot
    let pattern: MenuBarModel.TurnPattern?

    private var tone: UsageTone { UsageTone(percent: self.context.contextUsedPercent) }
    private var isCritical: Bool { self.context.contextUsedPercent >= 75 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Hero row — big ctx % matching the top-section visual hierarchy
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(self.context.contextRemainingPercent.rounded()))%")
                    .font(.geist(size: 22, weight: .bold))
                    .foregroundStyle(self.tone.color)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.45), value: self.context.contextRemainingPercent)
                Text("context left")
                    .font(.geist(size: 11))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                Spacer(minLength: 6)
                if let msgs = self.context.estimatedMessagesRemaining {
                    Text("~\(msgs) msgs")
                        .font(.geistMono(size: 11, weight: .semibold))
                        .foregroundStyle(self.isCritical ? DesignSystem.Colors.warning : DesignSystem.Colors.secondaryText)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.45), value: msgs)
                }
            }

            MeterBar(tone: self.tone, usedPercent: self.context.contextUsedPercent)

            // Project + model + tokens — single line of supporting info
            HStack(spacing: 6) {
                Text(self.directoryName)
                    .font(.geist(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                    .lineLimit(1)
                if let model = self.context.modelName {
                    Text("·").foregroundStyle(DesignSystem.Colors.tertiaryText)
                    Text(model).foregroundStyle(DesignSystem.Colors.secondaryText).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text("\(DisplayText.compact(self.context.contextUsedTokens)) / \(DisplayText.compact(self.context.contextWindowTokens))")
                    .font(.geistMono(size: 10))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
            }
            .font(.geist(size: 11))

            if self.isCritical {
                if let pattern = self.pattern, pattern.hasEnoughData {
                    PersonalizedForecast(context: self.context, pattern: pattern)
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(DesignSystem.Colors.warning)
                        Text("Approaching limit — \(Int(self.context.contextUsedPercent.rounded()))% used")
                            .font(.geist(size: 10, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.warning)
                    }
                }
            }
        }
    }

    private var directoryName: String {
        guard let dir = self.context.directory else { return "session" }
        return URL(fileURLWithPath: dir).lastPathComponent
    }

    private func warningCopy(msgs: Int) -> String {
        let pct = Int(self.context.contextUsedPercent.rounded())
        if msgs <= 3 { return "Critical — \(msgs) \(msgs == 1 ? "message" : "messages") before compact" }
        if msgs <= 8 { return "Tight — \(pct)% used, compact soon" }
        return "Approaching limit — \(pct)% used"
    }
}

private struct PersonalizedForecast: View {
    let context: WorkContextSnapshot
    let pattern: MenuBarModel.TurnPattern

    private var remainingTokens: Int { self.context.contextRemainingTokens }
    private var avgTurnsLeft: Int { max(0, self.remainingTokens / max(1, self.pattern.avg)) }
    private var p90TurnsLeft: Int { max(0, self.remainingTokens / max(1, self.pattern.p90)) }

    private var verdict: (icon: String, color: Color, copy: String) {
        let pct = Int(self.context.contextUsedPercent.rounded())
        // Recent turns ran larger than usual + little headroom = warn,
        // but don't predict the next ask. We can't know what you'll send.
        if self.pattern.trend == .up, self.avgTurnsLeft <= 2 {
            return ("flame.fill", DesignSystem.Colors.danger,
                    "Recent turns ran larger than usual. \(pct)% used.")
        }
        // Big asks won't fit
        if self.p90TurnsLeft == 0 {
            return ("exclamationmark.triangle.fill", DesignSystem.Colors.danger,
                    "No room for a typical big ask. Compact soon.")
        }
        // Average won't fit
        if self.avgTurnsLeft == 0 {
            return ("exclamationmark.triangle.fill", DesignSystem.Colors.warning,
                    "No room for another average turn at \(pct)% used.")
        }
        // Borderline
        if self.avgTurnsLeft <= 2 {
            return ("exclamationmark.triangle.fill", DesignSystem.Colors.warning,
                    "Tight — \(self.avgTurnsLeft) avg turn\(self.avgTurnsLeft == 1 ? "" : "s") left.")
        }
        // Healthy
        return ("info.circle", DesignSystem.Colors.brandLavender,
                "~\(self.avgTurnsLeft) avg turns left at your pace.")
    }

    private var smallBucket: Int { max(2_000, Int(Double(self.pattern.avg) * 0.4)) }
    private var mediumBucket: Int { max(6_000, self.pattern.avg) }
    private var largeBucket: Int { max(20_000, max(self.pattern.p90, Int(Double(self.pattern.avg) * 2.5))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: self.verdict.icon)
                    .font(.system(size: 9))
                    .foregroundStyle(self.verdict.color)
                Text(self.verdict.copy)
                    .font(.geist(size: 10, weight: .semibold))
                    .foregroundStyle(self.verdict.color)
            }

            // Personalized bucket gauge — sizes derived from YOUR pattern
            HStack(spacing: 0) {
                BucketChip(
                    count: max(0, self.remainingTokens / self.smallBucket),
                    label: "small",
                    description: "~\(DisplayText.compact(self.smallBucket))")
                BucketSep()
                BucketChip(
                    count: max(0, self.remainingTokens / self.mediumBucket),
                    label: "medium",
                    description: "~\(DisplayText.compact(self.mediumBucket))")
                BucketSep()
                BucketChip(
                    count: max(0, self.remainingTokens / self.largeBucket),
                    label: "large",
                    description: "~\(DisplayText.compact(self.largeBucket))")
                Spacer(minLength: 0)
            }
            .padding(.top, 1)

            // Transparency line — what the math is based on
            HStack(spacing: 6) {
                Text("based on your last \(self.pattern.samples.count) turn\(self.pattern.samples.count == 1 ? "" : "s")")
                    .font(.geist(size: 9))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                Text("·")
                    .font(.geist(size: 9))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                Text("avg \(DisplayText.compact(self.pattern.avg))")
                    .font(.geistMono(size: 9))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                if self.pattern.trend == .up {
                    Text("↑")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.danger)
                } else if self.pattern.trend == .down {
                    Text("↓")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.success)
                }
            }
        }
    }
}

private struct BucketChip: View {
    let count: Int
    let label: String
    let description: String

    var body: some View {
        HStack(spacing: 3) {
            Text("\(self.count)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(self.count == 0 ? DesignSystem.Colors.danger : DesignSystem.Colors.primaryText)
            Text(self.label)
                .font(.geist(size: 9))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
            Text("(\(self.description))")
                .font(.geistMono(size: 8))
                .foregroundStyle(DesignSystem.Colors.tertiaryText.opacity(0.7))
        }
    }
}

private struct BucketSep: View {
    var body: some View {
        Text("·")
            .font(.geist(size: 10))
            .foregroundStyle(DesignSystem.Colors.tertiaryText)
            .padding(.horizontal, 6)
    }
}

private struct FlatTaskRibbon: View {
    let session: ClaudeSessionStats

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: self.glyph)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.brandLavender)
            Text(self.detail)
                .font(.geist(size: 10))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if let durationMs = self.session.lastTurnDurationMs {
                Text("\(durationMs / 1000)s")
                    .font(.geistMono(size: 10))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
            }
        }
    }

    private var glyph: String {
        guard let last = self.session.activeTaskChain.last else { return "sparkle" }
        switch last {
        case "Edit", "Write", "NotebookEdit": return "pencil.line"
        case "Read": return "doc.text"
        case "Bash": return "terminal"
        case "Grep", "Glob": return "magnifyingglass"
        case "WebSearch", "WebFetch": return "globe"
        case "Skill": return "sparkles"
        case "Task", "Agent": return "person.2"
        case "TaskCreate", "TaskUpdate": return "checklist"
        default: return "wand.and.stars"
        }
    }

    private var detail: String {
        let chain = self.session.activeTaskChain.suffix(3)
        let chainStr = chain.isEmpty ? "" : chain.joined(separator: " → ")
        let parts: [String] = [
            chainStr,
            self.session.gitBranch.map { "branch \($0)" } ?? "",
            "turn \(self.session.assistantMessageCount)",
        ].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Surface tab

struct SurfaceView: View {
    let snapshot: ProviderUsageSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let surface = self.snapshot.codexSurface {
                    CodexSurfaceOverviewPanel(surface: surface, context: self.snapshot.workContext)
                    if !surface.activityDays.isEmpty {
                        CodexActivityPulseCard(surface: surface)
                    }
                    CodexProjectLeaderboardCard(surface: surface)
                    CodexRecentThreadsCard(surface: surface)

                    if let session = self.snapshot.codexSession {
                        VStack(alignment: .leading, spacing: 8) {
                            InlineSectionLabel(title: "Current Work")
                            CodexTelemetryCard(session: session)
                            if !session.flightEvents.isEmpty {
                                CodexFlightRecorderCard(session: session)
                            }
                        }
                    }
                } else {
                    SurfaceEmptyView(snapshot: self.snapshot)
                }
            }
            .padding(.leading, DesignSystem.Layout.contentPadding)
            .padding(.trailing, DesignSystem.Layout.contentPadding)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
    }
}

private struct SurfaceEmptyView: View {
    let snapshot: ProviderUsageSnapshot

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: self.snapshot.kind == .codex ? "square.stack.3d.up" : "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.brandLavender)
            Text(self.title)
                .font(.geist(size: 13, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.primaryText)
            Text(self.detail)
                .font(.geist(size: 11))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity)
        .padding(36)
        .brandGlass(cornerRadius: DesignSystem.Layout.cardRadius)
    }

    private var title: String {
        self.snapshot.kind == .codex
            ? "Codex map warming up"
            : "Switch to Codex"
    }

    private var detail: String {
        self.snapshot.kind == .codex
            ? "The work map appears once Codex has a local thread to read."
            : "This tab summarizes Codex work, projects, recent threads, and active context."
    }
}

// MARK: - Patterns tab

struct PatternsView: View {
    let snapshot: ProviderUsageSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if self.snapshot.kind == .claude {
                    ClaudePatternsTabContent(cards: self.snapshot.patternCards.filter { Self.patternsTabKinds.contains($0.kind) })
                } else if self.snapshot.kind == .codex {
                    CodexPatternsNativeView(snapshot: self.snapshot)
                }

                if self.snapshot.patternCards.isEmpty && self.snapshot.kind == .claude {
                    PatternsEmpty()
                }
            }
            .padding(.leading, DesignSystem.Layout.contentPadding)
            .padding(.trailing, DesignSystem.Layout.contentPadding)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
    }

    static let patternsTabKinds: Set<ClaudePatternKind> = [
        .chronotype, .modelMix, .hourProfile, .toolBias, .anxietyMeter, .speculation,
        .streak, .marathon, .weekendWarrior,
        .achievements, .bashLeaderboard, .mcpLeaderboard, .skillLeaderboard, .pluginPopularity,
        .contextDeaths, .wrongPath, .regretIndex, .skipList, .badDay, .codeImpact,
    ]
}

private struct ClaudePatternsTabContent: View {
    let cards: [ClaudePatternCard]

    private var grouped: [(category: String, cards: [ClaudePatternCard])] {
        let buckets: [(String, Set<ClaudePatternKind>)] = [
            ("Personality", [.chronotype, .modelMix, .hourProfile, .toolBias, .anxietyMeter, .speculation]),
            ("Streaks", [.streak, .marathon, .weekendWarrior]),
            ("Achievements", [.achievements, .bashLeaderboard, .mcpLeaderboard, .skillLeaderboard, .pluginPopularity]),
            ("Diagnostics", [.contextDeaths, .wrongPath, .regretIndex, .skipList, .badDay, .codeImpact]),
        ]
        return buckets.compactMap { name, kinds in
            let matching = self.cards
                .filter { kinds.contains($0.kind) }
                .sorted { $0.sortPriority > $1.sortPriority }
            return matching.isEmpty ? nil : (name, matching)
        }
    }

    var body: some View {
        ForEach(self.grouped, id: \.category) { group in
            VStack(alignment: .leading, spacing: 8) {
                InlineSectionLabel(title: group.category)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(group.cards.enumerated()), id: \.element.id) { idx, card in
                        patternView(for: card)
                            .padding(.vertical, card.kind.tier == .hero ? 10 : (card.kind.tier == .compact ? 4 : 6))
                        if idx < group.cards.count - 1 {
                            Divider().background(DesignSystem.Colors.stroke.opacity(0.4))
                        }
                    }
                }
            }
        }
    }
}

private struct CodexPatternsTabContent: View {
    let session: CodexSessionStats

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            InlineSectionLabel(title: "Telemetry")
            CodexTelemetryCard(session: self.session)
            if !self.session.flightEvents.isEmpty {
                InlineSectionLabel(title: "Flight Recorder")
                CodexFlightRecorderCard(session: self.session)
            }
        }
    }
}

// MARK: - Pattern card tier system
//
// Three visual tiers for the 38 pattern card kinds:
//   .hero     — narrative cards that deserve room (chronotype, monthlyWrap, etc.)
//   .standard — data cards with explanatory body
//   .compact  — single-line summaries (leaderboards)

private enum PatternTier { case hero, standard, compact }

extension ClaudePatternKind {
    fileprivate var tier: PatternTier {
        switch self {
        case .chronotype, .burnstarSign, .monthlyWrap, .mostExpensiveTurn,
             .anniversary, .firstPromptEver, .pastedNovel, .wrap:
            return .hero
        case .bashLeaderboard, .mcpLeaderboard, .skillLeaderboard,
             .pluginPopularity, .achievements:
            return .compact
        default:
            return .standard
        }
    }
}

@ViewBuilder
private func patternView(for card: ClaudePatternCard) -> some View {
    switch card.kind.tier {
    case .hero:
        HeroPatternRow(card: card)
    case .standard:
        PatternRow(card: card)
    case .compact:
        CompactPatternRow(card: card)
    }
}

private struct PatternRow: View {
    let card: ClaudePatternCard

    private var tone: UsageTone { UsageTone(patternTone: self.card.tone) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(self.card.title)
                    .font(.geist(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                if let highlight = self.card.highlightValue {
                    Text(highlight)
                        .font(.geistMono(size: 13, weight: .semibold))
                        .foregroundStyle(self.tone == .tight ? DesignSystem.Colors.warning : DesignSystem.Colors.brandLavender)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            Text(self.card.body)
                .font(.geist(size: 10))
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let progress = self.card.progressPercent {
                MeterBar(tone: self.tone, usedPercent: progress)
                    .padding(.top, 1)
            }
            if let foot = self.card.footnote {
                Text(foot)
                    .font(.geist(size: 9, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    .lineLimit(1)
            }
        }
    }
}

private struct HeroPatternRow: View {
    let card: ClaudePatternCard

    private var tone: UsageTone { UsageTone(patternTone: self.card.tone) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Wide leading accent rail — full hero column height
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(DesignSystem.Colors.brandLavender)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 8) {
                if let highlight = self.card.highlightValue {
                    Text(highlight)
                        .font(.geist(size: 26, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.brandLavender)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                }
                Text(self.card.title)
                    .font(.geist(size: 16, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(self.card.body)
                    .font(.geist(size: 11))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                if let progress = self.card.progressPercent {
                    MeterBar(tone: self.tone, usedPercent: progress)
                        .padding(.top, 2)
                }
                if let foot = self.card.footnote {
                    Text(foot)
                        .font(.geist(size: 9, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
        .background {
            // Soft purple wash that tells the eye "this one is special"
            LinearGradient(
                colors: [
                    DesignSystem.Colors.brandLavender.opacity(0.10),
                    DesignSystem.Colors.brandLavender.opacity(0.0),
                ],
                startPoint: .leading,
                endPoint: .trailing)
        }
    }
}

private struct CompactPatternRow: View {
    let card: ClaudePatternCard

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(DesignSystem.Colors.brandLavender.opacity(0.7))
                .frame(width: 4, height: 4)
            Text(self.card.title)
                .font(.geist(size: 11, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .lineLimit(1)
            Text("·")
                .font(.geist(size: 10))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
            Text(self.card.body)
                .font(.geist(size: 10))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            if let highlight = self.card.highlightValue {
                Text(highlight)
                    .font(.geistMono(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.brandLavender)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
    }
}

private struct PatternsEmpty: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 22))
                .foregroundStyle(DesignSystem.Colors.brandLavender)
            Text("Patterns coming soon for this source")
                .font(.geist(size: 12, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.primaryText)
            Text("Claude Code has the heavier of the two right now. Codex parity in progress.")
                .font(.geist(size: 10))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - Wrap tab

struct WrapView: View {
    let snapshot: ProviderUsageSnapshot

    static let wrapTabKinds: Set<ClaudePatternKind> = [
        .wrap, .monthlyWrap, .firstPromptEver, .mostExpensiveTurn, .pastedNovel,
        .anniversary, .codenameCollector, .burnstarSign, .betaTimeline,
        .cacheSavings, .costPerCommit, .projectLeaderboard, .thinkingSpend,
        .apiEquivalent, .overage, .overageForecast, .overageReceipts, .idleReclaim,
    ]

    static let featureKinds: Set<ClaudePatternKind> = [
        .wrap, .monthlyWrap, .firstPromptEver, .mostExpensiveTurn, .anniversary, .burnstarSign,
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if self.snapshot.kind == .claude {
                    if let aggregate = self.snapshot.claudeAggregate {
                        WrapAggregateStrip(aggregate: aggregate)

                        CostSection(aggregate: aggregate, today: self.snapshot.today)

                        if !aggregate.recentDayTokens.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    InlineSectionLabel(title: "Last 30 days")
                                    Spacer()
                                    if let total = self.totalRecentTokens(aggregate: aggregate) {
                                        Text("\(DisplayText.compact(total)) tokens")
                                            .font(.geistMono(size: 10))
                                            .foregroundStyle(DesignSystem.Colors.tertiaryText)
                                    }
                                }
                                ClaudeSparkline(values: aggregate.recentDayTokens.map { $0.totalTokens })
                                    .frame(height: 56)
                            }
                        }
                    }

                    if let memory = self.snapshot.claudeMemory {
                        VStack(alignment: .leading, spacing: 8) {
                            InlineSectionLabel(title: "Project Memory")
                            ProjectMemoryRow(memory: memory)
                        }
                    }

                    let cards = self.snapshot.patternCards
                        .filter { Self.wrapTabKinds.contains($0.kind) }
                        .sorted { $0.sortPriority > $1.sortPriority }
                    let featureCards = cards.filter { Self.featureKinds.contains($0.kind) }
                    let secondaryCards = cards.filter { !Self.featureKinds.contains($0.kind) }

                    if !featureCards.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            InlineSectionLabel(title: "Highlights")
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(featureCards.enumerated()), id: \.element.id) { idx, card in
                                    patternView(for: card)
                                        .padding(.vertical, card.kind.tier == .hero ? 10 : 6)
                                    if idx < featureCards.count - 1 {
                                        Divider().background(DesignSystem.Colors.stroke.opacity(0.4))
                                    }
                                }
                            }
                        }
                    }

                    if !secondaryCards.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            InlineSectionLabel(title: "History")
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(secondaryCards.enumerated()), id: \.element.id) { idx, card in
                                    patternView(for: card)
                                        .padding(.vertical, card.kind.tier == .compact ? 4 : 6)
                                    if idx < secondaryCards.count - 1 {
                                        Divider().background(DesignSystem.Colors.stroke.opacity(0.4))
                                    }
                                }
                            }
                        }
                    }
                } else if self.snapshot.kind == .codex {
                    CodexWrapNativeView(snapshot: self.snapshot)
                } else {
                    EmptyWrapView()
                }
            }
            .padding(.leading, DesignSystem.Layout.contentPadding)
            .padding(.trailing, DesignSystem.Layout.contentPadding)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
    }

    private func totalRecentTokens(aggregate: ClaudeAggregateStats) -> Int? {
        let v = aggregate.recentDayTokens.map(\.totalTokens).reduce(0, +)
        return v > 0 ? v : nil
    }
}

private struct ProjectMemoryRow: View {
    let memory: CodexProjectMemory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(self.memory.projectName)
                    .font(.geist(size: 13, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(self.burnMultiple)
                    .font(.geistMono(size: 14, weight: .semibold))
                    .foregroundStyle(self.burnTone)
                    .layoutPriority(1)
            }

            HStack(spacing: 0) {
                BigStat(value: "\(self.memory.sessionCount)", label: "sessions")
                BigStatPipe()
                BigStat(value: DisplayText.compact(self.memory.averageTurnTokens), label: "avg turn")
                BigStatPipe()
                BigStat(value: DisplayText.compact(self.memory.heaviestSessionTokens), label: "heaviest")
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Text(self.burnDetail)
                    .font(.geist(size: 9))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                Spacer()
                if let updated = self.memory.lastUpdatedAt {
                    Text("last \(DisplayText.relative(updated))")
                        .font(.geist(size: 9))
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                }
            }
        }
    }

    private var burnMultiple: String {
        String(format: "%.1fx", self.memory.relativeBurnMultiple)
    }

    private var burnTone: Color {
        if self.memory.relativeBurnMultiple >= 1.5 { return DesignSystem.Colors.warning }
        if self.memory.relativeBurnMultiple <= 0.75 { return DesignSystem.Colors.success }
        return DesignSystem.Colors.brandLavender
    }

    private var burnDetail: String {
        if self.memory.relativeBurnMultiple >= 1.5 { return "above your normal burn" }
        if self.memory.relativeBurnMultiple <= 0.75 { return "below your normal burn" }
        return "at your normal burn"
    }
}

private struct CostSection: View {
    let aggregate: ClaudeAggregateStats
    let today: DailyUsageStats

    private var lifetimeTokens: Int {
        self.aggregate.lifetimeInputTokens + self.aggregate.lifetimeOutputTokens
            + self.aggregate.lifetimeCacheReadTokens + self.aggregate.lifetimeCacheCreationTokens
    }

    /// Today's per-token rate uses the SAME model mix as the last-30-days
    /// computation so today's estimate stays consistent with the more accurate
    /// 30-day number. Falls back to lifetime-blended only if no recent data.
    private var todayRatePerToken: Double {
        let recentTokens = self.aggregate.lastThirtyDayTokens
        let recentCost = self.aggregate.lastThirtyDayCostUSD
        if recentTokens > 0, recentCost > 0 {
            return recentCost / Double(recentTokens)
        }
        return self.aggregate.lifetimeSyntheticCostUSD / Double(max(1, self.lifetimeTokens))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InlineSectionLabel(title: "Cost")
            VStack(alignment: .leading, spacing: 0) {
                CostRow(
                    period: "Today",
                    cost: Double(self.today.totalTokens) * self.todayRatePerToken,
                    tokens: self.today.totalTokens)
                    .padding(.vertical, 6)
                Divider().background(DesignSystem.Colors.stroke.opacity(0.4))
                CostRow(
                    period: "Last 30 days",
                    cost: self.aggregate.lastThirtyDayCostUSD,
                    tokens: self.aggregate.lastThirtyDayTokens)
                    .padding(.vertical, 6)
                Divider().background(DesignSystem.Colors.stroke.opacity(0.4))
                CostRow(
                    period: "Lifetime",
                    cost: self.aggregate.lifetimeSyntheticCostUSD,
                    tokens: self.lifetimeTokens)
                    .padding(.vertical, 6)
            }
        }
    }
}

private struct CostRow: View {
    let period: String
    let cost: Double
    let tokens: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(self.period)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.secondaryText)
            Spacer(minLength: 6)
            Text(self.costLabel)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.brandLavender)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.5), value: self.cost)
            Text("·")
                .font(.system(size: 11))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
            Text("\(DisplayText.compact(self.tokens)) tokens")
                .font(.system(size: 10))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
        }
    }

    private var costLabel: String {
        if self.cost == 0 { return "$0" }
        if self.cost >= 1_000 { return String(format: "$%.1fk", self.cost / 1_000) }
        if self.cost >= 100 { return String(format: "$%.0f", self.cost) }
        if self.cost >= 1 { return String(format: "$%.2f", self.cost) }
        return String(format: "$%.3f", self.cost)
    }
}

private struct WrapAggregateStrip: View {
    let aggregate: ClaudeAggregateStats

    var body: some View {
        HStack(spacing: 0) {
            BigStat(value: aggregate.daysSinceFirstSession.map { "\($0)" } ?? "—", label: "day")
            BigStatPipe()
            BigStat(value: "\(aggregate.streakDays)d", label: "streak")
            BigStatPipe()
            BigStat(value: aggregate.totalSessions.formatted(), label: "sessions")
            BigStatPipe()
            BigStat(value: self.longestLabel, label: "longest")
            Spacer(minLength: 0)
        }
    }

    private var longestLabel: String {
        let m = aggregate.longestSessionMinutes
        if m >= 1440 {
            let d = m / 1440
            let hr = (m % 1440) / 60
            return hr == 0 ? "\(d)d" : "\(d)d \(hr)h"
        }
        if m >= 60 {
            let h = m / 60
            let min = m % 60
            return min == 0 ? "\(h)h" : "\(h)h \(min)m"
        }
        return "\(m)m"
    }
}

private struct WrapFeatureRow: View {
    let card: ClaudePatternCard

    private var tone: UsageTone { UsageTone(patternTone: self.card.tone) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(self.card.title)
                    .font(.geist(size: 13, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                if let highlight = self.card.highlightValue {
                    Text(highlight)
                        .font(.geistMono(size: 16, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.brandLavender)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            Text(self.card.body)
                .font(.geist(size: 10))
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let foot = self.card.footnote {
                Text(foot)
                    .font(.geist(size: 9, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
            }
        }
    }
}

private struct SubsectionHeaderInline: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(self.title.uppercased())
                .font(.geist(size: 10, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .tracking(0.8)
            Text("\(self.count)")
                .font(.geistMono(size: 9))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .padding(.horizontal, 5)
                .frame(height: 14)
                .background(Color.white.opacity(0.06), in: Capsule())
            Spacer()
        }
        .padding(.top, 4)
    }
}

private struct WrapFeatureCard: View {
    let card: ClaudePatternCard

    private var tone: UsageTone { UsageTone(patternTone: self.card.tone) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(self.card.title)
                    .font(.geist(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                if let highlight = self.card.highlightValue {
                    Text(highlight)
                        .font(.geistMono(size: 18, weight: .semibold))
                        .foregroundStyle(self.tone.color)
                        .lineLimit(1)
                }
            }
            Text(self.card.body)
                .font(.geist(size: 11))
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            if let progress = self.card.progressPercent {
                MeterBar(tone: self.tone, usedPercent: progress)
            }
            if let foot = self.card.footnote {
                Text(foot)
                    .font(.geist(size: 9, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
            }
        }
        .padding(DesignSystem.Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brandGlass(cornerRadius: DesignSystem.Layout.cardRadius, tint: self.tone.color.opacity(0.10))
    }
}

private struct PatternGridCellWrap: View {
    let card: ClaudePatternCard

    private var tone: UsageTone { UsageTone(patternTone: self.card.tone) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(self.card.title)
                    .font(.geist(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if let highlight = self.card.highlightValue {
                    Text(highlight)
                        .font(.geistMono(size: 13, weight: .semibold))
                        .foregroundStyle(self.tone.color)
                        .lineLimit(1)
                }
            }
            Text(self.card.body)
                .font(.geist(size: 10))
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let foot = self.card.footnote {
                Text(foot)
                    .font(.geist(size: 9, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .brandGlass(cornerRadius: 10)
    }
}

private struct EmptyWrapView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 22))
                .foregroundStyle(DesignSystem.Colors.brandLavender)
            Text("No wrap yet")
                .font(.geist(size: 12, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.primaryText)
            Text("Use Claude Code or Codex for a few days and the wrap fills out.")
                .font(.geist(size: 10))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - Health tab

struct HealthView: View {
    let snapshot: ProviderUsageSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if self.snapshot.kind == .claude {
                    if !self.snapshot.healthIndicators.isEmpty {
                        SystemPillsRow(indicators: self.snapshot.healthIndicators)
                    }

                    if let breakdown = self.snapshot.claudeTodayBreakdown {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                InlineSectionLabel(title: "Today")
                                Spacer()
                                Text("\(self.snapshot.today.requests) turns · \(DisplayText.compact(self.snapshot.today.totalTokens)) tokens · \(DisplayText.minutes(self.snapshot.today.activeMinutes))")
                                    .font(.geistMono(size: 9))
                                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                                    .lineLimit(1)
                            }
                            FlatTodayBreakdown(today: self.snapshot.today, breakdown: breakdown)
                        }
                    }

                    if let session = self.snapshot.claudeSession, !session.toolHistogram.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            InlineSectionLabel(title: "Tools this session")
                            FlatToolHistogram(session: session)
                        }
                    }
                } else if self.snapshot.kind == .codex {
                    CodexHealthNativeView(snapshot: self.snapshot)
                }
            }
            .padding(.leading, DesignSystem.Layout.contentPadding)
            .padding(.trailing, DesignSystem.Layout.contentPadding)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Flat Today breakdown (replaces ClaudeTodayRichCard's chrome)

private struct FlatTodayBreakdown: View {
    let today: DailyUsageStats
    let breakdown: ClaudeTodayBreakdown

    private var currentHour: Int { Calendar.current.component(.hour, from: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ClaudeHourlySparkline(hours: breakdown.hourBuckets, currentHour: currentHour)
                .frame(height: 68)

            HStack {
                Text("00")
                Spacer()
                Text("06")
                Spacer()
                Text("12")
                Spacer()
                Text("18")
                Spacer()
                Text("now")
            }
            .font(.geistMono(size: 9))
            .foregroundStyle(DesignSystem.Colors.tertiaryText)

            if !breakdown.languages.isEmpty {
                let total = max(1, breakdown.languages.reduce(0) { $0 + $1.count })
                HStack(spacing: 6) {
                    ForEach(breakdown.languages.prefix(4)) { lang in
                        let pct = Int(Double(lang.count) / Double(total) * 100)
                        LanguagePill(name: lang.name, percent: pct)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }

            if breakdown.linesAdded + breakdown.linesRemoved > 0 || breakdown.gitCommits > 0 {
                HStack(spacing: 14) {
                    if breakdown.gitCommits > 0 {
                        FlatTodayChip(symbol: "checkmark.seal", text: "\(breakdown.gitCommits) commits")
                    }
                    if breakdown.linesAdded > 0 {
                        FlatTodayChip(symbol: "plus.circle", text: "+\(DisplayText.compact(breakdown.linesAdded))")
                    }
                    if breakdown.linesRemoved > 0 {
                        FlatTodayChip(symbol: "minus.circle", text: "−\(DisplayText.compact(breakdown.linesRemoved))")
                    }
                    if breakdown.filesModified > 0 {
                        FlatTodayChip(symbol: "doc.text", text: "\(breakdown.filesModified) files")
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
        }
    }
}

private struct LanguagePill: View {
    let name: String
    let percent: Int

    private var color: Color {
        switch self.name.lowercased() {
        case "swift": Color(red: 0.99, green: 0.45, blue: 0.27)
        case "typescript": Color(red: 0.32, green: 0.55, blue: 0.92)
        case "javascript": Color(red: 0.94, green: 0.84, blue: 0.27)
        case "python": Color(red: 0.30, green: 0.62, blue: 0.85)
        case "rust": Color(red: 0.84, green: 0.42, blue: 0.20)
        case "go": Color(red: 0.20, green: 0.78, blue: 0.92)
        case "ruby": Color(red: 0.86, green: 0.32, blue: 0.32)
        case "css": Color(red: 0.45, green: 0.62, blue: 0.92)
        case "html": Color(red: 0.92, green: 0.40, blue: 0.20)
        case "markdown", "md": Color(red: 0.62, green: 0.62, blue: 0.72)
        case "json": Color(red: 0.78, green: 0.56, blue: 0.30)
        case "shell", "bash", "sh": Color(red: 0.50, green: 0.84, blue: 0.66)
        default: DesignSystem.Colors.brandLavender
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(self.color)
                .frame(width: 6, height: 6)
            Text("\(self.name) \(self.percent)%")
                .font(.geist(size: 10, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(self.color.opacity(0.13))
                .overlay {
                    Capsule().stroke(self.color.opacity(0.30), lineWidth: 0.6)
                }
        }
    }
}

private struct FlatTodayChip: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: self.symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.brandLavender)
            Text(self.text)
                .font(.geist(size: 10, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .lineLimit(1)
        }
    }
}

// MARK: - System pills (top of Health tab)

private struct SystemPillsRow: View {
    let indicators: [ClaudeHealthIndicator]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(self.indicators.prefix(3)) { indicator in
                SystemPill(indicator: indicator)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct SystemPill: View {
    let indicator: ClaudeHealthIndicator

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(self.color)
                .frame(width: 6, height: 6)
            Text(self.indicator.label)
                .font(.geist(size: 10, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .lineLimit(1)
            Text(self.indicator.detail)
                .font(.geist(size: 10))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(self.color.opacity(0.13))
                .overlay {
                    Capsule().stroke(self.color.opacity(0.32), lineWidth: 0.6)
                }
        }
    }

    private var color: Color {
        switch self.indicator.status {
        case .ok: DesignSystem.Colors.success
        case .warn: DesignSystem.Colors.warning
        case .error: DesignSystem.Colors.danger
        case .unknown: DesignSystem.Colors.tertiaryText
        }
    }
}

// MARK: - Flat health indicator rows

private struct FlatHealthRows: View {
    let indicators: [ClaudeHealthIndicator]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(self.indicators.enumerated()), id: \.element.id) { idx, indicator in
                HStack(spacing: 9) {
                    Circle()
                        .fill(self.color(for: indicator.status))
                        .frame(width: 7, height: 7)
                    Text(indicator.label)
                        .font(.geist(size: 12, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                    Spacer()
                    Text(indicator.detail)
                        .font(.geist(size: 11))
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.vertical, 7)
                if idx < self.indicators.count - 1 {
                    Divider().background(DesignSystem.Colors.stroke.opacity(0.4))
                }
            }
        }
    }

    private func color(for status: ClaudeHealthStatus) -> Color {
        switch status {
        case .ok: DesignSystem.Colors.success
        case .warn: DesignSystem.Colors.warning
        case .error: DesignSystem.Colors.danger
        case .unknown: DesignSystem.Colors.tertiaryText
        }
    }
}

// MARK: - Flat tool histogram

private struct FlatToolHistogram: View {
    let session: ClaudeSessionStats

    private var topTools: [ClaudeToolCount] {
        Array(self.session.toolHistogram.sorted { $0.count > $1.count }.prefix(6))
    }

    private var maxCount: Int {
        max(1, self.topTools.first?.count ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(self.topTools) { tool in
                HStack(spacing: 9) {
                    Text(tool.name)
                        .font(.geist(size: 11, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                        .frame(width: 80, alignment: .leading)
                        .lineLimit(1)
                    MeterBar(tone: .calm, usedPercent: Double(tool.count) / Double(self.maxCount) * 100)
                        .frame(maxWidth: .infinity)
                    Text("\(tool.count)")
                        .font(.geistMono(size: 11, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                        .frame(width: 32, alignment: .trailing)
                }
            }
        }
    }
}

private struct CodexHealthSummary: View {
    let session: CodexSessionStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Health")
                    .font(.geist(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                Spacer()
            }
            HStack(spacing: 6) {
                CodexHealthChip(
                    label: "Errors",
                    detail: "\(self.session.errors) this session",
                    tone: self.session.errors > 0 ? .tight : .calm)
                CodexHealthChip(
                    label: "Tools",
                    detail: "\(self.session.toolCalls) calls",
                    tone: .calm)
                CodexHealthChip(
                    label: "Compactions",
                    detail: "\(self.session.compactions) compacted",
                    tone: self.session.compactions > 2 ? .watch : .calm)
                CodexHealthChip(
                    label: "Activity",
                    detail: self.activityLabel,
                    tone: self.activityTone)
            }
        }
        .padding(DesignSystem.Layout.cardPadding)
        .brandGlass(cornerRadius: DesignSystem.Layout.cardRadius)
    }

    private var activityLabel: String {
        guard let last = self.session.lastActivityAt else { return "no activity" }
        let s = max(0, Int(Date().timeIntervalSince(last)))
        if s < 120 { return "live" }
        if s < 3_600 { return "\(s / 60)m idle" }
        return "\(s / 3_600)h idle"
    }

    private var activityTone: UsageTone {
        guard let last = self.session.lastActivityAt else { return .watch }
        let s = max(0, Int(Date().timeIntervalSince(last)))
        if s > 1_800 { return .watch }
        return .calm
    }
}

private struct CodexHealthChip: View {
    let label: String
    let detail: String
    let tone: UsageTone

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Circle()
                    .fill(self.tone.color)
                    .frame(width: 5, height: 5)
                Text(self.label.uppercased())
                    .font(.geist(size: 9, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)
            }
            Text(self.detail)
                .font(.geist(size: 9))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .brandGlassThin(cornerRadius: 7)
    }
}
