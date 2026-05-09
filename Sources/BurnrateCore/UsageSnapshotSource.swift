import Foundation

public actor UsageSnapshotSource {
    private let codexFetcher = CodexUsageFetcher()
    private let claudeWatcher = ClaudeUsageWatcher()

    public init() {}

    public func loadOverview(
        recentDailySpend: Double? = nil,
        pinnedClaudeSessionId: String? = nil,
        pinnedCodexSessionId: String? = nil,
        focusedProvider: ProviderKind? = nil,
        existingOverview: UsageOverview? = nil) async throws -> UsageOverview
    {
        let now = Date()
        if let focusedProvider, let existingOverview, !existingOverview.snapshots.isEmpty {
            switch focusedProvider {
            case .codex:
                let base = existingOverview.snapshot(for: .codex)
                let codex = await self.codexFetcher.loadPreviewSnapshot(
                    now: now,
                    pinnedSessionId: pinnedCodexSessionId,
                    preserving: base)
                return Self.replacing(.codex, with: codex, in: existingOverview, updatedAt: now)
            case .claude:
                let base = existingOverview.snapshot(for: .claude)
                let claude = await self.claudeWatcher.loadPreviewSnapshot(
                    now: now,
                    pinnedSessionId: pinnedClaudeSessionId,
                    preserving: base)
                return Self.replacing(.claude, with: claude, in: existingOverview, updatedAt: now)
            }
        }

        async let codexAsync = self.codexFetcher.loadSnapshot(
            now: now,
            pinnedSessionId: pinnedCodexSessionId)
        async let claudeAsync = self.claudeWatcher.loadSnapshot(
            now: now,
            recentDailySpend: recentDailySpend,
            pinnedSessionId: pinnedClaudeSessionId)
        let snapshots = await [codexAsync, claudeAsync].compactMap { $0 }
        return UsageOverview(
            snapshots: snapshots,
            updatedAt: Date())
    }

    public func loadFastOverview(
        pinnedClaudeSessionId: String? = nil,
        pinnedCodexSessionId: String? = nil) async -> UsageOverview
    {
        let now = Date()
        async let codexAsync = self.codexFetcher.loadPreviewSnapshot(
            now: now,
            pinnedSessionId: pinnedCodexSessionId,
            preserving: nil)
        async let claudeAsync = self.claudeWatcher.loadPreviewSnapshot(
            now: now,
            pinnedSessionId: pinnedClaudeSessionId,
            preserving: nil)
        let snapshots = await [codexAsync, claudeAsync].compactMap { $0 }
        return UsageOverview(
            snapshots: snapshots,
            updatedAt: Date())
    }

    private static func replacing(
        _ provider: ProviderKind,
        with snapshot: ProviderUsageSnapshot?,
        in overview: UsageOverview,
        updatedAt: Date) -> UsageOverview
    {
        var snapshots = overview.snapshots.filter { $0.kind != provider }
        if let snapshot {
            snapshots.append(snapshot)
        }
        let order = Dictionary(uniqueKeysWithValues: ProviderKind.allCases.enumerated().map { ($0.element, $0.offset) })
        snapshots.sort { (order[$0.kind] ?? 99) < (order[$1.kind] ?? 99) }
        return UsageOverview(snapshots: snapshots, updatedAt: updatedAt)
    }

}

private struct CodexUsageFetcher {
    func loadSnapshot(now: Date, pinnedSessionId: String? = nil) async -> ProviderUsageSnapshot? {
        let watcher = CodexSessionWatcher()
        let local = watcher.latestSnapshot(pinnedSessionId: pinnedSessionId, fast: true)
        let liveSessions = watcher.liveSessions(now: now)
        let surface = CodexSurfaceScanner().scan(
            now: now,
            localSnapshot: local,
            liveSessions: liveSessions)
        if let local {
            return local.providerSnapshot(
                accountLabel: "Local Codex",
                now: now,
                liveSessions: liveSessions,
                surface: surface)
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
            codexSurface: surface,
            creditBalance: creditBalance,
            extraSpend: nil,
            streakDays: 0,
            updatedAt: now)
    }

    func loadPreviewSnapshot(
        now: Date,
        pinnedSessionId: String?,
        preserving base: ProviderUsageSnapshot?) async -> ProviderUsageSnapshot?
    {
        let watcher = CodexSessionWatcher()
        let local = watcher.latestSnapshot(pinnedSessionId: pinnedSessionId, fast: true)
        guard let local else { return base }
        let liveSessions = watcher.liveSessions(now: now)
        return local.providerSnapshot(
            accountLabel: base?.accountLabel ?? "Local Codex",
            now: now,
            liveSessions: liveSessions.isEmpty ? (base?.liveSessions ?? []) : liveSessions,
            surface: base?.codexSurface)
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
    func latestSnapshot(pinnedSessionId: String? = nil, fast: Bool = false) -> CodexLocalSnapshot? {
        let pinnedFile = pinnedSessionId.flatMap { self.sessionFile(sessionId: $0) }
        guard let file = pinnedFile ?? self.latestSessionFile() else { return nil }
        guard let content = Self.sessionText(from: file, fast: fast) else { return nil }

        let thread = CodexThreadStore().thread(for: file.path)
        var sessionId = thread?.sessionId
        var directory = thread?.cwd
        var modelName = thread?.model
        var userMessageCount = 0
        var tokenSamples: [TokenSample] = []
        var firstDate: Date?
        var latestDate = thread?.updatedAt ?? Date()
        var observedRateLimits: [LocalRateLimit] = []
        var toolCalls = 0
        var shellCommands = 0
        var patchEvents = 0
        var webSearches = 0
        var errors = 0
        var compactions = 0
        var flightEvents: [CodexFlightEvent] = []

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
                if shellCommands <= 3 || shellCommands % 8 == 0 {
                    flightEvents.append(
                        CodexFlightEvent(
                            timestamp: date ?? latestDate,
                            kind: .shell,
                            title: "Shell activity",
                            detail: "\(shellCommands) commands this session",
                            tokenImpact: nil))
                }
            }

            if payloadType?.contains("patch") == true {
                patchEvents += 1
                flightEvents.append(
                    CodexFlightEvent(
                        timestamp: date ?? latestDate,
                        kind: .patch,
                        title: "Code edit",
                        detail: "\(patchEvents) patch events seen",
                        tokenImpact: nil))
            }

            if payloadType?.contains("web_search") == true {
                webSearches += 1
                flightEvents.append(
                    CodexFlightEvent(
                        timestamp: date ?? latestDate,
                        kind: .web,
                        title: "Web search",
                        detail: "\(webSearches) searches this session",
                        tokenImpact: nil))
            }

            if topType == "error" || payloadType?.contains("error") == true {
                errors += 1
                flightEvents.append(
                    CodexFlightEvent(
                        timestamp: date ?? latestDate,
                        kind: .error,
                        title: "Error signal",
                        detail: "\(errors) errors this session",
                        tokenImpact: nil))
            }

            if payloadType?.contains("compact") == true {
                compactions += 1
                flightEvents.append(
                    CodexFlightEvent(
                        timestamp: date ?? latestDate,
                        kind: .compaction,
                        title: "Context compaction",
                        detail: "\(compactions) compactions seen",
                        tokenImpact: nil))
            }

            if payloadType == "token_count" {
                if let rateLimit = Self.rateLimit(from: payload) {
                    observedRateLimits.append(rateLimit)
                }

                guard let info = payload["info"] as? [String: Any],
                      let lastUsage = info["last_token_usage"] as? [String: Any]
                else { continue }
                let totalUsage = info["total_token_usage"] as? [String: Any]

                modelName = info["model"] as? String ?? modelName
                let used = Self.int(lastUsage["total_tokens"])
                let input = Self.int(lastUsage["input_tokens"])
                let output = Self.int(lastUsage["output_tokens"])
                let cached = Self.int(lastUsage["cached_input_tokens"] ?? lastUsage["cache_read_input_tokens"])
                let reasoning = Self.int(lastUsage["reasoning_output_tokens"])
                let cumulativeInput = Self.int(totalUsage?["input_tokens"])
                let cumulativeOutput = Self.int(totalUsage?["output_tokens"])
                let cumulativeCached = Self.int(totalUsage?["cached_input_tokens"] ?? totalUsage?["cache_read_input_tokens"])
                let cumulativeReasoning = Self.int(totalUsage?["reasoning_output_tokens"])
                let contextWindow = Self.int(info["model_context_window"])
                if used > 0, contextWindow > 0 {
                    let turnTokens = input + output
                    if turnTokens >= 15_000 {
                        flightEvents.append(
                            CodexFlightEvent(
                                timestamp: date ?? latestDate,
                                kind: .tokenSpike,
                                title: "Large turn",
                                detail: "\(Self.compact(input)) in / \(Self.compact(output)) out",
                                tokenImpact: turnTokens))
                    }
                    tokenSamples.append(
                        TokenSample(
                            date: date ?? latestDate,
                            used: used,
                            input: input,
                            output: output,
                            cached: cached,
                            reasoning: reasoning,
                            cumulativeInput: cumulativeInput,
                            cumulativeOutput: cumulativeOutput,
                            cumulativeCached: cumulativeCached,
                            cumulativeReasoning: cumulativeReasoning,
                            contextWindow: contextWindow))
                }
            }
        }

        guard let latest = tokenSamples.last else { return nil }
        let mergedRateLimit = Self.mergeRateLimits(observedRateLimits)

        let totalInput = latest.cumulativeInput > 0
            ? latest.cumulativeInput
            : tokenSamples.reduce(0) { $0 + $1.input }
        let totalOutput = latest.cumulativeOutput > 0
            ? latest.cumulativeOutput
            : tokenSamples.reduce(0) { $0 + $1.output }
        let totalCached = latest.cumulativeCached > 0
            ? latest.cumulativeCached
            : tokenSamples.reduce(0) { $0 + $1.cached }
        let totalReasoning = latest.cumulativeReasoning > 0
            ? latest.cumulativeReasoning
            : tokenSamples.reduce(0) { $0 + $1.reasoning }
        // Per-turn growth = mean of positive deltas in `used` tokens
        // (filters compactions, since those produce negatives). Returns
        // nil when no positive deltas exist yet — we deliberately do NOT
        // fall back to averaging raw `.used` values: those are absolute
        // sizes (~100K–1M), not per-turn deltas (~5–20K), and mixing
        // units made `estimatedMessagesRemaining` nonsensical.
        let averageGrowth = Self.averagePositiveGrowth(tokenSamples.map(\.used))
        let lastContextDelta = Self.lastPositiveGrowth(tokenSamples.map(\.used))
        let activeMinutes = Self.minutes(from: firstDate, to: latestDate)
        let project = directory.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Codex"
        let curatedFlightEvents = Self.curatedFlightEvents(flightEvents)
        let biggestBurnEvent = curatedFlightEvents
            .filter { $0.tokenImpact != nil }
            .max { ($0.tokenImpact ?? 0) < ($1.tokenImpact ?? 0) }

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

        let insight = Self.insight(
            context: context,
            latest: latest,
            windows: mergedRateLimit?.windows ?? [],
            totalInput: totalInput,
            totalCached: totalCached,
            totalOutput: totalOutput,
            errors: errors,
            compactions: compactions,
            shellCommands: shellCommands,
            webSearches: webSearches,
            biggestBurn: biggestBurnEvent,
            lastContextDelta: lastContextDelta,
            activeMinutes: activeMinutes,
            latestDate: latestDate)

        let codexSession = CodexSessionStats(
            insight: insight,
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
            lastCachedInputTokens: latest.cached,
            lastReasoningOutputTokens: latest.reasoning,
            tokenEvents: tokenSamples.count,
            toolCalls: toolCalls,
            shellCommands: shellCommands,
            patchEvents: patchEvents,
            webSearches: webSearches,
            errors: errors,
            compactions: compactions,
            flightEvents: curatedFlightEvents,
            biggestBurnEvent: biggestBurnEvent)

        let windows = mergedRateLimit?.windows ?? []
        let modelMix = modelName.map { [ModelUsageShare(modelName: $0, percent: 100)] } ?? []
        let memory = CodexHistoryStore().record(
            sessionId: sessionId ?? file.lastPathComponent,
            projectName: project,
            threadTitle: thread?.title,
            totalTokens: totalInput + totalOutput,
            turnCount: max(1, tokenSamples.count),
            updatedAt: latestDate)

        return CodexLocalSnapshot(
            context: context,
            codexSession: codexSession,
            windows: windows,
            planName: mergedRateLimit?.planName,
            creditBalance: mergedRateLimit?.creditBalance,
            projectLabel: project,
            memory: memory,
            today: DailyUsageStats(
                requests: userMessageCount,
                inputTokens: totalInput,
                outputTokens: totalOutput,
                activeMinutes: activeMinutes,
                spend: nil,
                peakHourLabel: "current session"),
            modelMix: modelMix)
    }

    private static func sessionText(from url: URL, fast: Bool) -> String? {
        if !fast {
            return try? String(contentsOf: url, encoding: .utf8)
        }

        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let headBytes = 64 * 1024
        let tailBytes = 1_500_000
        if fileSize <= headBytes + tailBytes {
            return try? String(contentsOf: url, encoding: .utf8)
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let headData = (try? handle.read(upToCount: headBytes)) ?? Data()
        let tailOffset = UInt64(max(0, fileSize - tailBytes))
        do {
            try handle.seek(toOffset: tailOffset)
        } catch {
            return String(data: headData, encoding: .utf8)
        }
        let tailData = (try? handle.readToEnd()) ?? Data()

        let head = String(data: headData, encoding: .utf8) ?? ""
        let tail = String(data: tailData, encoding: .utf8) ?? ""
        return head + "\n" + tail
    }

    private static func insight(
        context: WorkContextSnapshot,
        latest: TokenSample,
        windows: [UsageWindow],
        totalInput: Int,
        totalCached: Int,
        totalOutput: Int,
        errors: Int,
        compactions: Int,
        shellCommands: Int,
        webSearches: Int,
        biggestBurn: CodexFlightEvent?,
        lastContextDelta: Int?,
        activeMinutes: Int,
        latestDate: Date) -> CodexSessionInsight
    {
        let primaryUsedPercent = windows.first?.usedPercent ?? 0
        let messagesRemaining = context.estimatedMessagesRemaining
        let idleSeconds = max(0, Int(Date().timeIntervalSince(latestDate)))
        let lastTurnTokens = latest.input + latest.output
        let newContextTokens = lastContextDelta ?? 0
        let lastTurnShare = context.contextWindowTokens > 0
            ? Double(newContextTokens) / Double(context.contextWindowTokens) * 100
            : 0
        let tokensPerMinute = activeMinutes > 0
            ? max(0, (totalInput + totalOutput) / activeMinutes)
            : 0
        let cacheShare = totalInput > 0 ? Double(totalCached) / Double(totalInput) * 100 : 0
        let lastCacheShare = latest.input > 0 ? Double(latest.cached) / Double(latest.input) * 100 : 0

        let health: CodexThreadHealth
        let recommendation: String
        let riskReason: String

        if errors > 0, idleSeconds > 300 {
            health = .stuck
            recommendation = "Check the last command before continuing."
            riskReason = "The latest session has errors and has been idle for \(idleSeconds / 60)m."
        } else if context.contextUsedPercent >= 86 || primaryUsedPercent >= 90 || (messagesRemaining ?? 99) <= 2 {
            health = .tight
            recommendation = "Wrap this thread and start fresh soon."
            riskReason = "Context or the 5h burst window is close to the edge."
        } else if context.contextUsedPercent >= 70 || primaryUsedPercent >= 75 || (messagesRemaining ?? 99) <= 5 {
            health = .watch
            recommendation = "Keep the next ask focused."
            riskReason = "The session is still usable, but pressure is building."
        } else if cacheShare >= 70, latest.used < 65_000 {
            health = .efficient
            recommendation = "Keep going in this thread."
            riskReason = "The thread is reusing context efficiently."
        } else {
            health = .healthy
            recommendation = "Good room for more work."
            riskReason = "No major pressure signal is active."
        }

        let driver: (String, String)
        if latest.input > 30_000, lastCacheShare >= 70 {
            driver = ("Context replay", "\(Int(lastCacheShare.rounded()))% of last input was cached")
        } else if latest.input > 30_000 {
            driver = ("Large prompt", "\(Self.compact(latest.input)) input tokens last turn")
        } else if webSearches > 0, latest.input > 15_000 {
            driver = ("Web context", "\(webSearches) searches added context")
        } else if shellCommands > 8 {
            driver = ("Tool loop", "\(shellCommands) shell commands this session")
        } else if compactions > 0 {
            driver = ("Compaction", "\(compactions) context compactions seen")
        } else if latest.reasoning > 0 {
            driver = ("Reasoning", "\(Self.compact(latest.reasoning)) reasoning tokens last turn")
        } else {
            driver = ("Steady burn", "\(Self.compact(lastTurnTokens)) tokens last turn")
        }

        let forecast: String
        if let messagesRemaining {
            if messagesRemaining <= 2 {
                forecast = "~\(messagesRemaining) focused turns left"
            } else if messagesRemaining > 99 {
                forecast = "Plenty of context left"
            } else {
                forecast = "~\(messagesRemaining) turns at this pace"
            }
        } else {
            forecast = "Learning this thread's pace"
        }

        let resetPlan: String
        if primaryUsedPercent >= 85 {
            resetPlan = "The 5h window is the bottleneck right now."
        } else if let biggestBurn {
            resetPlan = "Biggest burn: \(biggestBurn.title.lowercased()) at \(Self.compact(biggestBurn.tokenImpact ?? 0))."
        } else if context.contextUsedPercent >= 70 {
            resetPlan = "Context is the bottleneck before the reset."
        } else {
            resetPlan = "Current pace should fit this window."
        }

        return CodexSessionInsight(
            health: health,
            recommendation: recommendation,
            primaryDriver: driver.0,
            driverDetail: driver.1,
            forecast: forecast,
            riskReason: riskReason,
            resetPlan: resetPlan,
            lastTurnSharePercent: lastTurnShare,
            projectedTurnsRemaining: messagesRemaining,
            tokensPerMinute: tokensPerMinute)
    }

    private static func curatedFlightEvents(_ events: [CodexFlightEvent]) -> [CodexFlightEvent] {
        let significant = events.filter { event in
            switch event.kind {
            case .tokenSpike, .error, .compaction, .web:
                return true
            case .shell, .patch:
                return event.tokenImpact != nil
            }
        }

        let fallback = significant.isEmpty ? events : significant
        return Array(fallback.suffix(5).reversed())
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

    private func sessionFile(sessionId: String) -> URL? {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])
        else { return nil }

        for case let url as URL in enumerator
        where url.pathExtension == "jsonl"
        {
            let filenameId = url.deletingPathExtension().lastPathComponent
            let canonicalId = Self.rolloutSessionId(from: url)
            if filenameId == sessionId || canonicalId == sessionId {
                return url
            }
        }
        return nil
    }

    /// All Codex jsonl session files modified within `thresholdSeconds`,
    /// converted to `LiveSession` records. Project name is extracted by
    /// reading the leading `session_meta`/`turn_context` payload of each
    /// file (the cwd lives there). Falls back to the filename basename.
    func liveSessions(now: Date, thresholdSeconds: TimeInterval = 1_800) -> [LiveSession] {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])
        else { return [] }

        let cutoff = now.addingTimeInterval(-thresholdSeconds)
        var live: [LiveSession] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate),
                  mtime >= cutoff
            else { continue }
            let projectName = Self.extractProjectName(from: url)
                ?? url.deletingPathExtension().lastPathComponent
            let metadata = CodexThreadStore().thread(for: url.path)
            let sessionId = metadata?.sessionId
                ?? Self.rolloutSessionId(from: url)
                ?? url.deletingPathExtension().lastPathComponent
            let displayName = Self.cleanDisplayName(metadata?.title)
                ?? Self.extractFirstUserMessage(from: url)
            live.append(LiveSession(
                sessionId: sessionId,
                projectName: projectName,
                lastActivityAt: mtime,
                displayName: displayName))
        }
        return live.sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    private static func rolloutSessionId(from url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
        guard name.count >= 36 else { return nil }
        let suffix = String(name.suffix(36))
        let pattern = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#
        guard suffix.range(of: pattern, options: .regularExpression) != nil else {
            return nil
        }
        return suffix
    }

    private static func extractProjectName(from url: URL) -> String? {
        // Read the leading slice of the jsonl — the session_meta record
        // (with `cwd`) is on or near line 1, so 8KB is more than enough.
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 8192),
              let text = String(data: data, encoding: .utf8)
        else { return nil }

        for line in text.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            if let payload = obj["payload"] as? [String: Any],
               let cwd = payload["cwd"] as? String
            {
                return URL(fileURLWithPath: cwd).lastPathComponent
            }
        }
        return nil
    }

    private static func extractFirstUserMessage(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 256 * 1024),
              let text = String(data: data, encoding: .utf8)
        else { return nil }

        var inspected = 0
        for line in text.split(separator: "\n") {
            inspected += 1
            if inspected > 220 { break }
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  payload["type"] as? String == "user_message"
            else { continue }
            let text = Self.string(fromMessagePayload: payload)
            if let cleaned = Self.cleanDisplayName(text) {
                return cleaned
            }
        }
        return nil
    }

    private static func string(fromMessagePayload payload: [String: Any]) -> String? {
        if let text = payload["text"] as? String { return text }
        if let message = payload["message"] as? String { return message }
        if let text = payload["content"] as? String { return text }
        if let content = payload["content"] as? [[String: Any]] {
            return content.compactMap { item in
                item["text"] as? String
            }.joined(separator: " ")
        }
        return nil
    }

    private static func cleanDisplayName(_ text: String?) -> String? {
        guard let text else { return nil }
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty,
              !collapsed.hasPrefix("/"),
              !collapsed.lowercased().contains("<environment_context>")
        else { return nil }
        if collapsed.count <= 72 { return collapsed }
        return String(collapsed.prefix(71)) + "…"
    }

    private static func rateLimit(from payload: [String: Any]) -> LocalRateLimit? {
        guard let rateLimits = payload["rate_limits"] as? [String: Any] else { return nil }

        let limitID = (rateLimits["limit_id"] as? String) ?? "codex"
        let limitName = rateLimits["limit_name"] as? String
        var windows: [UsageWindow] = []
        if let primary = rateLimits["primary"] as? [String: Any] {
            windows.append(
                UsageWindow(
                    id: "codex-local-\(limitID)-primary",
                    title: Self.windowTitle(minutes: Self.int(primary["window_minutes"])) ?? "5h",
                    usedPercent: Self.double(primary["used_percent"]),
                    resetsAt: Self.date(fromUnixSeconds: Self.int(primary["resets_at"]))))
        }

        if let secondary = rateLimits["secondary"] as? [String: Any] {
            windows.append(
                UsageWindow(
                    id: "codex-local-\(limitID)-weekly",
                    title: Self.windowTitle(minutes: Self.int(secondary["window_minutes"])) ?? "Weekly",
                    usedPercent: Self.double(secondary["used_percent"]),
                    resetsAt: Self.date(fromUnixSeconds: Self.int(secondary["resets_at"]))))
        }

        let credits = rateLimits["credits"] as? [String: Any]
        return LocalRateLimit(
            limitID: limitID,
            limitName: limitName,
            windows: windows,
            planName: (rateLimits["plan_type"] as? String).map(CodexUsageFetcher.displayPlan),
            creditBalance: Double(credits?["balance"] as? String ?? ""))
    }

    private static func mergeRateLimits(_ limits: [LocalRateLimit]) -> LocalRateLimit? {
        guard !limits.isEmpty else { return nil }
        let allWindows = limits.flatMap(\.windows)
        let primary = Self.mostConstrainedWindow(
            in: allWindows,
            id: "codex-local-primary",
            title: "5h",
            matching: { window in
                let title = window.title.lowercased()
                return !title.contains("weekly")
                    && !title.contains("week")
                    && !title.contains("7d")
            })
        let weekly = Self.mostConstrainedWindow(
            in: allWindows,
            id: "codex-local-weekly",
            title: "Weekly",
            matching: { window in
                let title = window.title.lowercased()
                return title.contains("weekly")
                    || title.contains("week")
                    || title.contains("7d")
            })
        let planName = limits.compactMap(\.planName).last
        let creditBalance = limits.compactMap(\.creditBalance).last
        return LocalRateLimit(
            limitID: "codex-merged",
            limitName: nil,
            windows: [primary, weekly].compactMap { $0 },
            planName: planName,
            creditBalance: creditBalance)
    }

    private static func mostConstrainedWindow(
        in windows: [UsageWindow],
        id: String,
        title: String,
        matching predicate: (UsageWindow) -> Bool) -> UsageWindow?
    {
        let candidates = windows.filter(predicate)
        guard let strongest = candidates.max(by: { lhs, rhs in
            if lhs.usedPercent == rhs.usedPercent {
                let lhsReset = lhs.resetsAt ?? .distantFuture
                let rhsReset = rhs.resetsAt ?? .distantFuture
                return lhsReset > rhsReset
            }
            return lhs.usedPercent < rhs.usedPercent
        }) else { return nil }
        return UsageWindow(
            id: id,
            title: title,
            usedPercent: strongest.usedPercent,
            resetsAt: strongest.resetsAt)
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

    private static func lastPositiveGrowth(_ values: [Int]) -> Int? {
        guard let previous = values.dropLast().last,
              let latest = values.last
        else { return nil }
        let delta = latest - previous
        return delta > 0 ? delta : nil
    }

    private static func average(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    private static func minutes(from start: Date?, to end: Date?) -> Int {
        guard let start, let end else { return 0 }
        return max(0, Int(end.timeIntervalSince(start) / 60))
    }

    private static func compact(_ value: Int) -> String {
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
        let cumulativeInput: Int
        let cumulativeOutput: Int
        let cumulativeCached: Int
        let cumulativeReasoning: Int
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
    let memory: CodexProjectMemory?
    let today: DailyUsageStats
    let modelMix: [ModelUsageShare]

    func providerSnapshot(
        accountLabel: String,
        now: Date,
        liveSessions: [LiveSession] = [],
        surface: CodexSurfaceSnapshot? = nil) -> ProviderUsageSnapshot
    {
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
            codexMemory: self.memory,
            codexSurface: surface,
            creditBalance: self.creditBalance,
            extraSpend: nil,
            streakDays: 0,
            liveSessions: liveSessions,
            updatedAt: now)
    }
}

private struct CodexSurfaceScanner {
    private let fileManager = FileManager.default

    func scan(
        now: Date,
        localSnapshot: CodexLocalSnapshot?,
        liveSessions: [LiveSession]) -> CodexSurfaceSnapshot
    {
        let home = self.fileManager.homeDirectoryForCurrentUser
        let root = home.appendingPathComponent(".codex")
        let auth = root.appendingPathComponent("auth.json")
        let sessions = root.appendingPathComponent("sessions")
        let stateDB = root.appendingPathComponent("state_5.sqlite")
        let config = root.appendingPathComponent("config.toml")
        let skills = root.appendingPathComponent("skills")
        let plugins = root.appendingPathComponent("plugins")
        let logs = root.appendingPathComponent("logs")

        let hasRoot = self.exists(root)
        let hasAuth = self.exists(auth)
        let rolloutFiles = self.countFiles(in: sessions, pathExtension: "jsonl")
        let stateStats = self.stateStats(from: stateDB)
        let rolloutEventMix = self.rolloutEventMix(from: sessions)
        let automation = self.automationStats(from: stateDB)
        let hasStateDB = self.exists(stateDB)
        let hasConfig = self.exists(config)
        let skillCount = self.countDirectories(in: skills)
        let pluginCount = max(
            self.countDirectories(in: plugins),
            self.countDirectories(in: plugins.appendingPathComponent("cache")))
        let hasLogs = self.exists(logs)
        let projectCount = max(
            stateStats?.projectCount ?? 0,
            localSnapshot?.projectLabel == nil ? 0 : 1)
        let windowsSeen = localSnapshot?.windows.count ?? 0

        let sources: [CodexSurfaceArea] = [
            CodexSurfaceArea(
                key: .root,
                title: "Codex home",
                detail: hasRoot ? "Local Codex directory is readable." : "No local Codex directory found yet.",
                pathHint: self.tildePath(root, home: home),
                status: hasRoot ? .active : .missing,
                depth: .visible,
                count: nil,
                sensitivity: "directory names only"),
            CodexSurfaceArea(
                key: .liveSessions,
                title: "Live sessions",
                detail: liveSessions.isEmpty
                    ? "No rollout touched in the last 10 minutes."
                    : "\(liveSessions.count) rollout\(liveSessions.count == 1 ? "" : "s") active right now.",
                pathHint: self.tildePath(sessions, home: home),
                status: liveSessions.isEmpty ? .available : .active,
                depth: .visible,
                count: liveSessions.count,
                sensitivity: "project labels and mtimes"),
            CodexSurfaceArea(
                key: .quota,
                title: "Quota windows",
                detail: windowsSeen > 0
                    ? "\(windowsSeen) rate-limit window\(windowsSeen == 1 ? "" : "s") decoded from local token counts."
                    : (hasAuth ? "Auth is present; remote quota can still be queried." : "Needs auth or token_count events."),
                pathHint: nil,
                status: windowsSeen > 0 ? .active : (hasAuth ? .available : .missing),
                depth: .visible,
                count: windowsSeen > 0 ? windowsSeen : nil,
                sensitivity: "usage percentages"),
            CodexSurfaceArea(
                key: .sessions,
                title: "Rollout JSONL",
                detail: rolloutFiles > 0
                    ? "\(rolloutFiles) session file\(rolloutFiles == 1 ? "" : "s") available for token/tool timelines."
                    : "No session rollouts found.",
                pathHint: self.tildePath(sessions, home: home),
                status: rolloutFiles > 0 ? .active : .missing,
                depth: .shallow,
                count: rolloutFiles,
                sensitivity: "conversation and tool event metadata"),
            CodexSurfaceArea(
                key: .stateDB,
                title: "State database",
                detail: self.stateDetail(stats: stateStats, hasDB: hasStateDB),
                pathHint: self.tildePath(stateDB, home: home),
                status: self.stateStatus(stats: stateStats, hasDB: hasStateDB),
                depth: .deep,
                count: stateStats?.threadCount,
                sensitivity: "thread titles, cwd, branch, model"),
            CodexSurfaceArea(
                key: .auth,
                title: "Auth token",
                detail: hasAuth
                    ? "Auth file exists; token value is never displayed."
                    : "No auth.json available for remote quota/account probes.",
                pathHint: self.tildePath(auth, home: home),
                status: hasAuth ? .available : .missing,
                depth: .deep,
                count: nil,
                sensitivity: "secret-bearing file, redacted"),
            CodexSurfaceArea(
                key: .config,
                title: "Config",
                detail: hasConfig
                    ? "Codex config is present for sandbox, model, and MCP hints."
                    : "No config.toml found.",
                pathHint: self.tildePath(config, home: home),
                status: hasConfig ? .available : .missing,
                depth: .deep,
                count: nil,
                sensitivity: "settings metadata"),
            CodexSurfaceArea(
                key: .skills,
                title: "Skills",
                detail: skillCount > 0
                    ? "\(skillCount) installed skill director\(skillCount == 1 ? "y" : "ies") detected."
                    : "No Codex skill directory detected.",
                pathHint: self.tildePath(skills, home: home),
                status: skillCount > 0 ? .active : .missing,
                depth: .abyss,
                count: skillCount,
                sensitivity: "skill names only"),
            CodexSurfaceArea(
                key: .plugins,
                title: "Plugins",
                detail: pluginCount > 0
                    ? "\(pluginCount) plugin/cache director\(pluginCount == 1 ? "y" : "ies") detected."
                    : "No plugin cache detected.",
                pathHint: self.tildePath(plugins, home: home),
                status: pluginCount > 0 ? .active : .missing,
                depth: .abyss,
                count: pluginCount,
                sensitivity: "plugin names only"),
            CodexSurfaceArea(
                key: .logs,
                title: "Logs",
                detail: hasLogs
                    ? "Log directory exists for deeper diagnostics."
                    : "No Codex log directory found.",
                pathHint: self.tildePath(logs, home: home),
                status: hasLogs ? .available : .missing,
                depth: .abyss,
                count: nil,
                sensitivity: "diagnostic metadata"),
            CodexSurfaceArea(
                key: .projectMemory,
                title: "Burnrate memory",
                detail: localSnapshot?.memory.map {
                    "\($0.sessionCount) session\($0.sessionCount == 1 ? "" : "s") remembered for this project."
                } ?? "Project memory starts after the first local Codex snapshot.",
                pathHint: "~/Library/Application Support/burnrate/codex-history.json",
                status: localSnapshot?.memory == nil ? .available : .active,
                depth: .abyss,
                count: localSnapshot?.memory?.sessionCount,
                sensitivity: "aggregated session totals"),
        ]

        return CodexSurfaceSnapshot(
            rootPath: self.tildePath(root, home: home),
            capturedAt: now,
            sources: sources,
            iceberg: Self.layers,
            sessionsSeen: rolloutFiles,
            liveSessionsSeen: liveSessions.count,
            projectsSeen: projectCount,
            stateThreadsSeen: stateStats?.threadCount ?? 0,
            rolloutFilesSeen: rolloutFiles,
            totalThreadTokens: stateStats?.totalTokens ?? 0,
            archivedThreadsSeen: stateStats?.archivedThreadCount ?? 0,
            firstThreadAt: stateStats?.firstThreadAt,
            lastThreadAt: stateStats?.lastThreadAt,
            modelFacets: stateStats?.models ?? [],
            reasoningFacets: stateStats?.reasoningEfforts ?? [],
            approvalFacets: stateStats?.approvalModes ?? [],
            sandboxFacets: stateStats?.sandboxPolicies ?? [],
            topProjects: stateStats?.topProjects ?? [],
            recentThreads: stateStats?.recentThreads ?? [],
            activityDays: stateStats?.activityDays ?? [],
            rolloutEventMix: rolloutEventMix,
            automation: automation)
    }

    private static let layers: [CodexSurfaceLayer] = [
        CodexSurfaceLayer(
            depth: .visible,
            title: "Visible",
            detail: "What the notch can safely show at a glance: live project, quota pressure, and session state.",
            sourceKeys: [.root, .liveSessions, .quota]),
        CodexSurfaceLayer(
            depth: .shallow,
            title: "Shallow",
            detail: "Rollout files expose token counts, tools, edits, searches, errors, and compactions.",
            sourceKeys: [.sessions]),
        CodexSurfaceLayer(
            depth: .deep,
            title: "Deep",
            detail: "State DB, auth, and config connect usage to thread identity, account windows, model, branch, sandbox, and MCP context.",
            sourceKeys: [.stateDB, .auth, .config]),
        CodexSurfaceLayer(
            depth: .abyss,
            title: "Abyss",
            detail: "Skills, plugins, logs, and Burnrate's own history let the app infer durable work patterns without reading secrets.",
            sourceKeys: [.skills, .plugins, .logs, .projectMemory]),
    ]

    private func stateStatus(stats: StateStats?, hasDB: Bool) -> CodexSurfaceStatus {
        if let stats, stats.threadCount > 0 { return .active }
        return hasDB ? .warning : .missing
    }

    private func stateDetail(stats: StateStats?, hasDB: Bool) -> String {
        guard hasDB else { return "No state_5.sqlite database found." }
        guard let stats else { return "Database exists, but thread metadata could not be decoded." }
        if stats.threadCount == 0 { return "Database exists, but no threads are recorded yet." }
        let projectText = stats.projectCount == 1 ? "1 project" : "\(stats.projectCount) projects"
        return "\(stats.threadCount) thread\(stats.threadCount == 1 ? "" : "s") across \(projectText)."
    }

    private func stateStats(from db: URL) -> StateStats? {
        guard self.exists(db) else { return nil }
        let query = """
        select
            count(*),
            count(distinct cwd),
            coalesce(sum(tokens_used), 0),
            coalesce(sum(case when archived != 0 then 1 else 0 end), 0),
            coalesce(min(created_at_ms), min(created_at * 1000)),
            coalesce(max(updated_at_ms), max(updated_at * 1000))
        from threads
        """

        guard let fields = self.sqliteRows(db, query: query).first,
              fields.count >= 6
        else { return nil }
        return StateStats(
            threadCount: Int(fields[0]) ?? 0,
            projectCount: Int(fields[1]) ?? 0,
            totalTokens: Int(fields[2]) ?? 0,
            archivedThreadCount: Int(fields[3]) ?? 0,
            firstThreadAt: Self.date(fromMilliseconds: fields[4]),
            lastThreadAt: Self.date(fromMilliseconds: fields[5]),
            models: self.facets(from: db, expression: "coalesce(nullif(model, ''), nullif(model_provider, ''), 'unknown')"),
            reasoningEfforts: self.facets(from: db, expression: "coalesce(nullif(reasoning_effort, ''), 'default')"),
            approvalModes: self.facets(from: db, expression: "coalesce(nullif(approval_mode, ''), 'unknown')"),
            sandboxPolicies: self.facets(
                from: db,
                expression: "coalesce(nullif(sandbox_policy, ''), 'unknown')",
                labelMap: Self.sandboxLabel(from:)),
            topProjects: self.topProjects(from: db),
            recentThreads: self.recentThreads(from: db),
            activityDays: self.activityDays(from: db))
    }

    private func facets(
        from db: URL,
        expression: String,
        limit: Int = 6,
        labelMap: (String) -> String = { $0 }) -> [CodexSurfaceFacet]
    {
        let query = """
        select
            \(expression) as label,
            count(*),
            coalesce(sum(tokens_used), 0),
            coalesce(max(updated_at_ms), max(updated_at * 1000))
        from threads
        group by label
        order by count(*) desc, coalesce(sum(tokens_used), 0) desc
        limit \(limit)
        """

        return self.sqliteRows(db, query: query).compactMap { fields in
            guard fields.count >= 4 else { return nil }
            return CodexSurfaceFacet(
                label: labelMap(Self.nilIfEmpty(fields[0]) ?? "unknown"),
                count: Int(fields[1]) ?? 0,
                tokens: Int(fields[2]) ?? 0,
                lastSeenAt: Self.date(fromMilliseconds: fields[3]))
        }
    }

    private func topProjects(from db: URL, limit: Int = 8) -> [CodexSurfaceProject] {
        let query = """
        select
            t.cwd,
            count(*),
            coalesce(sum(t.tokens_used), 0),
            coalesce(max(t.updated_at_ms), max(t.updated_at * 1000)),
            count(distinct t.git_branch),
            (
                select title from threads recent
                where recent.cwd = t.cwd
                order by coalesce(recent.updated_at_ms, recent.updated_at * 1000) desc
                limit 1
            )
        from threads t
        group by t.cwd
        order by coalesce(sum(t.tokens_used), 0) desc, count(*) desc
        limit \(limit)
        """

        return self.sqliteRows(db, query: query).compactMap { fields in
            guard fields.count >= 6 else { return nil }
            let path = fields[0]
            return CodexSurfaceProject(
                name: Self.projectName(from: path),
                path: path,
                threadCount: Int(fields[1]) ?? 0,
                tokens: Int(fields[2]) ?? 0,
                branchCount: Int(fields[4]) ?? 0,
                latestTitle: Self.nilIfEmpty(fields[5]),
                lastActivityAt: Self.date(fromMilliseconds: fields[3]))
        }
    }

    private func recentThreads(from db: URL, limit: Int = 8) -> [CodexSurfaceThread] {
        let query = """
        select
            coalesce(nullif(title, ''), nullif(first_user_message, ''), 'Untitled thread'),
            cwd,
            coalesce(nullif(model, ''), nullif(model_provider, '')),
            coalesce(nullif(reasoning_effort, ''), ''),
            tokens_used,
            coalesce(updated_at_ms, updated_at * 1000),
            coalesce(nullif(git_branch, ''), '')
        from threads
        order by coalesce(updated_at_ms, updated_at * 1000) desc
        limit \(limit)
        """

        return self.sqliteRows(db, query: query).compactMap { fields in
            guard fields.count >= 7 else { return nil }
            return CodexSurfaceThread(
                title: Self.condensed(fields[0], maxLength: 72),
                projectName: Self.projectName(from: fields[1]),
                modelName: Self.nilIfEmpty(fields[2]),
                reasoningEffort: Self.nilIfEmpty(fields[3]),
                tokens: Int(fields[4]) ?? 0,
                lastActivityAt: Self.date(fromMilliseconds: fields[5]),
                gitBranch: Self.nilIfEmpty(fields[6]))
        }
    }

    private func activityDays(from db: URL, limit: Int = 14) -> [CodexSurfaceActivityDay] {
        let query = """
        select
            strftime('%m/%d', coalesce(updated_at_ms, updated_at * 1000) / 1000, 'unixepoch'),
            count(*),
            coalesce(sum(tokens_used), 0),
            coalesce(max(updated_at_ms), max(updated_at * 1000))
        from threads
        where coalesce(updated_at_ms, updated_at * 1000) > 0
        group by strftime('%Y-%m-%d', coalesce(updated_at_ms, updated_at * 1000) / 1000, 'unixepoch')
        order by coalesce(max(updated_at_ms), max(updated_at * 1000)) desc
        limit \(limit)
        """

        return self.sqliteRows(db, query: query).compactMap { fields in
            guard fields.count >= 4 else { return nil }
            return CodexSurfaceActivityDay(
                label: Self.nilIfEmpty(fields[0]) ?? "day",
                threadCount: Int(fields[1]) ?? 0,
                tokens: Int(fields[2]) ?? 0,
                date: Self.date(fromMilliseconds: fields[3]))
        }
        .reversed()
    }

    private func automationStats(from db: URL) -> CodexAutomationSnapshot {
        guard self.exists(db) else { return .empty }
        let query = """
        select
            (select count(*) from agent_jobs),
            (select count(*) from thread_goals),
            (select count(*) from thread_dynamic_tools),
            (select count(*) from thread_spawn_edges)
        """
        guard let fields = self.sqliteRows(db, query: query).first,
              fields.count >= 4
        else { return .empty }
        return CodexAutomationSnapshot(
            agentJobs: Int(fields[0]) ?? 0,
            activeGoals: Int(fields[1]) ?? 0,
            dynamicTools: Int(fields[2]) ?? 0,
            spawnEdges: Int(fields[3]) ?? 0)
    }

    private func rolloutEventMix(from root: URL, limit: Int = 24) -> CodexRolloutEventMix {
        let files = self.recentRolloutFiles(in: root, limit: limit)
        var tokenEvents = 0
        var toolCalls = 0
        var shellCommands = 0
        var patchEvents = 0
        var webSearches = 0
        var errors = 0
        var compactions = 0

        for file in files {
            guard let content = Self.boundedText(from: file, maxBytes: 512 * 1024) else { continue }
            for line in content.split(separator: "\n") {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }

                let topType = object["type"] as? String
                let payload = object["payload"] as? [String: Any]
                let payloadType = payload?["type"] as? String

                if payloadType == "token_count" { tokenEvents += 1 }
                if topType == "response_item", payloadType == "function_call" { toolCalls += 1 }
                if payloadType == "exec_command_end" { shellCommands += 1 }
                if payloadType?.contains("patch") == true { patchEvents += 1 }
                if payloadType?.contains("web_search") == true { webSearches += 1 }
                if topType == "error" || payloadType?.contains("error") == true { errors += 1 }
                if payloadType?.contains("compact") == true { compactions += 1 }
            }
        }

        return CodexRolloutEventMix(
            tokenEvents: tokenEvents,
            toolCalls: toolCalls,
            shellCommands: shellCommands,
            patchEvents: patchEvents,
            webSearches: webSearches,
            errors: errors,
            compactions: compactions)
    }

    private func recentRolloutFiles(in root: URL, limit: Int) -> [URL] {
        guard let enumerator = self.fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])
        else { return [] }

        var files: [(url: URL, modified: Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            files.append((url, modified))
        }
        return files
            .sorted { $0.modified > $1.modified }
            .prefix(limit)
            .map(\.url)
    }

    private static func boundedText(from url: URL, maxBytes: Int) -> String? {
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard fileSize > maxBytes else {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(max(0, fileSize - maxBytes)))
        } catch {
            return nil
        }
        let data = (try? handle.readToEnd()) ?? Data()
        return String(data: data, encoding: .utf8)
    }

    private func sqliteRows(_ db: URL, query: String) -> [[String]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-tabs", db.path, query]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            guard let string = String(data: data, encoding: .utf8) else { return [] }
            return string
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { String($0).components(separatedBy: "\t") }
        } catch {
            return []
        }
    }

    private func countFiles(in root: URL, pathExtension: String) -> Int {
        guard let enumerator = self.fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])
        else { return 0 }

        var count = 0
        for case let url as URL in enumerator where url.pathExtension == pathExtension {
            count += 1
        }
        return count
    }

    private func countDirectories(in root: URL) -> Int {
        guard let urls = try? self.fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        else { return 0 }

        return urls.reduce(0) { partial, url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return partial + (isDirectory ? 1 : 0)
        }
    }

    private func exists(_ url: URL) -> Bool {
        self.fileManager.fileExists(atPath: url.path)
    }

    private func tildePath(_ url: URL, home: URL) -> String {
        let path = url.path
        let homePath = home.path
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") {
            return "~" + String(path.dropFirst(homePath.count))
        }
        return path
    }

    private static func date(fromMilliseconds value: String) -> Date? {
        guard let milliseconds = Double(value), milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }

    private static func nilIfEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func projectName(from path: String) -> String {
        guard !path.isEmpty else { return "Codex" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private static func sandboxLabel(from raw: String) -> String {
        if raw.contains("danger-full-access") { return "full access" }
        if raw.contains("workspace-write") { return "workspace write" }
        if raw.contains("read-only") { return "read only" }
        return raw.isEmpty ? "unknown" : raw
    }

    private static func condensed(_ value: String, maxLength: Int) -> String {
        let singleLine = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard singleLine.count > maxLength else { return singleLine }
        return String(singleLine.prefix(maxLength - 1)) + "..."
    }

    private struct StateStats {
        let threadCount: Int
        let projectCount: Int
        let totalTokens: Int
        let archivedThreadCount: Int
        let firstThreadAt: Date?
        let lastThreadAt: Date?
        let models: [CodexSurfaceFacet]
        let reasoningEfforts: [CodexSurfaceFacet]
        let approvalModes: [CodexSurfaceFacet]
        let sandboxPolicies: [CodexSurfaceFacet]
        let topProjects: [CodexSurfaceProject]
        let recentThreads: [CodexSurfaceThread]
        let activityDays: [CodexSurfaceActivityDay]
    }
}

private struct CodexHistoryStore {
    func record(
        sessionId: String,
        projectName: String,
        threadTitle: String?,
        totalTokens: Int,
        turnCount: Int,
        updatedAt: Date) -> CodexProjectMemory?
    {
        var history = self.load()
        history.sessions.removeAll { $0.sessionId == sessionId }
        history.sessions.append(
            SessionSummary(
                sessionId: sessionId,
                projectName: projectName,
                threadTitle: threadTitle,
                totalTokens: totalTokens,
                turnCount: max(1, turnCount),
                updatedAt: updatedAt))
        history.sessions = Array(history.sessions.sorted { $0.updatedAt > $1.updatedAt }.prefix(240))
        self.save(history)
        return self.memory(projectName: projectName, history: history)
    }

    private func memory(projectName: String, history: HistoryFile) -> CodexProjectMemory? {
        let all = history.sessions
        let projectSessions = all.filter { $0.projectName == projectName }
        guard !projectSessions.isEmpty else { return nil }

        let averageSession = Self.average(projectSessions.map(\.totalTokens))
        let averageTurn = Self.average(projectSessions.map { $0.totalTokens / max(1, $0.turnCount) })
        let globalAverage = max(1, Self.average(all.map(\.totalTokens)))
        let heaviest = projectSessions.max { $0.totalTokens < $1.totalTokens }

        return CodexProjectMemory(
            projectName: projectName,
            sessionCount: projectSessions.count,
            averageSessionTokens: averageSession,
            averageTurnTokens: averageTurn,
            heaviestSessionTokens: heaviest?.totalTokens ?? 0,
            heaviestSessionTitle: heaviest?.threadTitle,
            relativeBurnMultiple: Double(averageSession) / Double(globalAverage),
            lastUpdatedAt: projectSessions.map(\.updatedAt).max())
    }

    private func load() -> HistoryFile {
        guard let data = try? Data(contentsOf: self.url),
              let decoded = try? JSONDecoder().decode(HistoryFile.self, from: data)
        else { return HistoryFile(sessions: []) }
        return decoded
    }

    private func save(_ history: HistoryFile) {
        do {
            try FileManager.default.createDirectory(
                at: self.url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(history)
            try data.write(to: self.url, options: [.atomic])
        } catch {
            // History is an enhancement; failures should not block telemetry.
        }
    }

    private var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("burnrate/codex-history.json")
    }

    private static func average(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / values.count
    }

    private struct HistoryFile: Codable {
        var sessions: [SessionSummary]
    }

    private struct SessionSummary: Codable {
        let sessionId: String
        let projectName: String
        let threadTitle: String?
        let totalTokens: Int
        let turnCount: Int
        let updatedAt: Date
    }
}

private struct LocalRateLimit {
    let limitID: String
    let limitName: String?
    let windows: [UsageWindow]
    let planName: String?
    let creditBalance: Double?
}

private struct CodexThreadStore {
    func thread(for rolloutPath: String) -> ThreadMetadata? {
        let db = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/state_5.sqlite")
        guard FileManager.default.fileExists(atPath: db.path) else { return nil }

        let query = """
        select
          id,
          title,
          cwd,
          coalesce(model,'') as model,
          coalesce(reasoning_effort,'') as reasoning_effort,
          coalesce(git_branch,'') as git_branch,
          source,
          tokens_used,
          coalesce(updated_at_ms,updated_at * 1000) as updated_at_ms,
          coalesce(cli_version,'') as cli_version,
          approval_mode,
          sandbox_policy
        from threads
        where rollout_path=\(Self.sqlQuote(rolloutPath))
        order by updated_at_ms desc
        limit 1
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-json", db.path, query]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let row = rows.first
            else { return nil }

            return ThreadMetadata(
                sessionId: Self.string(row["id"]),
                title: Self.string(row["title"]),
                cwd: Self.string(row["cwd"]),
                model: Self.string(row["model"]),
                reasoningEffort: Self.string(row["reasoning_effort"]),
                gitBranch: Self.string(row["git_branch"]),
                source: Self.string(row["source"]),
                tokensUsed: Self.int(row["tokens_used"]),
                updatedAt: Self.date(fromMilliseconds: row["updated_at_ms"]),
                cliVersion: Self.string(row["cli_version"]),
                approvalMode: Self.string(row["approval_mode"]),
                sandboxLabel: Self.sandboxLabel(from: Self.string(row["sandbox_policy"])))
        } catch {
            return nil
        }
    }

    private static func sqlQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String:
            return text.isEmpty ? nil : text
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func int(_ value: Any?) -> Int {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let text as String:
            return Int(text) ?? 0
        default:
            return 0
        }
    }

    private static func date(fromMilliseconds value: Any?) -> Date? {
        let milliseconds: Double
        switch value {
        case let double as Double:
            milliseconds = double
        case let int as Int:
            milliseconds = Double(int)
        case let number as NSNumber:
            milliseconds = number.doubleValue
        case let text as String:
            milliseconds = Double(text) ?? 0
        default:
            milliseconds = 0
        }
        guard milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }

    private static func sandboxLabel(from raw: String?) -> String? {
        guard let raw else { return nil }
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
