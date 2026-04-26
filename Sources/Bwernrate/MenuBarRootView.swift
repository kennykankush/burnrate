import AppKit
import BwernrateCore
import SwiftUI

struct MenuBarRootView: View {
    @Bindable var model: MenuBarModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(model: self.model)

            Divider()
                .overlay(DesignSystem.Colors.stroke)

            VStack(spacing: 10) {
                if let snapshot = self.model.selectedSnapshot {
                    ProviderSwitch(selectedProvider: self.$model.selectedProvider, snapshots: self.model.overview.snapshots)
                    ProviderCard(snapshot: snapshot)
                    TodayCard(snapshot: snapshot)
                    MiniProviderRow(overview: self.model.overview)
                } else {
                    EmptyStateView(isRefreshing: self.model.isRefreshing, error: self.model.lastError)
                }
            }
            .padding(DesignSystem.Layout.contentPadding)

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

private struct HeaderView: View {
    @Bindable var model: MenuBarModel

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .frame(width: 24, height: 24)
                .glassSurface(cornerRadius: 7, tint: .white.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(DesignSystem.Colors.stroke)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text("bwernrate")
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
                        Image(systemName: provider.symbolName)
                            .font(.system(size: 10, weight: .semibold))
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
        UsageTone(percent: self.snapshot.highestUsedPercent)
    }

    var body: some View {
        VStack(spacing: 11) {
            HStack(alignment: .center, spacing: 10) {
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
                    Text("\(Int(self.snapshot.highestUsedPercent.rounded()))%")
                        .font(.system(size: 25, weight: .semibold, design: .default))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                        .monospacedDigit()
                    Text(self.tone.label)
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
                CompactMetric(title: "Requests", value: "\(self.snapshot.today.requests)")
                CompactMetric(title: "Tokens", value: DisplayText.compact(self.snapshot.today.totalTokens))
                CompactMetric(title: "Spend", value: DisplayText.money(self.snapshot.today.spend?.used, currency: self.snapshot.today.spend?.currencyCode))
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

private struct MeterBar: View {
    let tone: UsageTone
    let usedPercent: Double

    var body: some View {
        GeometryReader { proxy in
            let fillWidth = max(4, proxy.size.width * min(1, max(0, self.usedPercent / 100)))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(self.tone.color)
                    .frame(width: fillWidth)
            }
        }
        .frame(height: 5)
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
        UsageTone(percent: self.snapshot.highestUsedPercent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(self.snapshot.kind.displayName)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(self.snapshot.highestUsedPercent.rounded()))%")
                    .font(DesignSystem.Typography.number)
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                    .monospacedDigit()
            }

            MeterBar(tone: self.tone, usedPercent: self.snapshot.highestUsedPercent)

            Text(DisplayText.resetShort(self.snapshot.nextResetAt))
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

private struct FooterView: View {
    @Bindable var model: MenuBarModel

    var body: some View {
        HStack {
            Text(self.updatedText)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.tertiaryText)

            Spacer()

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

    private var updatedText: String {
        guard !self.model.overview.snapshots.isEmpty else { return "not refreshed" }
        let seconds = max(0, Int(Date().timeIntervalSince(self.model.overview.updatedAt)))
        if seconds < 60 { return "updated just now" }
        return "updated \(seconds / 60)m ago"
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

private enum UsageTone {
    case calm
    case watch
    case tight

    init(percent: Double) {
        switch percent {
        case 0..<55:
            self = .calm
        case 55..<82:
            self = .watch
        default:
            self = .tight
        }
    }

    var label: String {
        switch self {
        case .calm: "Healthy"
        case .watch: "Moderate"
        case .tight: "Tight"
        }
    }

    var color: Color {
        switch self {
        case .calm: DesignSystem.Colors.success
        case .watch: DesignSystem.Colors.warning
        case .tight: DesignSystem.Colors.danger
        }
    }
}

private enum DisplayText {
    static func reset(_ date: Date?) -> String? {
        guard let date else { return nil }
        let remaining = date.timeIntervalSinceNow
        guard remaining > 0 else { return "resets now" }
        let minutes = Int(remaining / 60)
        if minutes < 60 { return "resets in \(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "resets in \(hours)h" }
        return "resets in \(hours / 24)d"
    }

    static func resetShort(_ date: Date?) -> String {
        guard let text = reset(date) else { return "--" }
        return text.replacingOccurrences(of: "resets in ", with: "")
            .replacingOccurrences(of: "resets ", with: "")
    }

    static func compact(_ value: Int) -> String {
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

    static func minutes(_ value: Int) -> String {
        if value < 60 { return "\(value)m" }
        let hours = value / 60
        let minutes = value % 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }

    static func money(_ value: Double?, currency: String?) -> String {
        guard let value else { return "--" }
        return money(value, currency: currency ?? "USD")
    }

    static func money(_ value: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private extension View {
    func premiumCard(accent: Color, includeGlow: Bool = true) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.075),
                                Color.white.opacity(0.040),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing))
                    .overlay(alignment: .topLeading) {
                        if includeGlow {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(accent.opacity(0.10))
                                .frame(width: 118, height: 42)
                                .offset(x: -22, y: -18)
                                .clipped()
                        }
                    }
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.34),
                                        Color.white.opacity(0.10),
                                        Color.white.opacity(0.04),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing),
                                lineWidth: 1)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.10))
            }
            .shadow(color: Color.black.opacity(0.16), radius: 10, y: 6)
    }

    func glassSurface(cornerRadius: CGFloat, tint: Color = .clear) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.045),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint)
                    }
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.32),
                                        Color.white.opacity(0.08),
                                        Color.white.opacity(0.03),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing),
                                lineWidth: 1)
                    }
            }
    }
}
