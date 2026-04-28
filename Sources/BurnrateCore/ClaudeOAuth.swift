import Foundation
import Security

/// Reads the Claude Code OAuth credential from the macOS Keychain or the
/// `~/.claude/.credentials.json` fallback used on Linux. Surfaces the access
/// token plus optional plan metadata.
public struct ClaudeOAuthCredentials: Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAtUnixMs: Int64?
    public let subscriptionType: String?
    public let scopes: [String]
}

public enum ClaudeOAuthCredentialReader {
    /// Reads from Keychain (`Claude Code-credentials`) first, then the
    /// `~/.claude/.credentials.json` file. Returns nil when nothing is found
    /// or the user denies the Keychain prompt.
    public static func read(claudeRoot: URL) -> ClaudeOAuthCredentials? {
        if let creds = readKeychain() { return creds }
        if let creds = readFile(at: claudeRoot.appendingPathComponent(".credentials.json")) { return creds }
        return nil
    }

    private static func readKeychain() -> ClaudeOAuthCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return decode(data: data)
    }

    private static func readFile(at url: URL) -> ClaudeOAuthCredentials? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data: data)
    }

    private static func decode(data: Data) -> ClaudeOAuthCredentials? {
        // The credential is stored as JSON with a `claudeAiOauth` envelope:
        //   { "claudeAiOauth": { "accessToken": "...", "refreshToken": "...",
        //                        "expiresAt": 1700000000000,
        //                        "scopes": [...], "subscriptionType": "max" } }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let envelope = json["claudeAiOauth"] as? [String: Any] {
                return parseEnvelope(envelope)
            }
            // Some forks store the envelope at the root.
            return parseEnvelope(json)
        }
        // Final fallback: plain string token.
        if let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty
        {
            return ClaudeOAuthCredentials(
                accessToken: token,
                refreshToken: nil,
                expiresAtUnixMs: nil,
                subscriptionType: nil,
                scopes: [])
        }
        return nil
    }

    private static func parseEnvelope(_ json: [String: Any]) -> ClaudeOAuthCredentials? {
        guard let token = (json["accessToken"] as? String)
            ?? (json["access_token"] as? String),
            !token.isEmpty
        else { return nil }
        return ClaudeOAuthCredentials(
            accessToken: token,
            refreshToken: (json["refreshToken"] as? String) ?? (json["refresh_token"] as? String),
            expiresAtUnixMs: (json["expiresAt"] as? Int64)
                ?? (json["expires_at"] as? Int64)
                ?? (json["expiresAt"] as? Int).map(Int64.init)
                ?? (json["expires_at"] as? Int).map(Int64.init),
            subscriptionType: (json["subscriptionType"] as? String) ?? (json["subscription_type"] as? String),
            scopes: (json["scopes"] as? [String]) ?? [])
    }
}

/// Fetches the undocumented `https://api.anthropic.com/api/oauth/usage` endpoint
/// (anthropic-beta: oauth-2025-04-20). Mirrors what CodexBar's
/// `ClaudeOAuthUsageFetcher` does — the cleanest signal we can get for window
/// utilisation and reset timestamps.
public struct ClaudeOAuthUsage: Sendable {
    public struct Window: Sendable {
        public let utilization: Double  // 0...100 (as returned by Anthropic)
        public let resetsAt: Date?
    }

    public struct ExtraUsage: Sendable {
        public let isEnabled: Bool
        public let monthlyLimit: Double
        public let usedCredits: Double
        public let utilization: Double
        public let currency: String
    }

    public let fiveHour: Window?
    public let sevenDay: Window?
    public let sevenDayOpus: Window?
    public let sevenDaySonnet: Window?
    public let sevenDayOAuthApps: Window?
    public let extraUsage: ExtraUsage?
    public let rateLimitTier: String?
    /// Subscription type from the keychain credential envelope (e.g.
    /// "max", "pro", "max_20x"). Carried alongside the API response
    /// so plan-name resolution can fall back on it when the API
    /// doesn't return `rate_limit_tier`. The keychain value is the
    /// most reliable local plan signal Claude Code stores.
    public let subscriptionType: String?

    public var hasAnyWindow: Bool {
        return fiveHour != nil || sevenDay != nil || sevenDayOpus != nil || sevenDaySonnet != nil
    }
}

public actor ClaudeOAuthUsageFetcher {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public init() {}

    public func fetch(credentials: ClaudeOAuthCredentials) async -> ClaudeOAuthUsage? {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("burnrate/0.1 (claude-code/2.1)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let raw = try JSONDecoder().decode(OAuthUsageRaw.self, from: data)
            return Self.decode(raw, subscriptionType: credentials.subscriptionType)
        } catch {
            return nil
        }
    }

    private static func decode(
        _ raw: OAuthUsageRaw,
        subscriptionType: String?) -> ClaudeOAuthUsage
    {
        return ClaudeOAuthUsage(
            fiveHour: raw.fiveHour.map(window),
            sevenDay: raw.sevenDay.map(window),
            sevenDayOpus: raw.sevenDayOpus.map(window),
            sevenDaySonnet: raw.sevenDaySonnet.map(window),
            sevenDayOAuthApps: raw.sevenDayOAuthApps.map(window),
            extraUsage: raw.extraUsage.map { extra in
                ClaudeOAuthUsage.ExtraUsage(
                    isEnabled: extra.isEnabled ?? false,
                    monthlyLimit: extra.monthlyLimit ?? 0,
                    usedCredits: extra.usedCredits ?? 0,
                    utilization: extra.utilization ?? 0,
                    currency: extra.currency ?? "USD")
            },
            rateLimitTier: raw.rateLimitTier,
            subscriptionType: subscriptionType)
    }

    private static func window(_ raw: WindowRaw) -> ClaudeOAuthUsage.Window {
        return ClaudeOAuthUsage.Window(
            utilization: raw.utilization ?? 0,
            resetsAt: ClaudeDate.parse(raw.resetsAt))
    }
}

private struct OAuthUsageRaw: Decodable {
    let fiveHour: WindowRaw?
    let sevenDay: WindowRaw?
    let sevenDayOpus: WindowRaw?
    let sevenDaySonnet: WindowRaw?
    let sevenDayOAuthApps: WindowRaw?
    let sevenDayDesign: WindowRaw?
    let sevenDayRoutines: WindowRaw?
    let extraUsage: ExtraUsageRaw?
    let rateLimitTier: String?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOAuthApps = "seven_day_oauth_apps"
        case sevenDayDesign = "seven_day_design"
        case sevenDayRoutines = "seven_day_routines"
        case extraUsage = "extra_usage"
        case rateLimitTier = "rate_limit_tier"
    }
}

private struct WindowRaw: Decodable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

private struct ExtraUsageRaw: Decodable {
    let isEnabled: Bool?
    let monthlyLimit: Double?
    let usedCredits: Double?
    let utilization: Double?
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
        case currency
    }
}
