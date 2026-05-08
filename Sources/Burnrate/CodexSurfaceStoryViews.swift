import BurnrateCore
import SwiftUI

// MARK: - Codex native surfaces

struct CodexSurfaceOverviewPanel: View {
    let surface: CodexSurfaceSnapshot
    let context: WorkContextSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    CodexSectionKicker(title: "CODEX WORK MAP")
                    Text(self.headline)
                        .font(.geist(size: 18, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(self.surface.rootPath)
                        .font(.geistMono(size: 9))
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(self.surface.projectsSeen)")
                        .font(.geistMono(size: 27, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.accent(for: .codex))
                    Text("projects")
                        .font(.geist(size: 9))
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                }
            }

            HStack(spacing: 6) {
                CodexMetricCell(title: "Threads", value: "\(self.surface.stateThreadsSeen)", detail: "\(self.surface.projectsSeen) projects")
                CodexMetricCell(title: "Tokens", value: DisplayText.compact(self.surface.totalThreadTokens), detail: self.timespan)
                CodexMetricCell(title: "History", value: "\(self.surface.rolloutFilesSeen)", detail: "\(self.surface.rolloutEventMix.toolCalls) tools")
                CodexMetricCell(title: "Context", value: self.contextLabel, detail: self.contextDetail)
            }

            CodexSignalStrip(surface: self.surface)
        }
        .padding(DesignSystem.Layout.cardPadding)
        .brandGlass(cornerRadius: DesignSystem.Layout.cardRadius)
    }

    private var headline: String {
        if self.surface.projectsSeen > 0 {
            return "\(self.surface.projectsSeen) projects in local memory"
        }
        return "Codex work map is warming up"
    }

    private var timespan: String {
        guard let first = self.surface.firstThreadAt,
              let last = self.surface.lastThreadAt
        else { return "local history" }
        let days = max(1, Calendar.current.dateComponents([.day], from: first, to: last).day ?? 1)
        return "\(days)d span"
    }

    private var contextLabel: String {
        guard let context else { return "--" }
        return "\(Int(context.contextUsedPercent.rounded()))%"
    }

    private var contextDetail: String {
        guard let context else { return "no live thread" }
        return "\(DisplayText.compact(context.contextRemainingTokens)) left"
    }
}

struct CodexPatternsNativeView: View {
    let snapshot: ProviderUsageSnapshot

    private var surface: CodexSurfaceSnapshot? { self.snapshot.codexSurface }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let surface {
                CodexPatternHeader(surface: surface, session: self.snapshot.codexSession)
                CodexFacetMatrixCard(
                    title: "Model and reasoning shape",
                    facets: [
                        ("Models", surface.modelFacets),
                        ("Reasoning", surface.reasoningFacets),
                    ])
                CodexEventMixCard(surface: surface, session: self.snapshot.codexSession)
                CodexFacetMatrixCard(
                    title: "Operating posture",
                    facets: [
                        ("Approvals", surface.approvalFacets),
                        ("Sandbox", surface.sandboxFacets),
                    ])
                CodexRecentThreadsCard(surface: surface)
            } else if let session = self.snapshot.codexSession {
                CodexTelemetryCard(session: session)
            } else {
                CodexNativeEmpty(title: "No Codex pattern data", detail: "Patterns fill once Codex has local work history.")
            }
        }
    }
}

struct CodexWrapNativeView: View {
    let snapshot: ProviderUsageSnapshot

    private var surface: CodexSurfaceSnapshot? { self.snapshot.codexSurface }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let surface {
                CodexWrapHeader(surface: surface, memory: self.snapshot.codexMemory)
                if !surface.activityDays.isEmpty {
                    CodexActivityPulseCard(surface: surface)
                }
                CodexProjectLeaderboardCard(surface: surface)
                if let memory = self.snapshot.codexMemory {
                    CodexMemoryCard(memory: memory)
                }
                CodexRecentThreadsCard(surface: surface)
            } else if let memory = self.snapshot.codexMemory {
                CodexMemoryCard(memory: memory)
            } else {
                CodexNativeEmpty(title: "No Codex wrap yet", detail: "Use Codex across a few threads and the project story appears here.")
            }
        }
    }
}

struct CodexHealthNativeView: View {
    let snapshot: ProviderUsageSnapshot

    private var surface: CodexSurfaceSnapshot? { self.snapshot.codexSurface }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let session = self.snapshot.codexSession {
                CodexHealthCommandCard(snapshot: self.snapshot, session: session)
            }
            if let surface {
                CodexSurfaceCoverageCard(surface: surface)
                CodexAutomationCard(surface: surface)
                CodexEventMixCard(surface: surface, session: self.snapshot.codexSession)
            } else if self.snapshot.codexSession == nil {
                CodexNativeEmpty(title: "No Codex health data", detail: "Health needs an active thread or local Codex history.")
            }
        }
    }
}

struct CodexProjectLeaderboardCard: View {
    let surface: CodexSurfaceSnapshot

    var body: some View {
        CodexStoryCard(title: "Projects in motion", trailing: "\(self.surface.topProjects.count)") {
            if self.surface.topProjects.isEmpty {
                CodexMutedLine("No Codex projects recorded yet.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(self.surface.topProjects.prefix(6).enumerated()), id: \.element.id) { idx, project in
                        CodexProjectRow(project: project, maxTokens: self.maxProjectTokens)
                        if idx < min(self.surface.topProjects.count, 6) - 1 {
                            Divider().background(DesignSystem.Colors.stroke.opacity(0.35))
                        }
                    }
                }
            }
        }
    }

    private var maxProjectTokens: Int {
        max(1, self.surface.topProjects.map(\.tokens).max() ?? 1)
    }
}

struct CodexRecentThreadsCard: View {
    let surface: CodexSurfaceSnapshot

    var body: some View {
        CodexStoryCard(title: "Recent work", trailing: "\(self.surface.recentThreads.count)") {
            if self.surface.recentThreads.isEmpty {
                CodexMutedLine("No recent Codex threads yet.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(self.surface.recentThreads.prefix(6).enumerated()), id: \.element.id) { idx, thread in
                        CodexThreadRow(thread: thread)
                        if idx < min(self.surface.recentThreads.count, 6) - 1 {
                            Divider().background(DesignSystem.Colors.stroke.opacity(0.35))
                        }
                    }
                }
            }
        }
    }
}

struct CodexEventMixCard: View {
    let surface: CodexSurfaceSnapshot
    let session: CodexSessionStats?

    private var rows: [(String, Int, Color)] {
        let mix = self.surface.rolloutEventMix
        let rows: [(String, Int, Color)] = [
            ("Context checks", mix.tokenEvents, DesignSystem.Colors.accent(for: .codex)),
            ("Tools", max(mix.toolCalls, self.session?.toolCalls ?? 0), DesignSystem.Colors.brandLavender),
            ("Shell", max(mix.shellCommands, self.session?.shellCommands ?? 0), DesignSystem.Colors.success),
            ("Edits", max(mix.patchEvents, self.session?.patchEvents ?? 0), DesignSystem.Colors.warning),
            ("Web", max(mix.webSearches, self.session?.webSearches ?? 0), Color.cyan),
            ("Errors", max(mix.errors, self.session?.errors ?? 0), DesignSystem.Colors.danger),
            ("Wraps", max(mix.compactions, self.session?.compactions ?? 0), Color.orange),
        ]
        return rows.filter { $0.1 > 0 }
    }

    var body: some View {
        CodexStoryCard(title: "Work signal mix", trailing: self.windowLabel) {
            if self.rows.isEmpty {
                CodexMutedLine("Recent Codex work has not exposed tool or context events yet.")
            } else {
                VStack(spacing: 7) {
                    ForEach(self.rows, id: \.0) { row in
                        CodexBarRow(label: row.0, value: row.1, maxValue: self.maxValue, tint: row.2)
                    }
                }
            }
        }
    }

    private var maxValue: Int {
        max(1, self.rows.map(\.1).max() ?? 1)
    }

    private var windowLabel: String {
        self.surface.rolloutFilesSeen > 24 ? "recent work" : "\(self.surface.rolloutFilesSeen) threads"
    }
}

struct CodexActivityPulseCard: View {
    let surface: CodexSurfaceSnapshot

    var body: some View {
        CodexStoryCard(title: "Daily rhythm", trailing: "\(self.totalThreads) threads") {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(self.surface.activityDays) { day in
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(self.color(for: day))
                            .frame(height: self.height(for: day))
                        Text(day.label)
                            .font(.geistMono(size: 8))
                            .foregroundStyle(DesignSystem.Colors.tertiaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 74, alignment: .bottom)
        }
    }

    private var totalThreads: Int {
        self.surface.activityDays.reduce(0) { $0 + $1.threadCount }
    }

    private var maxTokens: Int {
        max(1, self.surface.activityDays.map(\.tokens).max() ?? 1)
    }

    private func height(for day: CodexSurfaceActivityDay) -> CGFloat {
        max(8, CGFloat(day.tokens) / CGFloat(self.maxTokens) * 48)
    }

    private func color(for day: CodexSurfaceActivityDay) -> Color {
        if day.threadCount >= 6 { return DesignSystem.Colors.danger }
        if day.threadCount >= 3 { return DesignSystem.Colors.warning }
        return DesignSystem.Colors.accent(for: .codex)
    }
}

struct CodexAutomationCard: View {
    let surface: CodexSurfaceSnapshot

    var body: some View {
        CodexStoryCard(title: "Delegation layer", trailing: nil) {
            HStack(spacing: 6) {
                CodexMetricCell(title: "Jobs", value: "\(self.surface.automation.agentJobs)", detail: "background")
                CodexMetricCell(title: "Goals", value: "\(self.surface.automation.activeGoals)", detail: "active")
                CodexMetricCell(title: "Tools", value: "\(self.surface.automation.dynamicTools)", detail: "available")
                CodexMetricCell(title: "Spawns", value: "\(self.surface.automation.spawnEdges)", detail: "delegated")
            }
        }
    }
}

struct CodexSurfaceCoverageCard: View {
    let surface: CodexSurfaceSnapshot

    var body: some View {
        CodexStoryCard(title: "Signals Burnrate can see", trailing: self.surface.primarySummary) {
            VStack(spacing: 0) {
                ForEach(Array(self.surface.sources.enumerated()), id: \.element.id) { idx, source in
                    CodexCoverageRow(source: source)
                    if idx < self.surface.sources.count - 1 {
                        Divider().background(DesignSystem.Colors.stroke.opacity(0.35))
                    }
                }
            }
        }
    }
}

// MARK: - Private story components

private struct CodexPatternHeader: View {
    let surface: CodexSurfaceSnapshot
    let session: CodexSessionStats?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    CodexSectionKicker(title: "CODEX PATTERNS")
                    Text(self.dominantModel)
                        .font(.geist(size: 18, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                        .lineLimit(1)
                    Text(self.detail)
                        .font(.geist(size: 10))
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                        .lineLimit(2)
                }
                Spacer()
                StatusPill(text: self.sessionState, tone: self.sessionTone)
            }

            HStack(spacing: 6) {
                CodexMetricCell(title: "Projects", value: "\(self.surface.projectsSeen)", detail: "folders")
                CodexMetricCell(title: "Models", value: "\(self.surface.modelFacets.count)", detail: "seen")
                CodexMetricCell(title: "Reasoning", value: self.topReasoning, detail: "dominant")
                CodexMetricCell(title: "Delegation", value: "\(self.surface.automation.spawnEdges)", detail: "spawns")
            }
        }
        .padding(DesignSystem.Layout.cardPadding)
        .brandGlass(cornerRadius: DesignSystem.Layout.cardRadius)
    }

    private var dominantModel: String {
        self.surface.modelFacets.first?.label ?? self.session?.threadTitle ?? "Codex pattern map"
    }

    private var detail: String {
        "\(self.surface.stateThreadsSeen) threads, \(DisplayText.compact(self.surface.totalThreadTokens)) tokens remembered, \(self.surface.rolloutEventMix.toolCalls) tool actions observed"
    }

    private var topReasoning: String {
        self.surface.reasoningFacets.first?.label ?? self.session?.reasoningEffort ?? "--"
    }

    private var sessionState: String {
        guard let last = self.session?.lastActivityAt else { return "state" }
        let seconds = max(0, Int(Date().timeIntervalSince(last)))
        if seconds < 120 { return "live" }
        if seconds < 3_600 { return "\(seconds / 60)m idle" }
        return "\(seconds / 3_600)h idle"
    }

    private var sessionTone: UsageTone {
        guard let session else { return .watch }
        if session.errors > 0 { return .tight }
        return .calm
    }
}

private struct CodexWrapHeader: View {
    let surface: CodexSurfaceSnapshot
    let memory: CodexProjectMemory?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CodexSectionKicker(title: "CODEX WRAP")
            HStack(spacing: 6) {
                CodexMetricCell(title: "Threads", value: "\(self.surface.stateThreadsSeen)", detail: "history")
                CodexMetricCell(title: "Projects", value: "\(self.surface.projectsSeen)", detail: "folders")
                CodexMetricCell(title: "Tokens", value: DisplayText.compact(self.surface.totalThreadTokens), detail: "remembered")
                CodexMetricCell(title: "Avg turn", value: self.memoryLabel, detail: "project")
            }
            if let first = self.surface.firstThreadAt {
                Text("Codex history begins \(DisplayText.relative(first)); newest thread \(self.latestLabel).")
                    .font(.geist(size: 10))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    .lineLimit(2)
            }
        }
        .padding(DesignSystem.Layout.cardPadding)
        .brandGlass(cornerRadius: DesignSystem.Layout.cardRadius)
    }

    private var memoryLabel: String {
        guard let memory else { return "--" }
        return DisplayText.compact(memory.averageTurnTokens)
    }

    private var latestLabel: String {
        guard let last = self.surface.lastThreadAt else { return "unknown" }
        return DisplayText.relative(last)
    }
}

private struct CodexHealthCommandCard: View {
    let snapshot: ProviderUsageSnapshot
    let session: CodexSessionStats

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: self.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(self.tone.color)
                    .frame(width: 30, height: 30)
                    .brandGlassThin(cornerRadius: 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(self.title)
                        .font(.geist(size: 16, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                    Text(self.detail)
                        .font(.geist(size: 10))
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                        .lineLimit(2)
                }
                Spacer()
            }

            HStack(spacing: 6) {
                CodexMetricCell(title: "Context", value: self.contextValue, detail: self.contextDetail)
                CodexMetricCell(title: "Errors", value: "\(self.session.errors)", detail: self.errorDetail)
                CodexMetricCell(title: "Wraps", value: "\(self.session.compactions)", detail: "context")
                CodexMetricCell(title: "Quota", value: self.windowValue, detail: self.windowDetail)
            }
        }
        .padding(DesignSystem.Layout.cardPadding)
        .brandGlass(cornerRadius: DesignSystem.Layout.cardRadius)
    }

    private var title: String {
        self.session.insight?.health.title ?? "Codex health"
    }

    private var detail: String {
        self.session.insight?.recommendation
            ?? "Active Codex thread is being watched with context and quota signals."
    }

    private var tone: UsageTone {
        if let insight = self.session.insight { return UsageTone(health: insight.health) }
        if self.session.errors > 0 { return .tight }
        return .calm
    }

    private var iconName: String {
        switch self.tone {
        case .calm: "checkmark.seal"
        case .watch: "eye"
        case .tight: "exclamationmark.triangle"
        }
    }

    private var contextValue: String {
        guard let context = self.snapshot.workContext else { return "--" }
        return "\(Int(context.contextUsedPercent.rounded()))%"
    }

    private var contextDetail: String {
        guard let context = self.snapshot.workContext else { return "no live context" }
        if let remaining = context.estimatedMessagesRemaining {
            return "~\(remaining) turns left"
        }
        return "learning pace"
    }

    private var errorDetail: String {
        self.session.errors == 0 ? "clean" : "check last event"
    }

    private var windowValue: String {
        guard let window = self.snapshot.mostPressedWindow else { return "--" }
        return "\(Int(window.usedPercent.rounded()))%"
    }

    private var windowDetail: String {
        DisplayText.resetShort(self.snapshot.mostPressedWindow?.resetsAt)
    }
}

private struct CodexFacetMatrixCard: View {
    let title: String
    let facets: [(String, [CodexSurfaceFacet])]

    var body: some View {
        CodexStoryCard(title: self.title, trailing: nil) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(self.facets, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(group.0.uppercased())
                            .font(.geist(size: 9, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.tertiaryText)
                            .tracking(1.0)
                        if group.1.isEmpty {
                            CodexMutedLine("No \(group.0.lowercased()) recorded.")
                        } else {
                            VStack(spacing: 6) {
                                ForEach(group.1.prefix(5)) { facet in
                                    CodexFacetRow(facet: facet, maxCount: self.maxCount(group.1))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func maxCount(_ facets: [CodexSurfaceFacet]) -> Int {
        max(1, facets.map(\.count).max() ?? 1)
    }
}

private struct CodexSignalStrip: View {
    let surface: CodexSurfaceSnapshot

    private var items: [(String, String, Color)] {
        [
            ("Live", "\(self.sourceCount(.liveSessions)) active", DesignSystem.Colors.success),
            ("Projects", "\(self.surface.projectsSeen) seen", DesignSystem.Colors.accent(for: .codex)),
            ("Memory", "\(self.sourceCount(.projectMemory)) ready", DesignSystem.Colors.brandLavender),
            ("Skills", "\(self.sourceCount(.skills) + self.sourceCount(.plugins)) ready", DesignSystem.Colors.warning),
        ]
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(self.items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.0.uppercased())
                        .font(.geist(size: 8, weight: .bold))
                        .foregroundStyle(item.2)
                        .tracking(0.9)
                    Text(item.1)
                        .font(.geistMono(size: 13, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                    Text(self.caption(for: item.0))
                        .font(.geist(size: 9))
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(item.2.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
    }

    private func sourceCount(_ key: CodexSurfaceKey) -> Int {
        guard let source = self.surface.sources.first(where: { $0.key == key }) else { return 0 }
        return source.status.isReady ? max(1, source.count ?? 1) : 0
    }

    private func caption(for title: String) -> String {
        switch title {
        case "Live": "right now"
        case "Projects": "work map"
        case "Memory": "project history"
        default: "extensions"
        }
    }
}

private struct CodexProjectRow: View {
    let project: CodexSurfaceProject
    let maxTokens: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(self.project.name)
                    .font(.geist(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                    .lineLimit(1)
                Spacer()
                Text(DisplayText.compact(self.project.tokens))
                    .font(.geistMono(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.accent(for: .codex))
            }
            HStack(spacing: 7) {
                MeterBar(tone: .calm, usedPercent: Double(self.project.tokens) / Double(max(1, self.maxTokens)) * 100)
                Text("\(self.project.threadCount) threads")
                    .font(.geist(size: 9))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(self.project.latestTitle ?? self.project.path)
                    .font(.geist(size: 9))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let last = self.project.lastActivityAt {
                    Text(DisplayText.relative(last))
                        .font(.geistMono(size: 9))
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

private struct CodexThreadRow: View {
    let thread: CodexSurfaceThread

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            VStack(alignment: .leading, spacing: 3) {
                Text(self.thread.title)
                    .font(.geist(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(self.metaLine)
                    .font(.geist(size: 9))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(DisplayText.compact(self.thread.tokens))
                    .font(.geistMono(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                if let last = self.thread.lastActivityAt {
                    Text(DisplayText.relative(last))
                        .font(.geistMono(size: 8))
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                }
            }
        }
        .padding(.vertical, 7)
    }

    private var metaLine: String {
        [
            self.thread.projectName,
            self.thread.modelName,
            self.thread.reasoningEffort,
            self.thread.gitBranch.map { "branch \($0)" },
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " / ")
    }
}

private struct CodexFacetRow: View {
    let facet: CodexSurfaceFacet
    let maxCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(self.facet.label)
                .font(.geist(size: 10, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .frame(width: 96, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
            MeterBar(tone: .calm, usedPercent: Double(self.facet.count) / Double(max(1, self.maxCount)) * 100)
            Text("\(self.facet.count)")
                .font(.geistMono(size: 10, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .frame(width: 30, alignment: .trailing)
        }
    }
}

private struct CodexBarRow: View {
    let label: String
    let value: Int
    let maxValue: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(self.label)
                .font(.geist(size: 10, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .frame(width: 84, alignment: .leading)
                .lineLimit(1)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(DesignSystem.Colors.stroke.opacity(0.35))
                    Capsule()
                        .fill(self.tint.opacity(0.75))
                        .frame(width: max(6, proxy.size.width * CGFloat(self.value) / CGFloat(max(1, self.maxValue))))
                }
            }
            .frame(height: 7)
            Text("\(self.value)")
                .font(.geistMono(size: 10, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

private struct CodexCoverageRow: View {
    let source: CodexSurfaceArea

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(self.source.status.displayColor)
                .frame(width: 7, height: 7)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(self.title)
                        .font(.geist(size: 11, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Text(self.visibilityLabel)
                        .font(.geist(size: 8))
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                        .lineLimit(1)
                }
                Text(self.detail)
                    .font(.geist(size: 9))
                    .foregroundStyle(DesignSystem.Colors.tertiaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 7)
    }

    private var title: String {
        switch self.source.key {
        case .root: "Codex installed"
        case .liveSessions: "Live work"
        case .quota: "Usage windows"
        case .sessions: "Work history"
        case .stateDB: "Project history"
        case .auth: "Account"
        case .config: "Preferences"
        case .skills: "Skills"
        case .plugins: "Plugins"
        case .logs: "Diagnostics"
        case .projectMemory: "Burnrate memory"
        }
    }

    private var detail: String {
        switch self.source.key {
        case .root: return self.source.status.isReady ? "Codex is available on this Mac." : "Codex has not created local files yet."
        case .liveSessions: return (self.source.count ?? 0) > 0 ? "\(self.source.count ?? 0) active Codex thread\(self.source.count == 1 ? "" : "s")." : "No Codex thread is active right now."
        case .quota: return self.source.status.isReady ? "Quota pressure can be shown in the notch." : "Quota appears after Codex emits usage data."
        case .sessions: return (self.source.count ?? 0) > 0 ? "\(self.source.count ?? 0) past thread files available for pace and tool stories." : "No local work history yet."
        case .stateDB: return self.source.status.isReady ? "Projects, titles, branches, models, and timing are available." : "Project history is not available yet."
        case .auth: return self.source.status.isReady ? "Account presence is known; secrets are not displayed." : "No account token is available for remote checks."
        case .config: return self.source.status.isReady ? "Preferences can explain model, sandbox, and extension posture." : "No Codex preferences file is present."
        case .skills: return (self.source.count ?? 0) > 0 ? "\(self.source.count ?? 0) Codex skill\(self.source.count == 1 ? "" : "s") installed." : "No Codex skills found."
        case .plugins: return (self.source.count ?? 0) > 0 ? "\(self.source.count ?? 0) plugin/cache director\(self.source.count == 1 ? "y" : "ies") found." : "No plugin cache found."
        case .logs: return self.source.status.isReady ? "Diagnostics are available for troubleshooting." : "No diagnostics folder found."
        case .projectMemory: return self.source.status.isReady ? "Burnrate can compare this project against prior sessions." : "Project memory starts after a Codex session is seen."
        }
    }

    private var visibilityLabel: String {
        switch self.source.status {
        case .active: "active"
        case .available: "available"
        case .warning: "partial"
        case .missing: "missing"
        }
    }
}

private struct CodexMetricCell: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(self.title.uppercased())
                .font(.geist(size: 8, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .lineLimit(1)
            Text(self.value)
                .font(.geistMono(size: 13, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(self.detail)
                .font(.geist(size: 8))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .brandGlassThin(cornerRadius: 7)
    }
}

private struct CodexStoryCard<Content: View>: View {
    let title: String
    let trailing: String?
    let content: Content

    init(title: String, trailing: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(self.title)
                    .font(.geist(size: 13, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                    .lineLimit(1)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.geistMono(size: 9))
                        .foregroundStyle(DesignSystem.Colors.tertiaryText)
                        .lineLimit(1)
                }
            }
            self.content
        }
        .padding(DesignSystem.Layout.cardPadding)
        .brandGlass(cornerRadius: DesignSystem.Layout.cardRadius)
    }
}

private struct CodexSectionKicker: View {
    let title: String

    var body: some View {
        Text(self.title)
            .font(.geist(size: 9, weight: .bold))
            .foregroundStyle(DesignSystem.Colors.accent(for: .codex))
            .tracking(1.2)
    }
}

private struct CodexMutedLine: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(self.text)
            .font(.geist(size: 10))
            .foregroundStyle(DesignSystem.Colors.tertiaryText)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CodexNativeEmpty: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.accent(for: .codex))
            Text(self.title)
                .font(.geist(size: 12, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.primaryText)
            Text(self.detail)
                .font(.geist(size: 10))
                .foregroundStyle(DesignSystem.Colors.tertiaryText)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity)
        .padding(34)
        .brandGlass(cornerRadius: DesignSystem.Layout.cardRadius)
    }
}

private extension CodexSurfaceStatus {
    var displayColor: Color {
        switch self {
        case .active: DesignSystem.Colors.success
        case .available: DesignSystem.Colors.accent(for: .codex)
        case .warning: DesignSystem.Colors.warning
        case .missing: DesignSystem.Colors.tertiaryText
        }
    }
}
