import Foundation
import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp` for "launch at login" support.
///
/// macOS 13+ approach: the app registers itself with the service manager. The
/// user can also toggle the same registration from System Settings → General →
/// Login Items. Both surfaces stay in sync via `SMAppService.mainApp.status`.
@MainActor
enum LaunchAtLoginManager {
    /// Whether burnrate is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Whether the registration request returned an unrecoverable error
    /// (e.g. user denied via System Settings, or app is in a non-standard
    /// location). Surfaces in the UI so we can grey out the toggle.
    static var isRequiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Register burnrate to launch at login. Idempotent.
    static func enable() throws {
        try SMAppService.mainApp.register()
    }

    /// Unregister burnrate from launching at login. Idempotent.
    static func disable() throws {
        try SMAppService.mainApp.unregister()
    }
}
