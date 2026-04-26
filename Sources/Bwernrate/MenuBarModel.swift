import BwernrateCore
import Foundation
import Observation

@MainActor
@Observable
final class MenuBarModel {
    var overview: UsageOverview = .empty
    var selectedProvider: ProviderKind = .codex
    var isRefreshing = false
    var lastError: String?

    private let source = UsageSnapshotSource()
    private var hasStarted = false

    var selectedSnapshot: ProviderUsageSnapshot? {
        self.overview.snapshot(for: self.selectedProvider) ?? self.overview.snapshots.first
    }

    var menuBarText: String {
        guard !self.overview.snapshots.isEmpty else { return "--" }
        return "\(Int(self.overview.highestUsedPercent.rounded()))%"
    }

    func start() {
        guard !self.hasStarted else { return }
        self.hasStarted = true
        Task {
            await self.refresh()
        }
    }

    func refresh() async {
        guard !self.isRefreshing else { return }
        self.isRefreshing = true
        defer { self.isRefreshing = false }

        do {
            let overview = try await self.source.loadOverview()
            self.overview = overview
            if overview.snapshot(for: self.selectedProvider) == nil,
               let first = overview.snapshots.first
            {
                self.selectedProvider = first.kind
            }
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }
}

