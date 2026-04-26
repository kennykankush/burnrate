import BurnrateCore
import Foundation
import Observation

@MainActor
@Observable
final class MenuBarModel {
    var overview: UsageOverview = .empty
    var selectedProvider: ProviderKind = .codex
    var isRefreshing = false
    var lastError: String?
    var alertMode: UsageAlertMode = UsageAlertMode(rawValue: UserDefaults.standard.string(forKey: UsageNotificationController.alertModeKey) ?? "") ?? .all
    var isLaunchAtLoginEnabled: Bool = LaunchAtLoginManager.isEnabled

    private let source = UsageSnapshotSource()
    private let notificationController = UsageNotificationController()
    private var hasStarted = false
    private var refreshTask: Task<Void, Never>?

    var selectedSnapshot: ProviderUsageSnapshot? {
        self.overview.snapshot(for: self.selectedProvider) ?? self.overview.snapshots.first
    }

    var menuBarText: String {
        guard !self.overview.snapshots.isEmpty else { return "--" }
        let snapshot = self.overview.snapshot(for: self.selectedProvider) ?? self.overview.snapshots.first
        return "\(Int((snapshot?.primaryUsedPercent ?? 0).rounded()))%"
    }

    func start() {
        guard !self.hasStarted else { return }
        self.hasStarted = true
        self.refreshTask = Task {
            await self.notificationController.prepare()
            await self.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await self.refresh()
            }
        }
    }

    func refresh() async {
        guard !self.isRefreshing else { return }
        self.isRefreshing = true
        defer { self.isRefreshing = false }

        do {
            let overview = try await self.source.loadOverview()
            self.overview = overview
            await self.notificationController.evaluate(overview)
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

    func cycleAlertMode() {
        self.alertMode = self.alertMode.next
        UserDefaults.standard.set(self.alertMode.rawValue, forKey: UsageNotificationController.alertModeKey)
    }

    func toggleLaunchAtLogin() {
        do {
            if self.isLaunchAtLoginEnabled {
                try LaunchAtLoginManager.disable()
            } else {
                try LaunchAtLoginManager.enable()
            }
        } catch {
            self.lastError = "Launch at login failed: \(error.localizedDescription)"
        }
        self.isLaunchAtLoginEnabled = LaunchAtLoginManager.isEnabled
    }
}
