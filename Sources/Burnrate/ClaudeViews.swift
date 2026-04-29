import AppKit
import BurnrateCore
import Charts
import SwiftUI

// MARK: - Claude content stack
//
// Catalogue mode: every component renders in-place with a small label above it
// so the user can reference each one by ID/name when picking what stays.

struct ClaudeContentStack: View {
    let snapshot: ProviderUsageSnapshot

    var body: some View {
        VStack(spacing: 14) {
            if let session = snapshot.claudeSession {
                ClaudeTaskRibbon(session: session)
            }

            if let advisor = snapshot.claudeSession?.advisor {
                ClaudeAdvisorCard(advisor: advisor, session: snapshot.claudeSession)
            }

            if let context = snapshot.workContext {
                ClaudeContextCard(context: context)
            }

            if let breakdown = snapshot.claudeTodayBreakdown {
                ClaudeTodayRichCard(today: snapshot.today, breakdown: breakdown)
            }

            if let aggregate = snapshot.claudeAggregate {
                ClaudeAggregateCard(aggregate: aggregate)

                if !aggregate.recentDayTokens.isEmpty {
                    ClaudeSparklineCard(aggregate: aggregate)
                }
            }

            if let session = snapshot.claudeSession, !session.toolHistogram.isEmpty {
                ClaudeToolHistogramCard(session: session)
            }

            if !snapshot.healthIndicators.isEmpty {
                ClaudeHealthRow(indicators: snapshot.healthIndicators)
            }

            if !snapshot.patternCards.isEmpty {
                ClaudePatternsCatalogue(cards: snapshot.patternCards)
            }
        }
    }
}

// MARK: - Patterns catalogue (all cards stacked vertically with numbered labels)

struct ClaudePatternsCatalogue: View {
    let cards: [ClaudePatternCard]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(cards) { card in
                ClaudePatternCardView(card: card)
                    .padding(12)
                    .premiumCard(accent: self.toneColor(card.tone), includeGlow: false)
            }
        }
    }

    private func toneColor(_ tone: ClaudePatternTone) -> Color {
        switch tone {
        case .positive: return DesignSystem.Colors.success
        case .neutral: return DesignSystem.Colors.warning
        case .caution: return DesignSystem.Colors.danger
        }
    }
}

// MARK: - Single pattern card (used both in catalogue and the (legacy) deck)

struct ClaudePatternCardView: View {
    let card: ClaudePatternCard

    private var tone: UsageTone {
        UsageTone(patternTone: card.tone)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if let highlight = card.highlightValue {
                    Text(highlight)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(self.tone.color)
                        .monospacedDigit()
                }
            }
            Text(card.body)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            if let progress = card.progressPercent {
                MeterBar(tone: self.tone, usedPercent: progress)
            }
            if let foot = card.footnote {
                Text(foot.uppercased())
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Today rich card (hourly sparkline + languages + lines/commits)

struct ClaudeTodayRichCard: View {
    let today: DailyUsageStats
    let breakdown: ClaudeTodayBreakdown

    private var currentHour: Int { Calendar.current.component(.hour, from: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                Spacer()
                Text("\(today.requests) turns · \(DisplayText.compact(today.totalTokens)) tokens · \(DisplayText.minutes(today.activeMinutes))")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    .monospacedDigit()
            }

            ClaudeHourlySparkline(hours: breakdown.hourBuckets, currentHour: currentHour)
                .frame(height: 44)

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
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(DesignSystem.Colors.tertiaryText)

            if !breakdown.languages.isEmpty {
                let total = max(1, breakdown.languages.reduce(0) { $0 + $1.count })
                HStack(spacing: 4) {
                    ForEach(breakdown.languages.prefix(4)) { lang in
                        let pct = Int(Double(lang.count) / Double(total) * 100)
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Self.languageColor(lang.name))
                                .frame(width: 6, height: 6)
                            Text("\(lang.name) \(pct)%")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(DesignSystem.Colors.secondaryText)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .glassSurface(cornerRadius: 5, tint: Self.languageColor(lang.name).opacity(0.10))
                    }
                }
            }

            if breakdown.linesAdded + breakdown.linesRemoved > 0 || breakdown.gitCommits > 0 {
                HStack(spacing: 8) {
                    if breakdown.gitCommits > 0 {
                        ClaudeTodayChip(symbol: "checkmark.seal", text: "\(breakdown.gitCommits) commits", tint: DesignSystem.Colors.success)
                    }
                    if breakdown.linesAdded > 0 {
                        ClaudeTodayChip(symbol: "plus.circle", text: "+\(DisplayText.compact(breakdown.linesAdded))", tint: DesignSystem.Colors.success)
                    }
                    if breakdown.linesRemoved > 0 {
                        ClaudeTodayChip(symbol: "minus.circle", text: "−\(DisplayText.compact(breakdown.linesRemoved))", tint: DesignSystem.Colors.danger)
                    }
                    if breakdown.filesModified > 0 {
                        ClaudeTodayChip(symbol: "doc.text", text: "\(breakdown.filesModified) files", tint: DesignSystem.Colors.tertiaryText)
                    }
                    Spacer()
                }
            }
        }
        .padding(10)
        .premiumCard(accent: DesignSystem.Colors.accent(for: .claude), includeGlow: false)
    }

    private static func languageColor(_ name: String) -> Color {
        switch name.lowercased() {
        case "swift": return Color(red: 0.99, green: 0.45, blue: 0.27)
        case "typescript": return Color(red: 0.19, green: 0.46, blue: 0.78)
        case "javascript": return Color(red: 0.94, green: 0.84, blue: 0.27)
        case "python": return Color(red: 0.21, green: 0.49, blue: 0.74)
        case "rust": return Color(red: 0.84, green: 0.42, blue: 0.20)
        case "go": return Color(red: 0.00, green: 0.69, blue: 0.83)
        case "ruby": return Color(red: 0.78, green: 0.16, blue: 0.18)
        case "css": return Color(red: 0.34, green: 0.50, blue: 0.78)
        case "html": return Color(red: 0.89, green: 0.31, blue: 0.16)
        case "markdown": return Color(red: 0.40, green: 0.40, blue: 0.45)
        case "json": return Color(red: 0.15, green: 0.61, blue: 0.85)
        case "yaml": return Color(red: 0.80, green: 0.27, blue: 0.27)
        case "shell", "bash", "zsh": return Color(red: 0.46, green: 0.55, blue: 0.61)
        default: return DesignSystem.Colors.accent(for: .claude)
        }
    }
}

struct ClaudeHourlySparkline: View {
    let hours: [Int]
    let currentHour: Int

    private struct HourBucket: Identifiable {
        let id: Int
        let count: Int
        let kind: HourKind
    }

    private enum HourKind { case past, current, future, zero }

    private var buckets: [HourBucket] {
        (0..<24).map { idx in
            let count = idx < self.hours.count ? self.hours[idx] : 0
            let kind: HourKind
            if count == 0 { kind = .zero }
            else if idx == self.currentHour { kind = .current }
            else if idx < self.currentHour { kind = .past }
            else { kind = .future }
            return HourBucket(id: idx, count: count, kind: kind)
        }
    }

    var body: some View {
        let peak = max(1, self.hours.max() ?? 1)
        Chart(self.buckets) { bucket in
            BarMark(
                x: .value("Hour", bucket.id),
                y: .value("Activity", bucket.count),
                width: .fixed(9))
                .foregroundStyle(self.color(for: bucket.kind))
                .cornerRadius(2)
                .accessibilityLabel("Hour \(bucket.id)")
                .accessibilityValue("\(bucket.count) requests")
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...Double(peak))
        .chartLegend(.hidden)
    }

    private func color(for kind: HourKind) -> Color {
        switch kind {
        case .current: return DesignSystem.Colors.brandLavender
        case .past: return DesignSystem.Colors.brandLavender.opacity(0.55)
        case .future: return Color.white.opacity(0.20)
        case .zero: return Color.white.opacity(0.10)
        }
    }
}

private struct ClaudeTodayChip: View {
    let symbol: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: self.symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(self.tint)
            Text(self.text)
                .font(DesignSystem.Typography.number)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .monospacedDigit()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .glassSurface(cornerRadius: 5, tint: self.tint.opacity(0.10))
    }
}

// MARK: - Task ribbon

struct ClaudeTaskRibbon: View {
    let session: ClaudeSessionStats

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: self.glyph)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(self.accent)
                .frame(width: 22, height: 22)
                .glassSurface(cornerRadius: 6, tint: self.accent.opacity(0.10))

            VStack(alignment: .leading, spacing: 2) {
                Text(self.headline)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                    .lineLimit(1)
                Text(self.detail)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let durationMs = session.lastTurnDurationMs {
                Text("\(durationMs / 1000)s")
                    .font(DesignSystem.Typography.number)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .glassSurface(cornerRadius: 8, tint: .white.opacity(0.04))
    }

    private var glyph: String {
        guard let last = session.activeTaskChain.last else { return "sparkle" }
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

    private var accent: Color {
        DesignSystem.Colors.accent(for: .claude)
    }

    private var headline: String {
        if let title = session.activeTaskTitle, !title.isEmpty { return title }
        if let title = session.threadTitle, !title.isEmpty { return title }
        return "Claude is working"
    }

    private var detail: String {
        let chain = session.activeTaskChain.suffix(4)
        let chainStr = chain.isEmpty ? "" : "chain " + chain.joined(separator: " → ")
        let parts: [String] = [
            "turn \(session.assistantMessageCount)",
            chainStr,
            session.gitBranch.map { "branch \($0)" } ?? "",
        ].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Advisor card

struct ClaudeAdvisorCard: View {
    let advisor: ClaudeAdvisor
    let session: ClaudeSessionStats?

    private var tone: UsageTone {
        UsageTone(health: self.advisor.health)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: self.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(self.tone.color)
                    .frame(width: 24, height: 24)
                    .glassSurface(cornerRadius: 7, tint: self.tone.color.opacity(0.08))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(self.advisor.health.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.primaryText)
                            .lineLimit(1)
                        Text("Claude advisor")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.tertiaryText)
                            .padding(.horizontal, 6)
                            .frame(height: 17)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }

                    Text(self.advisor.recommendation)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
            }

            HStack(spacing: 6) {
                ClaudeMiniMetric(title: "Why", value: self.advisor.primaryDriver, detail: self.advisor.driverDetail)
                ClaudeMiniMetric(title: "Forecast", value: self.advisor.forecast, detail: self.advisor.resetPlan)
            }

            HStack(spacing: 6) {
                ClaudeMeterMetric(
                    title: "New ctx",
                    value: DisplayText.contextShare(self.advisor.lastTurnSharePercent),
                    percent: self.advisor.lastTurnSharePercent,
                    tone: self.tone)
                if let usd = self.advisor.usdPerMinute, usd > 0 {
                    ClaudeMeterMetric(
                        title: "$/min",
                        value: String(format: "$%.2f", usd),
                        percent: min(100, usd / 0.50 * 100),
                        tone: usd > 0.30 ? .tight : (usd > 0.15 ? .watch : .calm))
                } else {
                    ClaudeMeterMetric(
                        title: "Burn/min",
                        value: DisplayText.compact(self.advisor.tokensPerMinute),
                        percent: min(100, Double(self.advisor.tokensPerMinute) / 1_200 * 100),
                        tone: self.tone)
                }
                if let cacheRead = session?.cacheReadInputTokens, cacheRead > 0 {
                    ClaudeMeterMetric(
                        title: "Cache",
                        value: "\(Int(session!.cacheSharePercent.rounded()))%",
                        percent: session!.cacheSharePercent,
                        tone: .calm)
                }
            }
        }
        .padding(10)
        .premiumCard(accent: self.tone.color, includeGlow: true)
    }

    private var iconName: String {
        switch advisor.health {
        case .efficient: "bolt.badge.checkmark"
        case .healthy: "checkmark.seal"
        case .watch: "eye"
        case .tight: "exclamationmark.triangle"
        case .stuck: "wrench.and.screwdriver"
        }
    }
}

private struct ClaudeMiniMetric: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(self.title.uppercased())
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
            Text(self.value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(self.detail)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(minHeight: 56, alignment: .topLeading)
        .glassSurface(cornerRadius: 7, tint: .white.opacity(0.035))
    }
}

private struct ClaudeMeterMetric: View {
    let title: String
    let value: String
    let percent: Double
    let tone: UsageTone

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(self.title.uppercased())
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                Spacer()
                Text(self.value)
                    .font(DesignSystem.Typography.number)
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                    .monospacedDigit()
            }
            MeterBar(tone: self.tone, usedPercent: self.percent)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .glassSurface(cornerRadius: 7, tint: .white.opacity(0.032))
    }
}

// MARK: - Context card (Claude flavour)

struct ClaudeContextCard: View {
    let context: WorkContextSnapshot

    private var tone: UsageTone {
        UsageTone(percent: self.context.contextUsedPercent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Context")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    Text(self.directory)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                        .lineLimit(1)
                    if let model = context.modelName {
                        Text(model)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(context.contextRemainingPercent.rounded()))%")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                        .monospacedDigit()
                    Text("left")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(self.tone.color)
                }
            }

            MeterBar(tone: self.tone, usedPercent: self.context.contextUsedPercent)

            HStack {
                Text("\(DisplayText.compact(self.context.contextUsedTokens)) / \(DisplayText.compact(self.context.contextWindowTokens)) used")
                Spacer()
                Text(DisplayText.relative(self.context.updatedAt))
            }
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Colors.tertiaryText)
        }
        .padding(12)
        .premiumCard(accent: self.tone.color, includeGlow: false)
    }

    private var directory: String {
        guard let dir = context.directory else { return "Claude session" }
        return URL(fileURLWithPath: dir).lastPathComponent
    }
}

// MARK: - Aggregate card (Day N · streak · longest)

struct ClaudeAggregateCard: View {
    let aggregate: ClaudeAggregateStats

    var body: some View {
        HStack(spacing: 0) {
            ClaudeStatColumn(
                title: "Day",
                value: aggregate.daysSinceFirstSession.map { "\($0)" } ?? "—",
                detail: "of using Claude")
            ClaudeStatDivider()
            ClaudeStatColumn(
                title: "Streak",
                value: "\(aggregate.streakDays)d",
                detail: "in a row")
            ClaudeStatDivider()
            ClaudeStatColumn(
                title: "Sessions",
                value: aggregate.totalSessions.formatted(),
                detail: "lifetime")
            ClaudeStatDivider()
            ClaudeStatColumn(
                title: "Longest",
                value: self.longestLabel,
                detail: "personal best")
        }
        .padding(.vertical, 10)
        .premiumCard(accent: DesignSystem.Colors.accent(for: .claude), includeGlow: false)
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

private struct ClaudeStatColumn: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(spacing: 2) {
            Text(self.title.uppercased())
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
            Text(self.value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .monospacedDigit()
            Text(self.detail)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ClaudeStatDivider: View {
    var body: some View {
        Rectangle()
            .fill(DesignSystem.Colors.stroke)
            .frame(width: 1, height: 34)
    }
}

// MARK: - 30-day sparkline

struct ClaudeSparklineCard: View {
    let aggregate: ClaudeAggregateStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Last 30 days")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                Spacer()
                if let total = self.totalRecentTokens {
                    Text("\(DisplayText.compact(total)) tokens")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                        .monospacedDigit()
                }
            }
            ClaudeSparkline(values: aggregate.recentDayTokens.map { $0.totalTokens })
                .frame(height: 48)
        }
        .padding(10)
        .premiumCard(accent: DesignSystem.Colors.accent(for: .claude), includeGlow: false)
    }

    private var totalRecentTokens: Int? {
        let v = aggregate.recentDayTokens.map(\.totalTokens).reduce(0, +)
        return v > 0 ? v : nil
    }
}

struct ClaudeSparkline: View {
    let values: [Int]

    private struct DayBucket: Identifiable {
        let id: Int
        let value: Int
    }

    private var buckets: [DayBucket] {
        self.values.enumerated().map { idx, v in
            DayBucket(id: idx, value: v)
        }
    }

    var body: some View {
        let peakValue = max(1, self.values.max() ?? 1)
        let accent = DesignSystem.Colors.brandLavender
        Chart(self.buckets) { bucket in
            AreaMark(
                x: .value("Day", bucket.id),
                y: .value("Tokens", bucket.value))
                .foregroundStyle(
                    .linearGradient(
                        colors: [
                            accent.opacity(0.55),
                            accent.opacity(0.05),
                        ],
                        startPoint: .top,
                        endPoint: .bottom))
                .interpolationMethod(.catmullRom)
                .accessibilityLabel("Day \(bucket.id + 1)")
                .accessibilityValue("\(bucket.value) tokens")

            LineMark(
                x: .value("Day", bucket.id),
                y: .value("Tokens", bucket.value))
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXScale(domain: -0.5...(Double(self.values.count) - 0.5))
        .chartYScale(domain: 0...Double(peakValue))
    }
}

// MARK: - Patterns deck

// Kept for the browse-all sheet — not used inline (replaced by ClaudePatternsCatalogue).
struct ClaudePatternsDeck: View {
    let cards: [ClaudePatternCard]

    @State private var index: Int = 0
    @State private var paused: Bool = false
    @State private var browsing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Patterns")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                Spacer()
                Button {
                    self.browsing = true
                    self.paused = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Browse all")
                            .font(DesignSystem.Typography.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .padding(.trailing, 4)
                HStack(spacing: 4) {
                    Button(action: self.previous) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 16, height: 16)
                    Text("\(self.boundedIndex + 1)/\(cards.count)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                        .monospacedDigit()
                    Button(action: self.next) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 16, height: 16)
                }
                .foregroundStyle(DesignSystem.Colors.secondaryText)
            }

            ZStack {
                if cards.indices.contains(self.boundedIndex) {
                    ClaudePatternCardView(card: cards[self.boundedIndex])
                        .id(cards[self.boundedIndex].id)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(x: 16)),
                            removal: .opacity.combined(with: .offset(x: -16))))
                }
            }
            .animation(.easeOut(duration: 0.25), value: self.boundedIndex)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onTapGesture { self.paused.toggle() }
            .onHover { hovering in self.paused = hovering }

            HStack(spacing: 4) {
                ForEach(0..<cards.count, id: \.self) { i in
                    Circle()
                        .fill(i == self.boundedIndex ? DesignSystem.Colors.accent(for: .claude) : Color.white.opacity(0.18))
                        .frame(width: 5, height: 5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(10)
        .premiumCard(accent: DesignSystem.Colors.accent(for: .claude), includeGlow: false)
        .sheet(isPresented: self.$browsing) {
            ClaudePatternsBrowseSheet(cards: cards) {
                self.browsing = false
                self.paused = false
            }
        }
        .task(id: cards.count) {
            while !Task.isCancelled, !cards.isEmpty {
                try? await Task.sleep(for: .seconds(8))
                if !self.paused { self.next() }
            }
        }
    }

    private var boundedIndex: Int {
        guard !cards.isEmpty else { return 0 }
        return ((index % cards.count) + cards.count) % cards.count
    }

    private func next() {
        guard !cards.isEmpty else { return }
        self.index = (self.boundedIndex + 1) % cards.count
    }

    private func previous() {
        guard !cards.isEmpty else { return }
        self.index = (self.boundedIndex - 1 + cards.count) % cards.count
    }
}

struct ClaudePatternsBrowseSheet: View {
    let cards: [ClaudePatternCard]
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("All patterns")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                    Text("\(cards.count) cards · ranked by deviation from your baseline")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                }
                Spacer()
                Button {
                    self.onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider().overlay(DesignSystem.Colors.stroke)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(cards) { card in
                        ClaudePatternBrowseRow(card: card)
                    }
                }
                .padding(14)
            }
            .background(Color.black.opacity(0.18))
        }
        .frame(width: 460, height: 540)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [Color.white.opacity(0.05), Color.black.opacity(0.20)],
                    startPoint: .top,
                    endPoint: .bottom)
            }
        }
    }
}

private struct ClaudePatternBrowseRow: View {
    let card: ClaudePatternCard

    private var tone: UsageTone {
        UsageTone(patternTone: card.tone)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle()
                    .fill(self.tone.color)
                    .frame(width: 3)
            }
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(card.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                        .lineLimit(2)
                    Spacer()
                    if let highlight = card.highlightValue {
                        Text(highlight)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(self.tone.color)
                            .monospacedDigit()
                    }
                }
                Text(card.body)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let foot = card.footnote {
                    Text(foot.uppercased())
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassSurface(cornerRadius: 7, tint: self.tone.color.opacity(0.04))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(self.tone.color)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))
        }
    }
}

private struct ClaudePatternCardViewDeck: View {
    let card: ClaudePatternCard

    private var tone: UsageTone {
        UsageTone(patternTone: card.tone)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if let highlight = card.highlightValue {
                    Text(highlight)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(self.tone.color)
                        .monospacedDigit()
                }
            }
            Text(card.body)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let progress = card.progressPercent {
                MeterBar(tone: self.tone, usedPercent: progress)
            }
            if let foot = card.footnote {
                Text(foot.uppercased())
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Health row

struct ClaudeHealthRow: View {
    let indicators: [ClaudeHealthIndicator]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Health")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                Spacer()
            }
            HStack(spacing: 6) {
                ForEach(indicators) { indicator in
                    ClaudeHealthChip(indicator: indicator)
                }
            }
        }
        .padding(10)
        .premiumCard(accent: DesignSystem.Colors.accent(for: .claude), includeGlow: false)
    }
}

private struct ClaudeHealthChip: View {
    let indicator: ClaudeHealthIndicator

    private var tone: UsageTone { UsageTone(status: indicator.status) }

    private var glyph: String {
        switch indicator.status {
        case .ok: "checkmark"
        case .warn: "exclamationmark"
        case .error: "xmark"
        case .unknown: "questionmark"
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: self.glyph)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(self.tone.color)
                Text(indicator.label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)
            }
            Text(indicator.detail)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .glassSurface(cornerRadius: 7, tint: self.tone.color.opacity(0.05))
        .help(indicator.detail)
    }
}

// MARK: - Tool histogram card

struct ClaudeToolHistogramCard: View {
    let session: ClaudeSessionStats

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tools this session")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                Spacer()
                Text("\(session.toolCalls) total")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    .monospacedDigit()
            }

            VStack(spacing: 4) {
                ForEach(session.toolHistogram.prefix(5)) { tool in
                    ClaudeToolBar(name: tool.name, count: tool.count, total: session.toolCalls)
                }
            }
        }
        .padding(10)
        .premiumCard(accent: DesignSystem.Colors.accent(for: .claude), includeGlow: false)
    }
}

private struct ClaudeToolBar: View {
    let name: String
    let count: Int
    let total: Int

    private var pct: Double {
        guard total > 0 else { return 0 }
        return Double(count) / Double(total) * 100
    }

    var body: some View {
        HStack(spacing: 7) {
            Text(self.name)
                .font(DesignSystem.Typography.label)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .frame(width: 70, alignment: .leading)
                .lineLimit(1)
            MeterBar(tone: .calm, usedPercent: self.pct)
            Text("\(count)")
                .font(DesignSystem.Typography.number)
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
    }
}
