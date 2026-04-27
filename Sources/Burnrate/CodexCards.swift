import BurnrateCore
import SwiftUI

// MARK: - Codex advisor card (used inside the Burn Watch surface)

struct CodexAdvisorCardView: View {
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
                    .brandGlassThin(cornerRadius: 7)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(self.insight.health.title)
                            .font(.geist(size: 14, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.primaryText)
                            .lineLimit(1)
                        Text("Codex advisor")
                            .font(.geist(size: 9, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.tertiaryText)
                            .padding(.horizontal, 6)
                            .frame(height: 17)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                    Text(self.insight.recommendation)
                        .font(.geist(size: 12))
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
            }

            HStack(spacing: 6) {
                AdvisorMetricChip(title: "Why", value: self.insight.primaryDriver, detail: self.insight.driverDetail)
                AdvisorMetricChip(title: "Forecast", value: self.insight.forecast, detail: self.insight.resetPlan)
            }

            HStack(spacing: 6) {
                AdvisorMeterChip(
                    title: "Last turn",
                    value: "\(Int(self.insight.lastTurnSharePercent.rounded()))%",
                    percent: self.insight.lastTurnSharePercent,
                    tone: self.tone)
                AdvisorMeterChip(
                    title: "Burn/min",
                    value: DisplayText.compact(self.insight.tokensPerMinute),
                    percent: min(100, Double(self.insight.tokensPerMinute) / 650 * 100),
                    tone: self.tone)
            }
        }
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

struct AdvisorMetricChip: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(self.title.uppercased())
                .font(.geist(size: 9, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
            Text(self.value)
                .font(.geist(size: 12, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(self.detail)
                .font(.geist(size: 9))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(minHeight: 56, alignment: .topLeading)
        .brandGlassThin(cornerRadius: 7)
    }
}

struct AdvisorMeterChip: View {
    let title: String
    let value: String
    let percent: Double
    let tone: UsageTone

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(self.title.uppercased())
                    .font(.geist(size: 9, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                Spacer()
                Text(self.value)
                    .font(.geistMono(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
            }
            MeterBar(tone: self.tone, usedPercent: self.percent)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .brandGlassThin(cornerRadius: 7)
    }
}

// MARK: - Codex context card (active session)

struct CodexContextCard: View {
    let context: WorkContextSnapshot

    private var tone: UsageTone {
        UsageTone(percent: self.context.contextUsedPercent)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Currently working under")
                        .font(.geist(size: 9, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    Text(self.directoryName)
                        .font(.geist(size: 14, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                        .lineLimit(1)
                    if let model = self.context.modelName {
                        Text(model)
                            .font(.geist(size: 10))
                            .foregroundStyle(DesignSystem.Colors.tertiaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(self.context.contextRemainingPercent.rounded()))%")
                        .font(.geistMono(size: 22, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                    Text("context left")
                        .font(.geist(size: 9))
                        .foregroundStyle(self.tone.color)
                }
            }

            MeterBar(tone: self.tone, usedPercent: self.context.contextUsedPercent)

            HStack {
                Text("\(DisplayText.compact(self.context.contextUsedTokens)) / \(DisplayText.compact(self.context.contextWindowTokens)) used")
                Spacer()
                Text(DisplayText.relative(self.context.updatedAt))
            }
            .font(.geist(size: 10))
            .foregroundStyle(DesignSystem.Colors.tertiaryText)
        }
        .padding(DesignSystem.Layout.cardPadding)
        .brandGlass(cornerRadius: DesignSystem.Layout.cardRadius)
    }

    private var directoryName: String {
        guard let directory = self.context.directory else { return "Codex session" }
        return URL(fileURLWithPath: directory).lastPathComponent
    }
}

// MARK: - Codex memory (project history)

struct CodexMemoryCard: View {
    let memory: CodexProjectMemory

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Project memory")
                    .font(.geist(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                Spacer()
                if let updated = memory.lastUpdatedAt {
                    Text(DisplayText.relative(updated))
                        .font(.geist(size: 9))
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                }
            }
            HStack(spacing: 0) {
                StatColumn(title: "Project", value: self.memory.projectName, detail: "\(self.memory.sessionCount) sessions")
                Spacer()
                StatColumn(title: "Avg turn", value: DisplayText.compact(self.memory.averageTurnTokens), detail: "tokens", monospaceValue: true)
                Spacer()
                StatColumn(title: "Burn idx", value: self.burnMultiple, detail: self.burnDetail, monospaceValue: true)
            }
        }
        .padding(DesignSystem.Layout.cardPadding)
        .brandGlass(cornerRadius: DesignSystem.Layout.cardRadius)
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

// MARK: - Codex telemetry card

struct CodexTelemetryCard: View {
    let session: CodexSessionStats

    var body: some View {
        VStack(spacing: 9) {
            HStack(alignment: .center, spacing: 9) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.title)
                        .font(.geist(size: 13, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                        .lineLimit(1)
                    Text(self.metaLine)
                        .font(.geist(size: 10))
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                StatusPill(text: self.activityText, tone: self.statusTone)
            }

            HStack(spacing: 6) {
                TelemetryMetric(title: "Cache", value: DisplayText.compact(self.session.cachedInputTokens), detail: "\(Int(self.session.cacheSharePercent.rounded()))% input")
                TelemetryMetric(title: "Reason", value: DisplayText.compact(self.session.reasoningOutputTokens), detail: "\(Int(self.session.reasoningSharePercent.rounded()))% output")
                TelemetryMetric(title: "Tools", value: "\(self.session.toolCalls)", detail: "\(self.session.shellCommands) shell")
                TelemetryMetric(title: "Signals", value: "\(self.session.patchEvents + self.session.webSearches + self.session.compactions)", detail: "\(self.session.errors) errors")
            }
        }
        .padding(DesignSystem.Layout.cardPadding)
        .brandGlass(cornerRadius: DesignSystem.Layout.cardRadius)
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
        return parts.isEmpty ? "local session telemetry" : parts.joined(separator: " · ")
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

// MARK: - Codex flight recorder card

struct CodexFlightRecorderCard: View {
    let session: CodexSessionStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Flight recorder")
                    .font(.geist(size: 13, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                Spacer()
                if let biggest = self.session.biggestBurnEvent?.tokenImpact {
                    Text("peak \(DisplayText.compact(biggest))")
                        .font(.geistMono(size: 10))
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                }
            }
            VStack(spacing: 5) {
                ForEach(self.session.flightEvents.prefix(4)) { event in
                    FlightEventRow(event: event)
                }
            }
        }
        .padding(DesignSystem.Layout.cardPadding)
        .brandGlass(cornerRadius: DesignSystem.Layout.cardRadius)
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
                    .font(.geist(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)
                Text(self.event.detail)
                    .font(.geist(size: 9))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    .lineLimit(1)
            }
            Spacer()
            if let tokenImpact = self.event.tokenImpact {
                Text(DisplayText.compact(tokenImpact))
                    .font(.geistMono(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .brandGlassThin(cornerRadius: 7)
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

// MARK: - Helpers

struct StatColumn: View {
    let title: String
    let value: String
    let detail: String
    var monospaceValue: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(self.title.uppercased())
                .font(.geist(size: 9, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
            Text(self.value)
                .font(self.monospaceValue ? .geistMono(size: 13, weight: .semibold) : .geist(size: 13, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(self.detail)
                .font(.geist(size: 9))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .lineLimit(1)
        }
    }
}

struct StatusPill: View {
    let text: String
    let tone: UsageTone

    var body: some View {
        Text(self.text)
            .font(.geist(size: 9, weight: .semibold))
            .foregroundStyle(self.tone.color)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(self.tone.color.opacity(0.12), in: Capsule())
            .overlay { Capsule().stroke(self.tone.color.opacity(0.26)) }
    }
}

struct TelemetryMetric: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(self.title.uppercased())
                .font(.geist(size: 9, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .lineLimit(1)
            Text(self.value)
                .font(.geistMono(size: 12, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(self.detail)
                .font(.geist(size: 9))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .frame(height: 44)
        .brandGlassThin(cornerRadius: 7)
    }
}
