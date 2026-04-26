import Foundation

public actor UsageSnapshotSource {
    public init() {}

    public func loadOverview() async throws -> UsageOverview {
        let now = Date()
        let codex = await CodexUsageFetcher().loadSnapshot(now: now) ?? Self.sampleCodex(now: now)
        return UsageOverview(
            snapshots: [
                codex,
                Self.sampleClaude(now: now),
            ],
            updatedAt: Date())
    }

    private static func sampleCodex(now: Date) -> ProviderUsageSnapshot {
        let local = CodexSessionWatcher().latestSnapshot()
        return local?.providerSnapshot(accountLabel: "Local Codex", now: now) ?? ProviderUsageSnapshot(
            kind: .codex,
            planName: "Plus",
            accountLabel: "Local account",
            projectLabel: "ai-usage-app",
            windows: [
                UsageWindow(
                    id: "codex-session",
                    title: "5h",
                    usedPercent: 28,
                    resetsAt: now.addingTimeInterval(68 * 60)),
                UsageWindow(
                    id: "codex-weekly",
                    title: "Weekly",
                    usedPercent: 44,
                    resetsAt: now.addingTimeInterval(2.6 * 24 * 60 * 60)),
            ],
            today: DailyUsageStats(
                requests: 42,
                inputTokens: 184_200,
                outputTokens: 61_900,
                activeMinutes: 96,
                spend: ProviderSpend(used: 4.80, limit: 25, currencyCode: "USD"),
                peakHourLabel: "current session"),
            modelMix: [
                ModelUsageShare(modelName: "gpt-5.5", percent: 100),
            ],
            workContext: nil,
            codexSession: nil,
            creditBalance: 18.4,
            extraSpend: nil,
            streakDays: 12,
            updatedAt: now)
    }

    private static func sampleClaude(now: Date) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            kind: .claude,
            planName: "Max",
            accountLabel: "Local account",
            projectLabel: "design pass",
            windows: [
                UsageWindow(
                    id: "claude-session",
                    title: "Session",
                    usedPercent: 63,
                    resetsAt: now.addingTimeInterval(32 * 60)),
                UsageWindow(
                    id: "claude-weekly",
                    title: "Weekly",
                    usedPercent: 71,
                    resetsAt: now.addingTimeInterval(4.1 * 24 * 60 * 60)),
            ],
            today: DailyUsageStats(
                requests: 31,
                inputTokens: 142_600,
                outputTokens: 48_300,
                activeMinutes: 78,
                spend: ProviderSpend(used: 3.20, limit: 20, currencyCode: "USD"),
                peakHourLabel: "9-10 AM"),
            modelMix: [
                ModelUsageShare(modelName: "opus", percent: 46),
                ModelUsageShare(modelName: "sonnet", percent: 42),
                ModelUsageShare(modelName: "haiku", percent: 12),
            ],
            creditBalance: nil,
            extraSpend: ProviderSpend(used: 3.2, limit: 20, currencyCode: "USD"),
            streakDays: 8,
            updatedAt: now)
    }
}

private struct CodexUsageFetcher {
    func loadSnapshot(now: Date) async -> ProviderUsageSnapshot? {
        let local = CodexSessionWatcher().latestSnapshot()
        if let local {
            return local.providerSnapshot(accountLabel: "Local Codex", now: now)
        }

        let payload = try? await Self.remoteUsagePayload()

        guard payload != nil else { return nil }

        let remoteWindows = Self.remoteWindows(from: payload)
        let planName = payload?.planType.map(Self.displayPlan)
        let creditBalance = Double(payload?.credits?.balance ?? "")

        return ProviderUsageSnapshot(
            kind: .codex,
            planName: planName,
            accountLabel: payload?.email ?? "Local Codex",
            projectLabel: nil,
            windows: remoteWindows,
            today: .empty,
            modelMix: [],
            workContext: nil,
            codexSession: nil,
            creditBalance: creditBalance,
            extraSpend: nil,
            streakDays: 0,
            updatedAt: now)
    }

    private static func remoteUsagePayload() async throws -> CodexUsagePayload {
        let auth = try Self.readCodexAuth()
        let request = Self.usageRequest(accessToken: auth.accessToken)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FetchError.unexpectedResponse
        }

        return try JSONDecoder().decode(CodexUsagePayload.self, from: data)
    }

    private static func remoteWindows(from payload: CodexUsagePayload?) -> [UsageWindow] {
        guard let payload else { return [] }
        let primary = payload.rateLimit.primaryWindow
        let secondary = payload.rateLimit.secondaryWindow
        return [
            UsageWindow(
                id: "codex-primary",
                title: Self.windowTitle(seconds: primary?.limitWindowSeconds) ?? "5h",
                usedPercent: primary?.usedPercent ?? 0,
                resetsAt: Self.date(fromUnixSeconds: primary?.resetAt, fallbackAfter: primary?.resetAfterSeconds)),
            UsageWindow(
                id: "codex-weekly",
                title: "Weekly",
                usedPercent: secondary?.usedPercent ?? 0,
                resetsAt: Self.date(fromUnixSeconds: secondary?.resetAt, fallbackAfter: secondary?.resetAfterSeconds)),
        ]
    }

    private static func readCodexAuth() throws -> CodexAuth {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let path = home.appendingPathComponent(".codex/auth.json")
        let data = try Data(contentsOf: path)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let tokens = json?["tokens"] as? [String: Any]
        guard let accessToken = tokens?["access_token"] as? String, !accessToken.isEmpty else {
            throw FetchError.missingAccessToken
        }
        return CodexAuth(accessToken: accessToken)
    }

    private static func usageRequest(accessToken: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("burnrate/0.1", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        return request
    }

    fileprivate static func displayPlan(_ plan: String) -> String {
        plan
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    fileprivate static func windowTitle(seconds: Int?) -> String? {
        guard let seconds else { return nil }
        let days = seconds / 86_400
        if days > 0, seconds % 86_400 == 0 { return days >= 7 ? "Weekly" : "\(days)d" }
        let hours = seconds / 3_600
        if hours > 0, seconds % 3_600 == 0 { return "\(hours)h" }
        return nil
    }

    fileprivate static func date(fromUnixSeconds seconds: Int?, fallbackAfter: Int?) -> Date? {
        if let seconds { return Date(timeIntervalSince1970: TimeInterval(seconds)) }
        if let fallbackAfter { return Date().addingTimeInterval(TimeInterval(fallbackAfter)) }
        return nil
    }

    private struct CodexAuth {
        let accessToken: String
    }

    private enum FetchError: Error {
        case missingAccessToken
        case unexpectedResponse
    }
}

private struct CodexSessionWatcher {
    func latestSnapshot() -> CodexLocalSnapshot? {
        guard let file = self.latestSessionFile() else { return nil }
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return nil }

        let thread = CodexThreadStore().thread(for: file.path)
        var sessionId = thread?.sessionId
        var directory = thread?.cwd
        var modelName = thread?.model
        var userMessageCount = 0
        var tokenSamples: [TokenSample] = []
        var firstDate: Date?
        var latestDate = thread?.updatedAt ?? Date()
        var latestRateLimit: LocalRateLimit?
        var toolCalls = 0
        var shellCommands = 0
        var patchEvents = 0
        var webSearches = 0
        var errors = 0
        var compactions = 0

        for line in content.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            let date = Self.date(from: object["timestamp"] as? String)
            if let date {
                firstDate = firstDate ?? date
                latestDate = date
            }

            guard let payload = object["payload"] as? [String: Any] else { continue }
            let topType = object["type"] as? String
            let payloadType = payload["type"] as? String

            if topType == "session_meta" {
                sessionId = payload["id"] as? String ?? sessionId
                directory = payload["cwd"] as? String ?? directory
            }

            if topType == "turn_context" {
                directory = payload["cwd"] as? String ?? directory
                modelName = payload["model"] as? String ?? modelName
            }

            if payloadType == "user_message" {
                userMessageCount += 1
            }

            if topType == "response_item", payloadType == "function_call" {
                toolCalls += 1
            }

            if payloadType == "exec_command_end" {
                shellCommands += 1
            }

            if payloadType?.contains("patch") == true {
                patchEvents += 1
            }

            if payloadType?.contains("web_search") == true {
                webSearches += 1
            }

            if topType == "error" || payloadType?.contains("error") == true {
                errors += 1
            }

            if payloadType?.contains("compact") == true {
                compactions += 1
            }

            if payloadType == "token_count" {
                latestRateLimit = Self.rateLimit(from: payload) ?? latestRateLimit

                guard let info = payload["info"] as? [String: Any],
                      let lastUsage = info["last_token_usage"] as? [String: Any]
                else { continue }

                modelName = info["model"] as? String ?? modelName
                let used = Self.int(lastUsage["total_tokens"])
                let input = Self.int(lastUsage["input_tokens"])
                let output = Self.int(lastUsage["output_tokens"])
                let cached = Self.int(lastUsage["cached_input_tokens"] ?? lastUsage["cache_read_input_tokens"])
                let reasoning = Self.int(lastUsage["reasoning_output_tokens"])
                let contextWindow = Self.int(info["model_context_window"])
                if used > 0, contextWindow > 0 {
                    tokenSamples.append(
                        TokenSample(
                            date: date ?? latestDate,
                            used: used,
                            input: input,
                            output: output,
                            cached: cached,
                            reasoning: reasoning,
                            contextWindow: contextWindow))
                }
            }
        }

        guard let latest = tokenSamples.last else { return nil }

        let totalInput = tokenSamples.reduce(0) { $0 + $1.input }
        let totalOutput = tokenSamples.reduce(0) { $0 + $1.output }
        let totalCached = tokenSamples.reduce(0) { $0 + $1.cached }
        let totalReasoning = tokenSamples.reduce(0) { $0 + $1.reasoning }
        let averageGrowth = Self.averagePositiveGrowth(tokenSamples.map(\.used)) ?? Self.average(tokenSamples.suffix(5).map(\.used))
        let activeMinutes = Self.minutes(from: firstDate, to: latestDate)

        let context = WorkContextSnapshot(
            sessionId: sessionId,
            directory: directory,
            modelName: modelName,
            contextUsedTokens: latest.used,
            contextWindowTokens: latest.contextWindow,
            averageGrowthTokens: averageGrowth,
            nextMessageTokens: latest.input + latest.output,
            userMessageCount: userMessageCount,
            updatedAt: latestDate)

        let codexSession = CodexSessionStats(
            threadTitle: thread?.title,
            gitBranch: thread?.gitBranch,
            reasoningEffort: thread?.reasoningEffort,
            cliVersion: thread?.cliVersion,
            source: thread?.source,
            approvalMode: thread?.approvalMode,
            sandboxLabel: thread?.sandboxLabel,
            sessionStartedAt: firstDate,
            lastActivityAt: latestDate,
            totalInputTokens: totalInput,
            cachedInputTokens: totalCached,
            totalOutputTokens: totalOutput,
            reasoningOutputTokens: totalReasoning,
            lastInputTokens: latest.input,
            lastOutputTokens: latest.output,
            tokenEvents: tokenSamples.count,
            toolCalls: toolCalls,
            shellCommands: shellCommands,
            patchEvents: patchEvents,
            webSearches: webSearches,
            errors: errors,
            compactions: compactions)

        let windows = latestRateLimit?.windows ?? []
        let project = directory.map { URL(fileURLWithPath: $0).lastPathComponent }
        let modelMix = modelName.map { [ModelUsageShare(modelName: $0, percent: 100)] } ?? []

        return CodexLocalSnapshot(
            context: context,
            codexSession: codexSession,
            windows: windows,
            planName: latestRateLimit?.planName,
            creditBalance: latestRateLimit?.creditBalance,
            projectLabel: project,
            today: DailyUsageStats(
                requests: userMessageCount,
                inputTokens: totalInput,
                outputTokens: totalOutput,
                activeMinutes: activeMinutes,
                spend: nil,
                peakHourLabel: "current session"),
            modelMix: modelMix)
    }

    private func latestSessionFile() -> URL? {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])
        else { return nil }

        var candidates: [(url: URL, modified: Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            candidates.append((url, values?.contentModificationDate ?? .distantPast))
        }

        return candidates.max { $0.modified < $1.modified }?.url
    }

    private static func rateLimit(from payload: [String: Any]) -> LocalRateLimit? {
        guard let rateLimits = payload["rate_limits"] as? [String: Any] else { return nil }

        var windows: [UsageWindow] = []
        if let primary = rateLimits["primary"] as? [String: Any] {
            windows.append(
                UsageWindow(
                    id: "codex-local-primary",
                    title: Self.windowTitle(minutes: Self.int(primary["window_minutes"])) ?? "5h",
                    usedPercent: Self.double(primary["used_percent"]),
                    resetsAt: Self.date(fromUnixSeconds: Self.int(primary["resets_at"]))))
        }

        if let secondary = rateLimits["secondary"] as? [String: Any] {
            windows.append(
                UsageWindow(
                    id: "codex-local-weekly",
                    title: Self.windowTitle(minutes: Self.int(secondary["window_minutes"])) ?? "Weekly",
                    usedPercent: Self.double(secondary["used_percent"]),
                    resetsAt: Self.date(fromUnixSeconds: Self.int(secondary["resets_at"]))))
        }

        let credits = rateLimits["credits"] as? [String: Any]
        return LocalRateLimit(
            windows: windows,
            planName: (rateLimits["plan_type"] as? String).map(CodexUsageFetcher.displayPlan),
            creditBalance: Double(credits?["balance"] as? String ?? ""))
    }

    private static func windowTitle(minutes: Int) -> String? {
        guard minutes > 0 else { return nil }
        if minutes == 10_080 { return "Weekly" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440)d" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }

    private static func averagePositiveGrowth(_ values: [Int]) -> Int? {
        let deltas = zip(values, values.dropFirst())
            .map { $1 - $0 }
            .filter { $0 > 0 }
            .suffix(8)
        guard !deltas.isEmpty else { return nil }
        return deltas.reduce(0, +) / deltas.count
    }

    private static func average(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    private static func minutes(from start: Date?, to end: Date?) -> Int {
        guard let start, let end else { return 0 }
        return max(0, Int(end.timeIntervalSince(start) / 60))
    }

    private static func int(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? String { return Int(value) ?? 0 }
        return 0
    }

    private static func double(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) ?? 0 }
        return 0
    }

    private static func date(fromUnixSeconds seconds: Int) -> Date? {
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    private static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        if let date = Self.isoDateFormatter.date(from: string) {
            return date
        }
        return Self.isoDateFormatterWithoutFractions.date(from: string)
    }

    private static let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoDateFormatterWithoutFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private struct TokenSample {
        let date: Date
        let used: Int
        let input: Int
        let output: Int
        let cached: Int
        let reasoning: Int
        let contextWindow: Int
    }
}

private struct CodexLocalSnapshot {
    let context: WorkContextSnapshot
    let codexSession: CodexSessionStats
    let windows: [UsageWindow]
    let planName: String?
    let creditBalance: Double?
    let projectLabel: String?
    let today: DailyUsageStats
    let modelMix: [ModelUsageShare]

    func providerSnapshot(accountLabel: String, now: Date) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            kind: .codex,
            planName: self.planName,
            accountLabel: accountLabel,
            projectLabel: self.projectLabel,
            windows: self.windows,
            today: self.today,
            modelMix: self.modelMix,
            workContext: self.context,
            codexSession: self.codexSession,
            creditBalance: self.creditBalance,
            extraSpend: nil,
            streakDays: 0,
            updatedAt: now)
    }
}

private struct LocalRateLimit {
    let windows: [UsageWindow]
    let planName: String?
    let creditBalance: Double?
}

private struct CodexThreadStore {
    func thread(for rolloutPath: String) -> ThreadMetadata? {
        let db = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/state_5.sqlite")
        guard FileManager.default.fileExists(atPath: db.path) else { return nil }

        let query = """
        select id,title,cwd,coalesce(model,''),coalesce(reasoning_effort,''),coalesce(git_branch,''),source,tokens_used,coalesce(updated_at_ms,updated_at * 1000),coalesce(cli_version,''),approval_mode,sandbox_policy
        from threads
        where rollout_path=\(Self.sqlQuote(rolloutPath))
        order by updated_at_ms desc
        limit 1
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-tabs", db.path, query]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let line = String(data: data, encoding: .utf8)?
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
        else { return nil }

        let fields = String(line).components(separatedBy: "\t")
        guard fields.count >= 12 else { return nil }

        return ThreadMetadata(
            sessionId: Self.nilIfEmpty(fields[0]),
            title: Self.nilIfEmpty(fields[1]),
            cwd: Self.nilIfEmpty(fields[2]),
            model: Self.nilIfEmpty(fields[3]),
            reasoningEffort: Self.nilIfEmpty(fields[4]),
            gitBranch: Self.nilIfEmpty(fields[5]),
            source: Self.nilIfEmpty(fields[6]),
            tokensUsed: Int(fields[7]) ?? 0,
            updatedAt: Self.date(fromMilliseconds: fields[8]),
            cliVersion: Self.nilIfEmpty(fields[9]),
            approvalMode: Self.nilIfEmpty(fields[10]),
            sandboxLabel: Self.sandboxLabel(from: fields[11]))
    }

    private static func sqlQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private static func nilIfEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }

    private static func date(fromMilliseconds value: String) -> Date? {
        guard let milliseconds = Double(value), milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }

    private static func sandboxLabel(from raw: String) -> String? {
        if raw.contains("danger-full-access") { return "full access" }
        if raw.contains("workspace-write") { return "workspace write" }
        if raw.contains("read-only") { return "read only" }
        return raw.isEmpty ? nil : raw
    }
}

private struct ThreadMetadata {
    let sessionId: String?
    let title: String?
    let cwd: String?
    let model: String?
    let reasoningEffort: String?
    let gitBranch: String?
    let source: String?
    let tokensUsed: Int
    let updatedAt: Date?
    let cliVersion: String?
    let approvalMode: String?
    let sandboxLabel: String?
}

private struct CodexUsagePayload: Decodable {
    let email: String?
    let planType: String?
    let rateLimit: RateLimit
    let credits: Credits?

    enum CodingKeys: String, CodingKey {
        case email
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
    }

    struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct Window: Decodable {
        let usedPercent: Double
        let limitWindowSeconds: Int?
        let resetAfterSeconds: Int?
        let resetAt: Int?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case limitWindowSeconds = "limit_window_seconds"
            case resetAfterSeconds = "reset_after_seconds"
            case resetAt = "reset_at"
        }
    }

    struct Credits: Decodable {
        let balance: String?
    }
}
