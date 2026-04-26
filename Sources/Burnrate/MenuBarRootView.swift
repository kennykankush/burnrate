import AppKit
import BurnrateCore
import SwiftUI

struct MenuBarRootView: View {
    @Bindable var model: MenuBarModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(model: self.model)

            Divider()
                .overlay(DesignSystem.Colors.stroke)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 10) {
                    if let snapshot = self.model.selectedSnapshot {
                        ProviderSwitch(selectedProvider: self.$model.selectedProvider, snapshots: self.model.overview.snapshots)
                        ProviderCard(snapshot: snapshot)

                        switch snapshot.kind {
                        case .codex:
                            if let insight = snapshot.codexSession?.insight {
                                CodexAdvisorCard(insight: insight)
                            }
                            if let memory = snapshot.codexMemory {
                                CodexMemoryCard(memory: memory)
                            }
                            if let context = snapshot.workContext {
                                WorkContextCard(context: context)
                            }
                            if let session = snapshot.codexSession {
                                CodexTelemetryCard(session: session)
                                if !session.flightEvents.isEmpty {
                                    CodexFlightRecorderCard(session: session)
                                }
                            }
                        case .claude:
                            ClaudeContentStack(snapshot: snapshot)
                        }

                        if snapshot.kind != .claude {
                            TodayCard(snapshot: snapshot)
                        }
                        MiniProviderRow(overview: self.model.overview)
                    } else {
                        EmptyStateView(isRefreshing: self.model.isRefreshing, error: self.model.lastError)
                    }
                }
                .padding(DesignSystem.Layout.contentPadding)
            }
            .frame(maxHeight: DesignSystem.Layout.scrollMaxHeight)

            Divider()
                .overlay(DesignSystem.Colors.stroke)

            FooterView(model: self.model)
        }
        .frame(width: DesignSystem.Layout.popoverWidth)
        .background {
            GlassBackdrop()
        }
    }
}

struct MenuBarLabel: View {
    let model: MenuBarModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform.path.ecg")
            Text(self.model.menuBarText)
                .font(.system(size: 11, weight: .medium, design: .default))
        }
    }
}

@MainActor
private struct HeaderView: View {
    @Bindable var model: MenuBarModel

    var body: some View {
        HStack(spacing: 9) {
            BrandMark(mark: .icon3D, size: 26)
                .shadow(color: Brand.Palette.deepPurple.opacity(0.45), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text("burnrate")
                    .font(DesignSystem.Typography.title)
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                Text(self.subtitle)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
            }

            Spacer()

            Button {
                Task { await self.model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(self.model.isRefreshing ? 360 : 0))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignSystem.Colors.secondaryText)
            .frame(width: 26, height: 26)
            .glassSurface(cornerRadius: 7, tint: .white.opacity(0.06))
            .animation(
                self.model.isRefreshing ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                value: self.model.isRefreshing)
            .disabled(self.model.isRefreshing)
            .help("Refresh")
        }
        .padding(.horizontal, DesignSystem.Layout.contentPadding)
        .padding(.vertical, 9)
    }

    private var subtitle: String {
        if self.model.isRefreshing { return "Refreshing usage" }
        if let error = self.model.lastError, !error.isEmpty { return "Needs attention" }
        return "Codex and Claude Code"
    }
}

private struct ProviderSwitch: View {
    @Binding var selectedProvider: ProviderKind
    let snapshots: [ProviderUsageSnapshot]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ProviderKind.allCases) { provider in
                let isSelected = self.selectedProvider == provider
                Button {
                    self.selectedProvider = provider
                } label: {
                    HStack(spacing: 5) {
                        ProviderMark(kind: provider, size: 12, renderingMode: .template)
                        Text(provider.displayName)
                            .font(DesignSystem.Typography.label)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: DesignSystem.Layout.controlHeight)
                    .foregroundStyle(isSelected ? DesignSystem.Colors.primaryText : DesignSystem.Colors.secondaryText)
                    .background(
                        isSelected ? Color.white.opacity(0.13) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(self.snapshots.isEmpty)
            }
        }
        .padding(3)
        .glassSurface(cornerRadius: 8, tint: .white.opacity(0.045))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DesignSystem.Colors.stroke.opacity(0.7))
        }
    }
}

private struct ProviderCard: View {
    let snapshot: ProviderUsageSnapshot

    private var tone: UsageTone {
        UsageTone(percent: self.snapshot.primaryUsedPercent)
    }

    var body: some View {
        VStack(spacing: 11) {
            HStack(alignment: .center, spacing: 10) {
                ProviderMark(kind: self.snapshot.kind, size: 22, renderingMode: .original)
                    .foregroundStyle(DesignSystem.Colors.accent(for: self.snapshot.kind))
                    .padding(7)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(DesignSystem.Colors.accent(for: self.snapshot.kind).opacity(0.14))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(DesignSystem.Colors.accent(for: self.snapshot.kind).opacity(0.32))
                    }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(self.snapshot.kind.displayName)
                            .font(.system(size: 16, weight: .semibold, design: .default))
                            .foregroundStyle(DesignSystem.Colors.primaryText)
                            .lineLimit(1)

                        if let plan = self.snapshot.planName {
                            Text(plan)
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.secondaryText)
                                .padding(.horizontal, 6)
                                .frame(height: 18)
                                .background(Color.white.opacity(0.11), in: Capsule())
                                .overlay {
                                    Capsule()
                                        .stroke(Color.white.opacity(0.13))
                                }
                        }
                    }

                    Text(self.subtitle)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(self.snapshot.primaryUsedPercent.rounded()))%")
                        .font(.system(size: 25, weight: .semibold, design: .default))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                        .monospacedDigit()
                    Text(self.primaryWindowLabel)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(self.tone.color)
                }
            }

            VStack(spacing: 9) {
                ForEach(self.snapshot.windows) { window in
                    CompactLimitRow(window: window, tone: UsageTone(percent: window.usedPercent))
                }
            }

            HStack(spacing: 7) {
                CompactMetric(title: self.requestTitle, value: "\(self.snapshot.today.requests)")
                CompactMetric(title: "Tokens", value: DisplayText.compact(self.snapshot.today.totalTokens))
                CompactMetric(title: self.thirdMetricTitle, value: self.thirdMetricValue)
            }
        }
        .padding(12)
        .premiumCard(accent: self.tone.color)
    }

    private var subtitle: String {
        let account = self.snapshot.accountLabel ?? "Local account"
        guard let project = self.snapshot.projectLabel else { return account }
        return "\(account) / \(project)"
    }

    private var primaryWindowLabel: String {
        guard let title = self.snapshot.primaryWindow?.title else { return self.tone.label }
        if title == "5h" { return "5h burst" }
        return title.lowercased()
    }

    private var requestTitle: String {
        self.snapshot.kind == .codex ? "Turns" : "Requests"
    }

    private var thirdMetricTitle: String {
        if self.snapshot.kind == .codex, self.snapshot.codexSession != nil { return "Cache" }
        return "Spend"
    }

    private var thirdMetricValue: String {
        if let session = self.snapshot.codexSession {
            return DisplayText.compact(session.cachedInputTokens)
        }
        return DisplayText.money(self.snapshot.today.spend?.used, currency: self.snapshot.today.spend?.currencyCode)
    }
}

private struct CompactLimitRow: View {
    let window: UsageWindow
    let tone: UsageTone

    var body: some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(self.window.title)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                Spacer()
                Text("\(Int(self.window.remainingPercent.rounded()))% left")
                    .font(DesignSystem.Typography.number)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                    .monospacedDigit()
            }

            MeterBar(tone: self.tone, usedPercent: self.window.usedPercent)

            HStack {
                Text("\(Int(self.window.usedPercent.rounded()))% used")
                Spacer()
                Text(DisplayText.reset(self.window.resetsAt) ?? "no reset")
            }
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Colors.tertiaryText)
        }
    }
}

private struct CompactMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(self.title.uppercased())
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .lineLimit(1)
            Text(self.value)
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .frame(height: 42)
        .glassSurface(cornerRadius: 7, tint: .white.opacity(0.045))
    }
}

private struct TodayCard: View {
    let snapshot: ProviderUsageSnapshot

    var body: some View {
        HStack(spacing: 0) {
            DetailColumn(title: "Active", value: DisplayText.minutes(self.snapshot.today.activeMinutes), detail: self.snapshot.today.peakHourLabel ?? "today")
            SoftDivider()
            DetailColumn(title: "Input", value: DisplayText.compact(self.snapshot.today.inputTokens), detail: "tokens")
            SoftDivider()
            DetailColumn(title: "Output", value: DisplayText.compact(self.snapshot.today.outputTokens), detail: "tokens")
        }
        .padding(.vertical, 10)
        .premiumCard(accent: DesignSystem.Colors.accent(for: self.snapshot.kind), includeGlow: false)
    }
}

private struct DetailColumn: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(spacing: 2) {
            Text(self.title.uppercased())
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .lineLimit(1)
            Text(self.value)
                .font(.system(size: 14, weight: .semibold, design: .default))
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .monospacedDigit()
            Text(self.detail)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SoftDivider: View {
    var body: some View {
        Rectangle()
            .fill(DesignSystem.Colors.stroke)
            .frame(width: 1, height: 34)
    }
}

private struct MiniProviderRow: View {
    let overview: UsageOverview

    var body: some View {
        HStack(spacing: 7) {
            ForEach(self.overview.snapshots) { snapshot in
                MiniProviderCard(snapshot: snapshot)
            }
        }
    }
}

private struct MiniProviderCard: View {
    let snapshot: ProviderUsageSnapshot

    private var tone: UsageTone {
        UsageTone(percent: self.snapshot.primaryUsedPercent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(self.snapshot.kind.displayName)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(self.snapshot.primaryUsedPercent.rounded()))%")
                    .font(DesignSystem.Typography.number)
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                    .monospacedDigit()
            }

            MeterBar(tone: self.tone, usedPercent: self.snapshot.primaryUsedPercent)

            Text(DisplayText.resetShort(self.snapshot.primaryResetAt))
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .lineLimit(1)
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .glassSurface(cornerRadius: 8, tint: .white.opacity(0.035))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DesignSystem.Colors.stroke.opacity(0.65))
        }
    }
}

private struct CodexAdvisorCard: View {
    let insight: CodexSessionInsight

    private var tone: UsageTone {
        UsageTone(health: self.insight.health)
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
                        Text(self.insight.health.title)
                            .font(.system(size: 14, weight: .semibold, design: .default))
                            .foregroundStyle(DesignSystem.Colors.primaryText)
                            .lineLimit(1)

                        Text("Codex advisor")
                            .font(.system(size: 9, weight: .medium, design: .default))
                            .foregroundStyle(DesignSystem.Colors.tertiaryText)
                            .padding(.horizontal, 6)
                            .frame(height: 17)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }

                    Text(self.insight.recommendation)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)
            }

            HStack(spacing: 6) {
                AdvisorMetric(title: "Why", value: self.insight.primaryDriver, detail: self.insight.driverDetail)
                AdvisorMetric(title: "Forecast", value: self.insight.forecast, detail: self.insight.resetPlan)
            }

            HStack(spacing: 6) {
                TinyMeterMetric(
                    title: "Last turn",
                    value: "\(Int(self.insight.lastTurnSharePercent.rounded()))%",
                    percent: self.insight.lastTurnSharePercent,
                    tone: self.tone)
                TinyMeterMetric(
                    title: "Burn/min",
                    value: DisplayText.compact(self.insight.tokensPerMinute),
                    percent: min(100, Double(self.insight.tokensPerMinute) / 650),
                    tone: self.tone)
            }
        }
        .padding(10)
        .premiumCard(accent: self.tone.color, includeGlow: true)
    }

    private var iconName: String {
        switch self.insight.health {
        case .efficient: "bolt.badge.checkmark"
        case .healthy: "checkmark.seal"
        case .watch: "eye"
        case .tight: "exclamationmark.triangle"
        case .stuck: "wrench.and.screwdriver"
        }
    }
}

private struct AdvisorMetric: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(self.title.uppercased())
                .font(.system(size: 9, weight: .medium, design: .default))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
            Text(self.value)
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(self.detail)
                .font(.system(size: 9, weight: .regular, design: .default))
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

private struct TinyMeterMetric: View {
    let title: String
    let value: String
    let percent: Double
    let tone: UsageTone

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(self.title.uppercased())
                    .font(.system(size: 9, weight: .medium, design: .default))
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

private struct CodexMemoryCard: View {
    let memory: CodexProjectMemory

    var body: some View {
        HStack(spacing: 0) {
            DetailColumn(title: "Project", value: self.memory.projectName, detail: "\(self.memory.sessionCount) sessions")
            SoftDivider()
            DetailColumn(title: "Avg turn", value: DisplayText.compact(self.memory.averageTurnTokens), detail: "tokens")
            SoftDivider()
            DetailColumn(title: "Burn index", value: self.burnMultiple, detail: self.burnDetail)
        }
        .padding(.vertical, 10)
        .premiumCard(accent: DesignSystem.Colors.accent(for: .codex), includeGlow: false)
    }

    private var burnMultiple: String {
        String(format: "%.1fx", self.memory.relativeBurnMultiple)
    }

    private var burnDetail: String {
        if self.memory.relativeBurnMultiple >= 1.5 { return "above normal" }
        if self.memory.relativeBurnMultiple <= 0.75 { return "below normal" }
        return "normal"
    }
}

private struct WorkContextCard: View {
    let context: WorkContextSnapshot

    private var tone: UsageTone {
        UsageTone(percent: self.context.contextUsedPercent)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Currently working under")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    Text(self.directoryName)
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                        .lineLimit(1)
                    if let model = self.context.modelName {
                        Text(model)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.tertiaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(self.context.contextRemainingPercent.rounded()))%")
                        .font(.system(size: 22, weight: .semibold, design: .default))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                        .monospacedDigit()
                    Text("context left")
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

            HStack(spacing: 7) {
                CompactMetric(title: "Last turn", value: DisplayText.compact(self.context.nextMessageTokens ?? 0))
                CompactMetric(title: "Burn", value: DisplayText.compact(self.context.averageGrowthTokens ?? 0))
                CompactMetric(title: "Msgs left", value: self.messagesRemainingText)
            }
        }
        .padding(12)
        .premiumCard(accent: self.tone.color, includeGlow: false)
    }

    private var directoryName: String {
        guard let directory = self.context.directory else { return "Codex session" }
        return URL(fileURLWithPath: directory).lastPathComponent
    }

    private var messagesRemainingText: String {
        guard let count = self.context.estimatedMessagesRemaining else { return "--" }
        if count > 999 { return "999+" }
        return "\(count)"
    }
}

private struct CodexTelemetryCard: View {
    let session: CodexSessionStats

    var body: some View {
        VStack(spacing: 9) {
            HStack(alignment: .center, spacing: 9) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.title)
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                        .lineLimit(1)
                    Text(self.metaLine)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                StatusPill(text: self.activityText, tone: self.statusTone)
            }

            HStack(spacing: 6) {
                TelemetryMetric(
                    title: "Cache",
                    value: DisplayText.compact(self.session.cachedInputTokens),
                    detail: "\(Int(self.session.cacheSharePercent.rounded()))% input")
                TelemetryMetric(
                    title: "Reason",
                    value: DisplayText.compact(self.session.reasoningOutputTokens),
                    detail: "\(Int(self.session.reasoningSharePercent.rounded()))% output")
                TelemetryMetric(
                    title: "Tools",
                    value: "\(self.session.toolCalls)",
                    detail: "\(self.session.shellCommands) shell")
                TelemetryMetric(
                    title: "Signals",
                    value: "\(self.session.patchEvents + self.session.webSearches + self.session.compactions)",
                    detail: "\(self.session.errors) errors")
            }
        }
        .padding(10)
        .premiumCard(accent: DesignSystem.Colors.accent(for: .codex), includeGlow: false)
    }

    private var title: String {
        self.session.threadTitle?.isEmpty == false ? self.session.threadTitle! : "Codex thread"
    }

    private var metaLine: String {
        let parts = [
            self.session.gitBranch.map { "branch \($0)" },
            self.session.reasoningEffort.map { "effort \($0)" },
            self.session.cliVersion.map { "Codex \($0)" },
        ].compactMap { $0 }
        return parts.isEmpty ? "local session telemetry" : parts.joined(separator: " / ")
    }

    private var activityText: String {
        guard let lastActivityAt = self.session.lastActivityAt else { return "local" }
        let seconds = max(0, Int(Date().timeIntervalSince(lastActivityAt)))
        if seconds < 120 { return "live" }
        if seconds < 3_600 { return "\(seconds / 60)m idle" }
        return "\(seconds / 3_600)h idle"
    }

    private var statusTone: UsageTone {
        guard let lastActivityAt = self.session.lastActivityAt else { return .watch }
        let seconds = max(0, Int(Date().timeIntervalSince(lastActivityAt)))
        if self.session.errors > 0 { return .tight }
        if seconds > 900 { return .watch }
        return .calm
    }
}

private struct CodexFlightRecorderCard: View {
    let session: CodexSessionStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Flight recorder")
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                Spacer()
                if let biggest = self.session.biggestBurnEvent?.tokenImpact {
                    Text("peak \(DisplayText.compact(biggest))")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                        .monospacedDigit()
                }
            }

            VStack(spacing: 5) {
                ForEach(self.session.flightEvents.prefix(4)) { event in
                    FlightEventRow(event: event)
                }
            }
        }
        .padding(10)
        .premiumCard(accent: DesignSystem.Colors.accent(for: .codex), includeGlow: false)
    }
}

private struct FlightEventRow: View {
    let event: CodexFlightEvent

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: self.symbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(self.color)
                .frame(width: 18, height: 18)
                .background(self.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(self.event.title)
                    .font(DesignSystem.Typography.label)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)
                Text(self.event.detail)
                    .font(.system(size: 9, weight: .regular, design: .default))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    .lineLimit(1)
            }

            Spacer()

            if let tokenImpact = self.event.tokenImpact {
                Text(DisplayText.compact(tokenImpact))
                    .font(DesignSystem.Typography.number)
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .glassSurface(cornerRadius: 7, tint: .white.opacity(0.026))
    }

    private var symbolName: String {
        switch self.event.kind {
        case .tokenSpike: "flame"
        case .shell: "terminal"
        case .patch: "hammer"
        case .web: "globe"
        case .error: "exclamationmark.triangle"
        case .compaction: "arrow.down.forward.and.arrow.up.backward"
        }
    }

    private var color: Color {
        switch self.event.kind {
        case .error: DesignSystem.Colors.danger
        case .tokenSpike, .compaction: DesignSystem.Colors.warning
        default: DesignSystem.Colors.accent(for: .codex)
        }
    }
}

private struct StatusPill: View {
    let text: String
    let tone: UsageTone

    var body: some View {
        Text(self.text)
            .font(.system(size: 9, weight: .semibold, design: .default))
            .foregroundStyle(self.tone.color)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(self.tone.color.opacity(0.12), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(self.tone.color.opacity(0.26))
            }
    }
}

private struct TelemetryMetric: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(self.title.uppercased())
                .font(.system(size: 9, weight: .medium, design: .default))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .lineLimit(1)
            Text(self.value)
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()
            Text(self.detail)
                .font(.system(size: 9, weight: .regular, design: .default))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .frame(height: 44)
        .glassSurface(cornerRadius: 7, tint: .white.opacity(0.032))
    }
}

private struct EmptyStateView: View {
    let isRefreshing: Bool
    let error: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: self.error == nil ? "hourglass" : "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(self.error == nil ? DesignSystem.Colors.secondaryText : DesignSystem.Colors.danger)
            Text(self.error ?? (self.isRefreshing ? "Refreshing" : "No usage data"))
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .glassSurface(cornerRadius: 8, tint: .white.opacity(0.055))
    }
}

@MainActor
private struct FooterView: View {
    @Bindable var model: MenuBarModel

    var body: some View {
        HStack(spacing: 8) {
            Text(self.leadingText)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .lineLimit(1)

            Spacer()

            if self.shouldShowInsights {
                Button {
                    self.openInsightsReport()
                } label: {
                    HStack(spacing: 3) {
                        Text("Insights")
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
                .font(DesignSystem.Typography.caption)
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .help("Open the cross-session Claude Code Insights HTML report")
            }

            Button(self.model.alertMode.title) {
                self.model.cycleAlertMode()
            }
            .font(DesignSystem.Typography.caption)
            .buttonStyle(.plain)
            .foregroundStyle(DesignSystem.Colors.secondaryText)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .font(DesignSystem.Typography.caption)
            .buttonStyle(.plain)
            .foregroundStyle(DesignSystem.Colors.secondaryText)
        }
        .padding(.horizontal, DesignSystem.Layout.contentPadding)
        .padding(.vertical, 8)
    }

    private var leadingText: String {
        if self.model.selectedProvider == .claude,
           let snap = self.model.overview.snapshot(for: .claude),
           let day = snap.claudeAggregate?.daysSinceFirstSession
        {
            return "day \(day) · " + self.updatedText
        }
        return self.updatedText
    }

    private var updatedText: String {
        guard !self.model.overview.snapshots.isEmpty else { return "not refreshed" }
        let seconds = max(0, Int(Date().timeIntervalSince(self.model.overview.updatedAt)))
        if seconds < 60 { return "updated just now" }
        return "updated \(seconds / 60)m ago"
    }

    private var shouldShowInsights: Bool {
        guard self.model.selectedProvider == .claude else { return false }
        let path = ("~/.claude/usage-data/report.html" as NSString).expandingTildeInPath
        return FileManager.default.fileExists(atPath: path)
    }

    private func openInsightsReport() {
        let path = ("~/.claude/usage-data/report.html" as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}

private struct GlassBackdrop: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.16),
                    Color.white.opacity(0.045),
                    Color.black.opacity(0.16),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)

            RadialGradient(
                colors: [
                    DesignSystem.Colors.accent(for: .codex).opacity(0.18),
                    .clear,
                ],
                center: .topLeading,
                startRadius: 18,
                endRadius: 260)

            RadialGradient(
                colors: [
                    DesignSystem.Colors.accent(for: .claude).opacity(0.14),
                    .clear,
                ],
                center: .bottomTrailing,
                startRadius: 12,
                endRadius: 260)
        }
    }
}

