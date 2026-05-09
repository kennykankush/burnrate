import Foundation
import os.log

private let log = Logger(subsystem: "fyi.burnrate.app", category: "claudeWatcher")

public actor ClaudeUsageWatcher {
    private var slashCommandCountsCache: (signature: FileSignature, counts: [String: Int])?

    public init() {}

    public func loadSnapshot(
        now: Date,
        recentDailySpend: Double? = nil,
        pinnedSessionId: String? = nil) async -> ProviderUsageSnapshot?
    {
        let root = Self.claudeRoot()
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }

        let oauthTask = Task.detached(priority: .utility) {
            await Self.readOAuthUsage(root: root)
        }
        let baseAggregate = self.readAggregate(root: root)
        let sessionMetas = self.readSessionMetas(root: root)
        let facets = self.readLatestFacets(root: root, metas: sessionMetas)
        let liveSession = self.readLiveSession(
            root: root,
            facets: facets,
            now: now,
            pinnedSessionId: pinnedSessionId)
        let leaderboard = self.scanRecentJsonlsForTools(root: root, limit: 20)
        let betaGates = self.readBetaGates(root: root)
        let oauth = await oauthTask.value
        let todayBreakdown = self.buildTodayBreakdown(
            sessionMetas: sessionMetas,
            liveSession: liveSession,
            now: now)
        let healthIndicators = self.buildHealth(
            root: root,
            liveSession: liveSession,
            oauth: oauth,
            now: now)
        let today = self.buildToday(
            sessionMetas: sessionMetas,
            liveSession: liveSession,
            now: now)
        let aggregate = self.aggregateIncludingToday(
            baseAggregate, today: today, now: now,
            toolLeaderboard: leaderboard, betaGates: betaGates)
        var patternCards = self.buildPatternCards(
            aggregate: aggregate,
            sessionMetas: sessionMetas,
            facets: facets,
            liveSession: liveSession,
            oauth: oauth,
            recentDailySpend: recentDailySpend,
            now: now)
        patternCards = Self.rankCards(patternCards)
        let modelMix = aggregate?.modelMix ?? self.modelMixFromLive(liveSession)
        let workContext = liveSession.flatMap { Self.workContext(from: $0, now: now) }
        let windows = self.buildWindows(
            oauth: oauth,
            aggregate: aggregate,
            today: today,
            workContext: workContext,
            now: now)
        let projectLabel = liveSession?.projectName
            ?? sessionMetas.first?.projectName
            ?? "Claude Code"

        let claudeMemory = self.computeClaudeProjectMemory(
            sessionMetas: sessionMetas,
            liveSession: liveSession,
            currentProject: projectLabel)

        let liveSessions = self.readLiveSessions(root: root, now: now)

        return ProviderUsageSnapshot(
            kind: .claude,
            planName: self.planName(from: oauth, aggregate: aggregate, liveSession: liveSession),
            accountLabel: self.accountLabel(root: root, oauth: oauth),
            projectLabel: projectLabel,
            windows: windows,
            today: today,
            modelMix: modelMix,
            workContext: workContext,
            codexSession: nil,
            codexMemory: nil,
            claudeSession: liveSession,
            claudeAggregate: aggregate,
            claudeFacets: facets,
            claudeTodayBreakdown: todayBreakdown,
            claudeMemory: claudeMemory,
            patternCards: patternCards,
            healthIndicators: healthIndicators,
            creditBalance: oauth?.extraUsage.map { $0.monthlyLimit - $0.usedCredits },
            extraSpend: oauth?.extraUsage.map {
                ProviderSpend(used: $0.usedCredits, limit: $0.monthlyLimit, currencyCode: $0.currency)
            },
            streakDays: aggregate?.streakDays ?? 0,
            liveSessions: liveSessions,
            updatedAt: now)
    }

    public func loadPreviewSnapshot(
        now: Date,
        pinnedSessionId: String?,
        preserving base: ProviderUsageSnapshot?) async -> ProviderUsageSnapshot?
    {
        let root = Self.claudeRoot()
        guard FileManager.default.fileExists(atPath: root.path) else { return base }

        let liveSession = self.readLiveSession(
            root: root,
            facets: base?.claudeFacets,
            now: now,
            pinnedSessionId: pinnedSessionId)
        guard let liveSession else { return base }

        let liveSessions = self.readLiveSessions(root: root, now: now)
        let workContext = Self.workContext(from: liveSession, now: now)
        let modelMix = (base?.modelMix.isEmpty == false)
            ? (base?.modelMix ?? [])
            : self.modelMixFromLive(liveSession)

        return ProviderUsageSnapshot(
            kind: .claude,
            planName: base?.planName,
            accountLabel: base?.accountLabel,
            projectLabel: liveSession.projectName ?? base?.projectLabel ?? "Claude Code",
            windows: base?.windows ?? [],
            today: base?.today ?? .empty,
            modelMix: modelMix,
            workContext: workContext,
            codexSession: nil,
            codexMemory: nil,
            codexSurface: nil,
            claudeSession: liveSession,
            claudeAggregate: base?.claudeAggregate,
            claudeFacets: base?.claudeFacets,
            claudeTodayBreakdown: base?.claudeTodayBreakdown,
            claudeMemory: base?.claudeMemory,
            patternCards: base?.patternCards ?? [],
            healthIndicators: base?.healthIndicators ?? [],
            creditBalance: base?.creditBalance,
            extraSpend: base?.extraSpend,
            streakDays: base?.streakDays ?? 0,
            liveSessions: liveSessions.isEmpty ? (base?.liveSessions ?? []) : liveSessions,
            updatedAt: now)
    }

    private func computeClaudeProjectMemory(
        sessionMetas: [ParsedSessionMeta],
        liveSession: ClaudeSessionStats?,
        currentProject: String) -> CodexProjectMemory?
    {
        guard !sessionMetas.isEmpty else { return nil }

        let projectMetas = sessionMetas.filter { $0.projectName == currentProject }
        guard !projectMetas.isEmpty else { return nil }

        func sessionTokens(_ m: ParsedSessionMeta) -> Int { m.inputTokens + m.outputTokens }
        func turnTokens(_ m: ParsedSessionMeta) -> Int {
            sessionTokens(m) / max(1, m.assistantMessageCount)
        }

        let totalSessionTokens = projectMetas.map(sessionTokens).reduce(0, +)
        let avgSessionTokens = totalSessionTokens / max(1, projectMetas.count)
        let avgTurnTokens = projectMetas.map(turnTokens).reduce(0, +) / max(1, projectMetas.count)

        let globalTotal = sessionMetas.map(sessionTokens).reduce(0, +)
        let globalAvg = max(1, globalTotal / max(1, sessionMetas.count))
        let burnMultiple = Double(avgSessionTokens) / Double(globalAvg)

        let heaviest = projectMetas.max { sessionTokens($0) < sessionTokens($1) }
        let lastUpdatedAt = projectMetas.compactMap(\.startTime).max()

        return CodexProjectMemory(
            projectName: currentProject,
            sessionCount: projectMetas.count,
            averageSessionTokens: avgSessionTokens,
            averageTurnTokens: avgTurnTokens,
            heaviestSessionTokens: heaviest.map(sessionTokens) ?? 0,
            heaviestSessionTitle: nil,
            relativeBurnMultiple: burnMultiple,
            lastUpdatedAt: lastUpdatedAt)
    }

    private static func readOAuthUsage(root: URL) async -> ClaudeOAuthUsage? {
        guard let creds = ClaudeOAuthCredentialReader.read(claudeRoot: root) else { return nil }
        if let usage = await ClaudeOAuthUsageFetcher().fetch(credentials: creds) {
            return usage
        }
        // API fetch failed (network, timeout, expired token, beta
        // header drift). Still surface a minimal record so the
        // keychain's `subscriptionType` survives — without this,
        // a flaky API would erase every plan-name signal we have
        // and the badge would tumble all the way down to "Pro/Max".
        return ClaudeOAuthUsage(
            fiveHour: nil,
            sevenDay: nil,
            sevenDayOpus: nil,
            sevenDaySonnet: nil,
            sevenDayOAuthApps: nil,
            extraUsage: nil,
            rateLimitTier: nil,
            subscriptionType: creds.subscriptionType)
    }

    private static func claudeRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }

    // MARK: - stats-cache.json

    private func readAggregate(root: URL) -> ClaudeAggregateStats? {
        let path = root.appendingPathComponent("stats-cache.json")
        guard let data = try? Data(contentsOf: path),
              let raw = try? JSONDecoder().decode(StatsCacheRaw.self, from: data)
        else { return nil }

        let firstSession = ClaudeDate.parse(raw.firstSessionDate)
        let longestDate = ClaudeDate.parse(raw.longestSession?.timestamp)
        let longestMinutes = max(0, Int((raw.longestSession?.duration ?? 0) / 60_000))

        let dailyCounts = (raw.dailyActivity ?? []).compactMap { entry -> ClaudeDailyCount? in
            guard let date = ClaudeDate.parseDay(entry.date) else { return nil }
            return ClaudeDailyCount(
                date: date,
                messageCount: entry.messageCount ?? 0,
                sessionCount: entry.sessionCount ?? 0,
                toolCallCount: entry.toolCallCount ?? 0)
        }.sorted { $0.date < $1.date }

        var hourArray = Array(repeating: 0, count: 24)
        for (key, value) in raw.hourCounts ?? [:] {
            if let hour = Int(key), (0..<24).contains(hour) {
                hourArray[hour] = value
            }
        }

        var lifetimeInput = 0
        var lifetimeOutput = 0
        var lifetimeCacheRead = 0
        var lifetimeCacheCreate = 0
        var lifetimeWebSearches = 0
        var lifetimeCostUSD: Double = 0
        var modelTotals: [(String, Int)] = []
        var modelTokens: [ClaudeModelTokens] = []
        for (model, usage) in raw.modelUsage ?? [:] {
            let i = usage.inputTokens ?? 0
            let o = usage.outputTokens ?? 0
            let cr = usage.cacheReadInputTokens ?? 0
            let cc = usage.cacheCreationInputTokens ?? 0
            lifetimeInput += i
            lifetimeOutput += o
            lifetimeCacheRead += cr
            lifetimeCacheCreate += cc
            lifetimeWebSearches += usage.webSearchRequests ?? 0
            let cost = ClaudePricing.synthesizeUSD(model: model, input: i, output: o, cacheRead: cr, cacheCreate: cc)
            lifetimeCostUSD += cost
            let total = i + o + cr + cc
            modelTotals.append((model, total))
            modelTokens.append(
                ClaudeModelTokens(
                    modelName: model,
                    inputTokens: i,
                    outputTokens: o,
                    cacheReadTokens: cr,
                    cacheCreationTokens: cc,
                    syntheticCostUSD: cost))
        }
        let modelTotalSum = max(1, modelTotals.reduce(0) { $0 + $1.1 })
        let modelMix = modelTotals
            .sorted { $0.1 > $1.1 }
            .prefix(4)
            .map { ModelUsageShare(modelName: Self.shortModelName($0.0), percent: Double($0.1) / Double(modelTotalSum) * 100) }

        let recentTokens = (raw.dailyModelTokens ?? []).compactMap { entry -> ClaudeDailyTokenCount? in
            guard let date = ClaudeDate.parseDay(entry.date) else { return nil }
            let total = (entry.tokensByModel ?? [:]).values.reduce(0, +)
            return ClaudeDailyTokenCount(date: date, totalTokens: total)
        }.sorted { $0.date < $1.date }.suffix(30)

        // Per-model lifetime cost-per-token (embeds the actual input/output/cache
        // distribution observed for that specific model). This avoids the
        // global-blended rate over-estimating recent activity when lifetime mix
        // skews toward expensive models.
        var perModelRate: [String: Double] = [:]
        for entry in modelTokens {
            let total = entry.inputTokens + entry.outputTokens + entry.cacheReadTokens + entry.cacheCreationTokens
            guard total > 0 else { continue }
            perModelRate[entry.modelName] = entry.syntheticCostUSD / Double(total)
        }

        // Walk last-30-days per-model token data with each model's actual rate.
        let last30Entries = (raw.dailyModelTokens ?? [])
            .compactMap { entry -> (Date, [String: Int])? in
                guard let date = ClaudeDate.parseDay(entry.date),
                      let by = entry.tokensByModel
                else { return nil }
                return (date, by)
            }
            .sorted { $0.0 < $1.0 }
            .suffix(30)

        var thirtyDayCost = 0.0
        var thirtyDayTokens = 0
        for (_, by) in last30Entries {
            for (model, tokens) in by {
                thirtyDayTokens += tokens
                if let rate = perModelRate[model] {
                    thirtyDayCost += Double(tokens) * rate
                } else {
                    // Fallback: compute synthesized rate fresh for an unseen model.
                    // Assume 70% input / 25% output / 5% cache split as a heuristic.
                    let r = ClaudePricing.rates(for: model)
                    let blended = (r.input * 0.70 + r.output * 0.25 + r.cacheRead * 0.05) / 1_000_000.0
                    thirtyDayCost += Double(tokens) * blended
                }
            }
        }

        return ClaudeAggregateStats(
            firstSessionDate: firstSession,
            totalSessions: raw.totalSessions ?? 0,
            totalMessages: raw.totalMessages ?? 0,
            longestSessionMinutes: longestMinutes,
            longestSessionMessageCount: raw.longestSession?.messageCount ?? 0,
            longestSessionDate: longestDate,
            dailyMessageCounts: Array(dailyCounts.suffix(60)),
            hourCounts: hourArray,
            lifetimeInputTokens: lifetimeInput,
            lifetimeOutputTokens: lifetimeOutput,
            lifetimeCacheReadTokens: lifetimeCacheRead,
            lifetimeCacheCreationTokens: lifetimeCacheCreate,
            lifetimeWebSearchRequests: lifetimeWebSearches,
            lifetimeModelTokens: modelTokens.sorted { $0.syntheticCostUSD > $1.syntheticCostUSD },
            lifetimeSyntheticCostUSD: lifetimeCostUSD,
            lastThirtyDayCostUSD: thirtyDayCost,
            lastThirtyDayTokens: thirtyDayTokens,
            modelMix: Array(modelMix),
            recentDayTokens: Array(recentTokens),
            speculationTimeSavedMs: raw.totalSpeculationTimeSavedMs ?? 0,
            lastComputedDate: raw.lastComputedDate)
    }

    private func aggregateIncludingToday(
        _ base: ClaudeAggregateStats?,
        today: DailyUsageStats,
        now: Date,
        toolLeaderboard: ClaudeToolLeaderboard,
        betaGates: [ClaudeBetaGate]) -> ClaudeAggregateStats?
    {
        guard let base else { return nil }
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        var counts = base.dailyMessageCounts.filter { !calendar.isDate($0.date, inSameDayAs: now) }
        if today.requests > 0 {
            counts.append(
                ClaudeDailyCount(
                    date: todayStart,
                    messageCount: today.requests,
                    sessionCount: 1,
                    toolCallCount: 0))
        }
        return ClaudeAggregateStats(
            firstSessionDate: base.firstSessionDate,
            totalSessions: base.totalSessions,
            totalMessages: base.totalMessages,
            longestSessionMinutes: base.longestSessionMinutes,
            longestSessionMessageCount: base.longestSessionMessageCount,
            longestSessionDate: base.longestSessionDate,
            dailyMessageCounts: counts.sorted { $0.date < $1.date },
            hourCounts: base.hourCounts,
            lifetimeInputTokens: base.lifetimeInputTokens,
            lifetimeOutputTokens: base.lifetimeOutputTokens,
            lifetimeCacheReadTokens: base.lifetimeCacheReadTokens,
            lifetimeCacheCreationTokens: base.lifetimeCacheCreationTokens,
            lifetimeWebSearchRequests: base.lifetimeWebSearchRequests,
            lifetimeModelTokens: base.lifetimeModelTokens,
            lifetimeSyntheticCostUSD: base.lifetimeSyntheticCostUSD,
            lastThirtyDayCostUSD: base.lastThirtyDayCostUSD,
            lastThirtyDayTokens: base.lastThirtyDayTokens,
            modelMix: base.modelMix,
            recentDayTokens: base.recentDayTokens,
            speculationTimeSavedMs: base.speculationTimeSavedMs,
            lastComputedDate: base.lastComputedDate,
            toolLeaderboard: toolLeaderboard,
            betaGates: betaGates)
    }

    // MARK: - session-meta files

    private func readSessionMetas(root: URL) -> [ParsedSessionMeta] {
        let dir = root.appendingPathComponent("usage-data/session-meta")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }

        let metas: [ParsedSessionMeta] = files.compactMap { url in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let raw = try? JSONDecoder().decode(SessionMetaRaw.self, from: data)
            else { return nil }
            return ParsedSessionMeta(raw: raw)
        }
        return metas.sorted { ($0.startTime ?? .distantPast) > ($1.startTime ?? .distantPast) }
    }

    /// Builds the concurrent-session list from the live transcript
    /// files in `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl` —
    /// these get appended to in real time during a Claude Code session,
    /// so file mtime is a faithful "last activity" signal. (The
    /// session-meta JSONs in `usage-data/session-meta/` are written at
    /// session end / rollup time and don't reflect in-flight activity.)
    private func readLiveSessions(root: URL, now: Date, thresholdSeconds: TimeInterval = 600) -> [LiveSession] {
        let projectsDir = root.appendingPathComponent("projects")
        guard FileManager.default.fileExists(atPath: projectsDir.path) else { return [] }
        guard let enumerator = FileManager.default.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])
        else { return [] }

        let cutoff = now.addingTimeInterval(-thresholdSeconds)
        // Single pass over `~/.claude/sessions/` — returns renamed
        // titles + the set of sessionIds whose process is actually
        // running. Lets us skip the jsonl mtime trap (which lingers
        // for the full threshold after Claude Code exits).
        let metadata = Self.sessionMetadata(root: root)
        var live: [LiveSession] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate),
                  mtime >= cutoff || metadata.liveSessionIds.contains(url.deletingPathExtension().lastPathComponent)
            else { continue }
            let sessionId = url.deletingPathExtension().lastPathComponent
            // If we have a session file for this id, trust it: only
            // include the session when its pid is alive. If we have
            // NO session file at all, fall back to the mtime
            // threshold (covers edge cases like Claude Code being
            // killed without writing a clean teardown).
            let hasSessionFile = metadata.names[sessionId] != nil
                || metadata.liveSessionIds.contains(sessionId)
            if hasSessionFile,
               !metadata.liveSessionIds.contains(sessionId)
            {
                continue
            }
            let projectName = ParsedSessionMeta.projectName(
                fromEncodedFolder: url.deletingLastPathComponent().lastPathComponent)
            // Resolution order for the pill name:
            //   1. User-renamed title from `~/.claude/sessions/*.json`
            //      — short, intentional, and matches what the user
            //      sees in Claude Code's session list.
            //   2. First user message from the jsonl — the
            //      conversation's de facto topic when no rename.
            //   3. Project folder name (handled at the view layer).
            let displayName = metadata.names[sessionId]
                ?? Self.firstUserMessage(from: url)
            live.append(LiveSession(
                sessionId: sessionId,
                projectName: projectName,
                lastActivityAt: mtime,
                displayName: displayName))
        }
        return live.sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    /// Combined scan of `~/.claude/sessions/*.json` — returns both
    /// the user's renamed titles and a "this session's process is
    /// actually alive" check, so callers can do one directory pass
    /// instead of two.
    ///
    /// `liveSessionIds` only includes sessions whose pid passes
    /// `kill(pid, 0)`. mtime alone is unreliable because the jsonl
    /// keeps showing recent timestamps for the full 10-minute
    /// threshold after Claude Code exits — checking the pid catches
    /// closed windows immediately.
    private static func sessionMetadata(root: URL) -> (
        names: [String: String],
        liveSessionIds: Set<String>)
    {
        let sessionsDir = root.appendingPathComponent("sessions")
        guard FileManager.default.fileExists(atPath: sessionsDir.path) else {
            return (names: [:], liveSessionIds: [])
        }
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
        else {
            return (names: [:], liveSessionIds: [])
        }
        var names: [String: String] = [:]
        var live: Set<String> = []
        for case let url as URL in enumerator where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessionId = json["sessionId"] as? String
            else { continue }
            if let name = json["name"] as? String, !name.isEmpty {
                names[sessionId] = name
            }
            if let pid = json["pid"] as? Int, Self.isProcessAlive(pid: pid) {
                live.insert(sessionId)
            }
        }
        return (names: names, liveSessionIds: live)
    }

    /// `kill(pid, 0)` sends signal 0 — a no-op that returns 0 if the
    /// process exists and -1/ESRCH if it doesn't. Same-user processes
    /// won't EPERM, so the simple check is enough here.
    private static func isProcessAlive(pid: Int) -> Bool {
        kill(Int32(pid), 0) == 0
    }

    private static func fileSignature(for url: URL) -> FileSignature? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return nil
        }
        return FileSignature(
            fileSize: values.fileSize ?? 0,
            modifiedAt: values.contentModificationDate)
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

    /// Reads a session jsonl and returns the first meaningful user
    /// message, formatted as a short conversation name. Mirrors
    /// Claude Code's own `/resume` heuristic — first non-caveat,
    /// non-slash-command, non-attachment user text. Truncated to ~40
    /// chars so it fits a pill. Returns nil when no qualifying
    /// message has landed yet (cold-start sessions).
    ///
    /// We stream-parse the file line-by-line and bail after finding
    /// the first match (or after 200 lines as a safety bound) so
    /// large transcripts don't cost much on every poll.
    private static func firstUserMessage(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        // Read up to ~256KB which comfortably covers the opening
        // turns of any session — the first user message is almost
        // always within the first few hundred lines.
        guard let data = try? handle.read(upToCount: 256 * 1024) else { return nil }
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        var inspected = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            inspected += 1
            if inspected > 200 { break }

            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            guard json["type"] as? String == "user" else { continue }

            // The message text can be either a plain string or an
            // array of content blocks. Walk both shapes.
            let raw = Self.extractUserText(from: json)
            guard let trimmed = Self.cleanFirstMessage(raw) else { continue }
            return trimmed
        }
        return nil
    }

    /// Walks both possible shapes for `message.content` (string or
    /// array of content blocks) and pulls out the first text we can
    /// find. Skips tool-use blocks, attachments, and other non-text
    /// content types.
    private static func extractUserText(from json: [String: Any]) -> String? {
        guard let message = json["message"] as? [String: Any] else { return nil }
        if let content = message["content"] as? String { return content }
        if let blocks = message["content"] as? [[String: Any]] {
            for block in blocks {
                if block["type"] as? String == "text",
                   let text = block["text"] as? String, !text.isEmpty
                {
                    return text
                }
            }
        }
        return nil
    }

    /// Filters out caveats and slash commands, trims whitespace,
    /// strips newlines, and truncates to a pill-friendly length.
    /// Returns nil for messages that don't qualify as a name —
    /// callers should keep walking the file in that case.
    private static func cleanFirstMessage(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // <local-command-caveat> blocks are wrapper text injected by
        // CLI commands like /clear or /compact — never user intent.
        if trimmed.hasPrefix("<local-command-caveat>") { return nil }
        // Slash commands (`/usage`, `/clear`, etc.) describe an
        // action, not a topic. Skip so we land on the first
        // substantive message.
        if trimmed.hasPrefix("/") { return nil }
        // Collapse internal newlines into spaces so the pill stays
        // a single line.
        let oneLine = trimmed
            .components(separatedBy: .newlines)
            .joined(separator: " ")
        // Truncate aggressively — pills are narrow and renamed
        // session titles are typically short ("NOTCH", "fix bugs").
        // 32 chars matches that scale; the pill view also middle-
        // truncates, so this is a memory bound, not a layout one.
        let maxLength = 32
        if oneLine.count <= maxLength { return oneLine }
        let endIndex = oneLine.index(oneLine.startIndex, offsetBy: maxLength)
        return oneLine[..<endIndex].trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - facets

    private func readLatestFacets(root: URL, metas: [ParsedSessionMeta]) -> ClaudeFacets? {
        let dir = root.appendingPathComponent("usage-data/facets")
        if let target = metas.first?.sessionId {
            let candidate = dir.appendingPathComponent("\(target).json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return Self.decodeFacets(at: candidate)
            }
        }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])
        else { return nil }

        let mostRecent = files
            .filter { $0.pathExtension == "json" }
            .map { url -> (URL, Date) in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return (url, date)
            }
            .max { $0.1 < $1.1 }?.0

        guard let url = mostRecent else { return nil }
        return Self.decodeFacets(at: url)
    }

    private static func decodeFacets(at url: URL) -> ClaudeFacets? {
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode(FacetsRaw.self, from: data)
        else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        return ClaudeFacets(
            sessionId: raw.sessionId,
            outcome: raw.outcome,
            helpfulness: raw.claudeHelpfulness,
            sessionType: raw.sessionType,
            underlyingGoal: raw.underlyingGoal,
            briefSummary: raw.briefSummary,
            frictionDetail: raw.frictionDetail,
            primarySuccess: raw.primarySuccess,
            frictionCounts: (raw.frictionCounts ?? [:])
                .map { ClaudeFrictionCount(name: $0.key, count: $0.value) }
                .sorted { $0.count > $1.count },
            satisfactionCounts: (raw.userSatisfactionCounts ?? [:])
                .map { ClaudeFrictionCount(name: $0.key, count: $0.value) }
                .sorted { $0.count > $1.count },
            recordedAt: modified)
    }

    // MARK: - live JSONL session

    private func readLiveSession(
        root: URL,
        facets: ClaudeFacets?,
        now: Date,
        pinnedSessionId: String? = nil) -> ClaudeSessionStats?
    {
        let projectsDir = root.appendingPathComponent("projects")
        guard FileManager.default.fileExists(atPath: projectsDir.path) else { return nil }

        // Honor the pinned session if its jsonl exists; the user
        // explicitly chose this one and we shouldn't drift to a
        // newer-mtime sibling without their consent. If the pinned
        // file is missing (renamed/deleted), fall through to latest.
        if let pinnedId = pinnedSessionId {
            if let pinnedURL = Self.findJsonl(in: projectsDir, sessionId: pinnedId) {
                if let session = Self.parseLiveJsonl(
                    url: pinnedURL,
                    root: root,
                    facets: facets,
                    now: now)
                {
                    log.info("readLiveSession: using pinned id=\(pinnedId, privacy: .public) project=\(session.projectName ?? "?", privacy: .public)")
                    return session
                } else {
                    log.warning("readLiveSession: pinned id=\(pinnedId, privacy: .public) jsonl found but failed to parse, falling back to latest")
                }
            } else {
                log.warning("readLiveSession: pinned id=\(pinnedId, privacy: .public) jsonl NOT FOUND, falling back to latest")
            }
        }

        guard let latest = Self.latestJsonl(in: projectsDir) else { return nil }
        let session = Self.parseLiveJsonl(url: latest, root: root, facets: facets, now: now)
        log.info("readLiveSession: using latest path=\(latest.lastPathComponent, privacy: .public) project=\(session?.projectName ?? "?", privacy: .public)")
        return session
    }

    private static func findJsonl(in directory: URL, sessionId: String) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])
        else { return nil }
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            if url.deletingPathExtension().lastPathComponent == sessionId {
                return url
            }
        }
        return nil
    }

    private static func latestJsonl(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return nil }

        var best: (url: URL, modified: Date)?
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if best == nil || modified > best!.modified {
                best = (url, modified)
            }
        }
        return best?.url
    }

    private static func parseLiveJsonl(
        url: URL,
        root: URL,
        facets: ClaudeFacets?,
        now: Date) -> ClaudeSessionStats?
    {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        var sessionId: String?
        var cwd: String?
        var gitBranch: String?
        var modelName: String?
        var version: String?
        var entrypoint: String?
        var permissionMode: String?
        var serviceTier: String?
        var firstActivity: Date?
        var latestActivity: Date?
        var firstUserPrompt: String?

        var userMessageCount = 0
        var assistantMessageCount = 0
        var toolCounts: [String: Int] = [:]
        var sidechainTokens = 0
        var webSearches = 0
        var webFetches = 0
        var thinkingBlockCount = 0

        // Dedup by (msg.id, requestId) — keep the row with max output_tokens
        struct UsageRow {
            var input: Int
            var cacheCreate: Int
            var cacheRead: Int
            var output: Int
            var ephemeral5m: Int
            var ephemeral1h: Int
        }
        var byKey: [String: UsageRow] = [:]
        var lastInput = 0
        var lastOutput = 0
        var lastCacheRead = 0
        var lastCacheCreate = 0
        var lastTurnDurationMs: Int?

        var activeTaskTitle: String?
        var activeTaskChain: [String] = []

        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            let topType = object["type"] as? String

            if topType == "permission-mode" {
                permissionMode = object["permissionMode"] as? String ?? permissionMode
                sessionId = object["sessionId"] as? String ?? sessionId
                continue
            }

            if let ts = object["timestamp"] as? String, let date = ClaudeDate.parse(ts) {
                firstActivity = firstActivity ?? date
                latestActivity = date
            }

            sessionId = (object["sessionId"] as? String) ?? sessionId
            cwd = (object["cwd"] as? String) ?? cwd
            gitBranch = (object["gitBranch"] as? String) ?? gitBranch
            version = (object["version"] as? String) ?? version
            entrypoint = (object["entrypoint"] as? String) ?? entrypoint

            if topType == "user" {
                if (object["isMeta"] as? Bool) == true { continue }
                userMessageCount += 1
                if firstUserPrompt == nil,
                   let message = object["message"] as? [String: Any],
                   let content = message["content"] {
                    firstUserPrompt = Self.extractText(from: content)
                }
                continue
            }

            if topType == "assistant" {
                assistantMessageCount += 1
                guard let message = object["message"] as? [String: Any] else { continue }
                modelName = (message["model"] as? String) ?? modelName
                let messageId = message["id"] as? String ?? ""
                let requestId = object["requestId"] as? String ?? ""
                let key = "\(messageId)|\(requestId)"
                let isSidechain = (object["isSidechain"] as? Bool) ?? false

                // Tool counts + thinking blocks from content[]
                if let contentArr = message["content"] as? [[String: Any]] {
                    for item in contentArr where (item["type"] as? String) == "thinking" {
                        thinkingBlockCount += 1
                    }
                    for item in contentArr where (item["type"] as? String) == "tool_use" {
                        if let name = item["name"] as? String {
                            toolCounts[name, default: 0] += 1
                            activeTaskChain.append(name)
                            if name == "TaskCreate" || name == "Edit" || name == "Write" {
                                if let input = item["input"] as? [String: Any] {
                                    if let title = input["subject"] as? String { activeTaskTitle = title }
                                    else if let path = input["file_path"] as? String {
                                        activeTaskTitle = "editing \((path as NSString).lastPathComponent)"
                                    }
                                }
                            } else if name == "Bash" {
                                if let input = item["input"] as? [String: Any],
                                   let desc = input["description"] as? String {
                                    activeTaskTitle = desc
                                }
                            } else if name == "Read" {
                                if let input = item["input"] as? [String: Any],
                                   let path = input["file_path"] as? String {
                                    activeTaskTitle = "reading \((path as NSString).lastPathComponent)"
                                }
                            }
                        }
                    }
                }

                guard let usage = message["usage"] as? [String: Any] else { continue }
                let input = Self.intValue(usage["input_tokens"])
                let cacheCreate = Self.intValue(usage["cache_creation_input_tokens"])
                let cacheRead = Self.intValue(usage["cache_read_input_tokens"])
                let output = Self.intValue(usage["output_tokens"])
                let ephem5m = (usage["cache_creation"] as? [String: Any]).map { Self.intValue($0["ephemeral_5m_input_tokens"]) } ?? 0
                let ephem1h = (usage["cache_creation"] as? [String: Any]).map { Self.intValue($0["ephemeral_1h_input_tokens"]) } ?? 0
                if let st = usage["service_tier"] as? String { serviceTier = st }
                if let serverTool = usage["server_tool_use"] as? [String: Any] {
                    webSearches += Self.intValue(serverTool["web_search_requests"])
                    webFetches += Self.intValue(serverTool["web_fetch_requests"])
                }

                if isSidechain {
                    sidechainTokens += input + output + cacheRead + cacheCreate
                }

                let existing = byKey[key]
                let newOutput = max(existing?.output ?? 0, output)
                let updated = UsageRow(
                    input: max(existing?.input ?? 0, input),
                    cacheCreate: max(existing?.cacheCreate ?? 0, cacheCreate),
                    cacheRead: max(existing?.cacheRead ?? 0, cacheRead),
                    output: newOutput,
                    ephemeral5m: max(existing?.ephemeral5m ?? 0, ephem5m),
                    ephemeral1h: max(existing?.ephemeral1h ?? 0, ephem1h))
                byKey[key] = updated

                lastInput = input > 1 ? input : lastInput
                lastOutput = output > 0 ? output : lastOutput
                lastCacheRead = cacheRead > 0 ? cacheRead : lastCacheRead
                lastCacheCreate = cacheCreate > 0 ? cacheCreate : lastCacheCreate
                if let durationMs = object["duration_ms"] as? Int {
                    lastTurnDurationMs = durationMs
                }
            }
        }

        let totalInput = byKey.values.reduce(0) { $0 + $1.input }
        let totalOutput = byKey.values.reduce(0) { $0 + $1.output }
        let totalCacheRead = byKey.values.reduce(0) { $0 + $1.cacheRead }
        let totalCacheCreate = byKey.values.reduce(0) { $0 + $1.cacheCreate }

        guard userMessageCount > 0 || assistantMessageCount > 0 else { return nil }

        let projectName = cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? ParsedSessionMeta.projectName(fromEncodedFolder: url.deletingLastPathComponent().lastPathComponent)
        let chain = Array(activeTaskChain.suffix(5))

        let advisor = Self.advisor(
            totalInput: totalInput,
            totalOutput: totalOutput,
            cacheRead: totalCacheRead,
            cacheCreate: totalCacheCreate,
            lastInput: lastInput,
            lastOutput: lastOutput,
            lastCacheRead: lastCacheRead,
            lastCacheCreate: lastCacheCreate,
            modelName: modelName,
            sessionStartedAt: firstActivity,
            latestDate: latestActivity ?? now,
            now: now,
            sidechainTokens: sidechainTokens,
            facets: facets)

        let toolHistogram = toolCounts
            .map { ClaudeToolCount(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }

        let threadTitle = facets?.briefSummary
            ?? facets?.underlyingGoal
            ?? firstUserPrompt.map { Self.truncate($0, to: 60) }
        let displayName = sessionId.flatMap { id in
            Self.sessionMetadata(root: root).names[id]
        } ?? Self.cleanFirstMessage(firstUserPrompt)

        return ClaudeSessionStats(
            advisor: advisor,
            sessionId: sessionId,
            projectPath: cwd,
            projectName: projectName,
            displayName: displayName,
            threadTitle: threadTitle,
            firstPrompt: firstUserPrompt.map { Self.truncate($0, to: 80) },
            gitBranch: gitBranch,
            modelName: modelName,
            cliVersion: version,
            entrypoint: entrypoint,
            permissionMode: permissionMode,
            sessionStartedAt: firstActivity,
            lastActivityAt: latestActivity,
            userMessageCount: userMessageCount,
            assistantMessageCount: assistantMessageCount,
            toolCalls: toolCounts.values.reduce(0, +),
            toolHistogram: Array(toolHistogram.prefix(8)),
            toolErrors: 0,
            userInterruptions: 0,
            totalInputTokens: totalInput,
            cacheCreateInputTokens: totalCacheCreate,
            cacheReadInputTokens: totalCacheRead,
            totalOutputTokens: totalOutput,
            lastInputTokens: lastInput,
            lastOutputTokens: lastOutput,
            lastCacheReadTokens: lastCacheRead,
            lastCacheCreateTokens: lastCacheCreate,
            webSearches: webSearches,
            webFetches: webFetches,
            serviceTier: serviceTier,
            sidechainTokens: sidechainTokens,
            thinkingBlockCount: thinkingBlockCount,
            activeTaskTitle: activeTaskTitle,
            activeTaskChain: chain,
            lastTurnDurationMs: lastTurnDurationMs)
    }

    private static func workContext(from session: ClaudeSessionStats, now: Date) -> WorkContextSnapshot {
        let usedTokens = session.lastInputTokens
            + session.lastCacheReadTokens
            + session.lastCacheCreateTokens
            + session.lastOutputTokens
        let contextWindow = Self.inferContextWindow(model: session.modelName, observedUsedTokens: usedTokens)

        // Per-turn context growth — best signal is what the LAST turn just
        // added to context. When cache is hit, `lastInputTokens` is exactly the
        // new prompt. When cache misses, `lastInputTokens` is the full history,
        // so we cap it to a safe 2k to avoid exploding the average.
        let averageGrowth: Int = {
            let lastInput = session.lastInputTokens
            let lastOutput = session.lastOutputTokens
            let lastCacheRead = session.lastCacheReadTokens

            let newPromptSize = lastCacheRead > 0 ? lastInput : min(lastInput, 2_000)
            let lastNewTokens = newPromptSize + lastOutput

            if lastNewTokens >= 3_000 {
                return lastNewTokens
            }
            // Fallback to historical average × 1.5 if last turn was tiny
            if session.userMessageCount > 0, usedTokens > 0 {
                let perTurn = usedTokens / session.userMessageCount
                return max(3_000, Int(Double(perTurn) * 1.5))
            }
            return 4_000
        }()

        return WorkContextSnapshot(
            sessionId: session.sessionId,
            directory: session.projectPath,
            modelName: session.modelName,
            contextUsedTokens: min(contextWindow, max(0, usedTokens)),
            contextWindowTokens: contextWindow,
            averageGrowthTokens: averageGrowth,
            nextMessageTokens: session.lastInputTokens + session.lastOutputTokens,
            userMessageCount: session.userMessageCount,
            updatedAt: session.lastActivityAt ?? now)
    }

    private static func contextWindowTokens(for model: String?) -> Int {
        guard let model else { return 200_000 }
        let lowered = model.lowercased()
        // Explicit `[1m]` suffix wins.
        if lowered.contains("[1m]") { return 1_000_000 }
        // Models that ship with a 1M context window by default. The JSONL
        // transcript strips runtime suffixes so we can't rely on `[1m]` —
        // the model ID itself is authoritative.
        if lowered.contains("opus-4-7") { return 1_000_000 }
        if lowered.contains("sonnet-4-6") { return 1_000_000 }
        return 200_000
    }

    /// Resolve the context window from the model name. We no longer infer
    /// from observed usage — the model→window mapping is authoritative,
    /// since stats downstream (percentages, p90 buckets, forecasts) all
    /// scale by the denominator and silent fallbacks distort everything.
    private static func inferContextWindow(model: String?, observedUsedTokens: Int) -> Int {
        let base = contextWindowTokens(for: model)
        // Safety net: if we somehow undersized the window and observed usage
        // already exceeds it, jump straight to 1M rather than clipping.
        if observedUsedTokens > base { return 1_000_000 }
        return base
    }

    private static func advisor(
        totalInput: Int,
        totalOutput: Int,
        cacheRead: Int,
        cacheCreate: Int,
        lastInput: Int,
        lastOutput: Int,
        lastCacheRead: Int,
        lastCacheCreate: Int,
        modelName: String?,
        sessionStartedAt: Date?,
        latestDate: Date,
        now: Date,
        sidechainTokens: Int,
        facets: ClaudeFacets?) -> ClaudeAdvisor
    {
        let activeMinutes: Int = {
            guard let start = sessionStartedAt else { return 0 }
            return max(0, Int(latestDate.timeIntervalSince(start) / 60))
        }()
        let totalSessionTokens = totalInput + totalOutput
        let tokensPerMinute = activeMinutes > 0 ? max(0, totalSessionTokens / activeMinutes) : 0
        let sessionCostUSD = modelName.map {
            ClaudePricing.synthesizeUSD(
                model: $0,
                input: totalInput,
                output: totalOutput,
                cacheRead: cacheRead,
                cacheCreate: cacheCreate)
        } ?? 0
        let usdPerMinute: Double? = activeMinutes > 0 && sessionCostUSD > 0
            ? sessionCostUSD / Double(activeMinutes)
            : nil
        let denominator = max(1, totalInput + cacheRead)
        let cacheShare = Double(cacheRead) / Double(denominator) * 100
        let lastTurnTokens = lastInput + lastOutput
        let observedUsed = lastInput + lastCacheRead + lastCacheCreate + lastOutput
        let contextWindow = Self.inferContextWindow(model: modelName, observedUsedTokens: observedUsed)
        let contextUsedShare = contextWindow > 0
            ? Double(observedUsed) / Double(contextWindow) * 100
            : 0
        // Per-turn context growth: cache reads replay existing context.
        // With a cache hit, `lastInput` is the new prompt. Without one,
        // Claude may report the full prompt history as input, so cap it
        // to a small human prompt estimate and let output carry the turn.
        let newPromptSize = lastCacheRead > 0 ? lastInput : min(lastInput, 2_000)
        let perTurnGrowth = max(2_000, newPromptSize + lastOutput)
        let lastTurnShare = contextWindow > 0
            ? Double(perTurnGrowth) / Double(contextWindow) * 100
            : 0
        let idleSeconds = max(0, Int(now.timeIntervalSince(latestDate)))
        let frictionTotal = facets?.totalFriction ?? 0

        let health: CodexThreadHealth
        let recommendation: String
        let riskReason: String

        if frictionTotal >= 5, idleSeconds > 600 {
            health = .stuck
            recommendation = "Recap before the next prompt — friction was high."
            riskReason = "The last logged session had \(frictionTotal) friction events."
        } else if contextUsedShare >= 86 {
            health = .tight
            recommendation = "Wrap this thread before context fills."
            riskReason = "The context window is \(Int(contextUsedShare.rounded()))% full."
        } else if contextUsedShare >= 70 || lastTurnShare >= 35 {
            health = .watch
            recommendation = "Keep the next ask focused."
            riskReason = "Pressure is building on the context window."
        } else if cacheShare >= 70, lastTurnTokens < 60_000 {
            health = .efficient
            recommendation = "Keep going — Claude is replaying context cheaply."
            riskReason = "\(Int(cacheShare.rounded()))% of input is cache reads."
        } else {
            health = .healthy
            recommendation = "Plenty of room — keep shipping."
            riskReason = "No major pressure signal."
        }

        let driver: (String, String)
        if lastInput > 30_000, lastCacheRead > 0 {
            let pct = Int(Double(lastCacheRead) / Double(max(1, lastInput + lastCacheRead)) * 100)
            driver = ("Context replay", "\(pct)% of last input was cached")
        } else if cacheCreate > 30_000 {
            driver = ("Cache build", "\(Self.compact(cacheCreate)) cache write tokens")
        } else if sidechainTokens > 50_000 {
            driver = ("Subagent work", "\(Self.compact(sidechainTokens)) tokens in subagent traffic")
        } else if lastOutput > 4_000 {
            driver = ("Long answer", "\(Self.compact(lastOutput)) output tokens last turn")
        } else if tokensPerMinute > 0 {
            driver = ("Steady burn", "\(Self.compact(tokensPerMinute)) tokens/min this session")
        } else {
            driver = ("Just started", "\(Self.compact(lastTurnTokens)) tokens last turn")
        }

        let contextRemaining = max(0, contextWindow - observedUsed)
        let forecast: String
        if contextUsedShare >= 70 {
            let turnsLeft = max(1, contextRemaining / perTurnGrowth)
            forecast = "~\(turnsLeft) turn\(turnsLeft == 1 ? "" : "s") at this size"
        } else {
            forecast = "Plenty of context left"
        }

        let resetPlan: String
        if contextUsedShare >= 80 {
            resetPlan = "Context is the bottleneck — start fresh after this turn."
        } else if frictionTotal >= 3 {
            resetPlan = "Recap goal — last session logged \(frictionTotal) friction events."
        } else if cacheShare >= 70 {
            resetPlan = "Cache is doing the work — keep this thread alive."
        } else {
            resetPlan = "Pace looks normal for this thread."
        }

        return ClaudeAdvisor(
            health: health,
            recommendation: recommendation,
            primaryDriver: driver.0,
            driverDetail: driver.1,
            forecast: forecast,
            riskReason: riskReason,
            resetPlan: resetPlan,
            lastTurnSharePercent: lastTurnShare,
            projectedTurnsRemaining: nil,
            tokensPerMinute: tokensPerMinute,
            usdPerMinute: usdPerMinute)
    }

    // MARK: - today

    private func buildToday(
        sessionMetas: [ParsedSessionMeta],
        liveSession: ClaudeSessionStats?,
        now: Date) -> DailyUsageStats
    {
        let calendar = Calendar.current

        let todays = sessionMetas.filter { meta in
            guard let start = meta.startTime else { return false }
            return calendar.isDate(start, inSameDayAs: now)
        }

        var requests = todays.reduce(0) { $0 + $1.userMessageCount }
        var input = todays.reduce(0) { $0 + $1.inputTokens }
        var output = todays.reduce(0) { $0 + $1.outputTokens }
        var minutes = todays.reduce(0) { $0 + $1.durationMinutes }

        if let live = liveSession,
           let start = live.sessionStartedAt
        {
            // Count the live session if it started today OR if its last
            // activity is today (session crossed midnight and is still going).
            let startsToday = calendar.isDate(start, inSameDayAs: now)
            let activeToday = live.lastActivityAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false

            if startsToday || activeToday {
                requests = max(requests, live.userMessageCount)
                input = max(input, live.totalInputTokens)
                output = max(output, live.totalOutputTokens)
                if let last = live.lastActivityAt {
                    // For midnight-crossing sessions, only count today's portion.
                    let dayStart = calendar.startOfDay(for: now)
                    let effectiveStart = max(start, dayStart)
                    let liveMinutes = max(0, Int(last.timeIntervalSince(effectiveStart) / 60))
                    minutes = max(minutes, liveMinutes)
                }
            }
        }

        let peakHour = self.peakHourLabel(metas: todays, now: now)

        return DailyUsageStats(
            requests: requests,
            inputTokens: input,
            outputTokens: output,
            activeMinutes: minutes,
            spend: nil,
            peakHourLabel: peakHour)
    }

    private func peakHourLabel(metas: [ParsedSessionMeta], now: Date) -> String? {
        var hours: [Int: Int] = [:]
        for meta in metas {
            for h in meta.messageHours {
                hours[h, default: 0] += 1
            }
        }
        guard let (hour, _) = hours.max(by: { $0.value < $1.value }) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
        return formatter.string(from: date).lowercased()
    }

    // MARK: - windows

    private func buildWindows(
        oauth: ClaudeOAuthUsage?,
        aggregate: ClaudeAggregateStats?,
        today: DailyUsageStats,
        workContext: WorkContextSnapshot?,
        now: Date) -> [UsageWindow]
    {
        // Prefer real OAuth windows when available — these are Anthropic's
        // actual rate-limit reset clocks. Fall back to synthetic pace gauges.
        if let oauth, oauth.hasAnyWindow {
            var windows: [UsageWindow] = []
            if let w = oauth.fiveHour {
                windows.append(
                    UsageWindow(
                        id: "claude-oauth-5h",
                        title: "Session",
                        usedPercent: w.utilization,
                        resetsAt: w.resetsAt))
            }
            if let w = oauth.sevenDay {
                windows.append(
                    UsageWindow(
                        id: "claude-oauth-7d",
                        title: "Weekly",
                        usedPercent: w.utilization,
                        resetsAt: w.resetsAt))
            }
            if let w = oauth.sevenDayOpus {
                windows.append(
                    UsageWindow(
                        id: "claude-oauth-7d-opus",
                        title: "Weekly Opus",
                        usedPercent: w.utilization,
                        resetsAt: w.resetsAt))
            } else if let w = oauth.sevenDaySonnet {
                windows.append(
                    UsageWindow(
                        id: "claude-oauth-7d-sonnet",
                        title: "Weekly Sonnet",
                        usedPercent: w.utilization,
                        resetsAt: w.resetsAt))
            }
            return windows
        }

        // No OAuth signal — fall back to context only. The synthetic
        // "Today's pace" / "Week's pace" gauges were misleading: they
        // measured today vs. (28-day-avg × 1.5), which pegged at 100%
        // trivially and didn't represent any real Anthropic limit. The
        // UI surfaces a "auth not detected" hint instead.
        var windows: [UsageWindow] = []
        if let context = workContext, context.contextWindowTokens > 0 {
            windows.append(
                UsageWindow(
                    id: "claude-context",
                    title: "Context",
                    usedPercent: context.contextUsedPercent,
                    resetsAt: nil))
        }
        return windows
    }

    // MARK: - pattern cards

    private func buildPatternCards(
        aggregate: ClaudeAggregateStats?,
        sessionMetas: [ParsedSessionMeta],
        facets: ClaudeFacets?,
        liveSession: ClaudeSessionStats?,
        oauth: ClaudeOAuthUsage?,
        recentDailySpend: Double?,
        now: Date) -> [ClaudePatternCard]
    {
        var cards: [ClaudePatternCard] = []

        if let band = aggregate?.peakHourBand {
            let label = "\(Self.formatHour(band.start))–\(Self.formatHour(band.end))"
            let isPeakNow = Self.hourBandContains(start: band.start, end: band.end, hour: Calendar.current.component(.hour, from: now))
            let body = isPeakNow
                ? "Right now is in your peak band — \(Int(band.sharePercent.rounded()))% of your turns happen between \(label)."
                : "\(Int(band.sharePercent.rounded()))% of your turns happen between \(label)."
            cards.append(
                ClaudePatternCard(
                    kind: .chronotype,
                    title: "Your peak band: \(label)",
                    body: body,
                    footnote: isPeakNow ? "you're in your peak hour" : nil,
                    highlightValue: "\(Int(band.sharePercent.rounded()))%",
                    progressPercent: band.sharePercent,
                    tone: isPeakNow ? .positive : .neutral,
                    sortPriority: isPeakNow ? 80 : 30))
        }

        // Hour profile baseline: what you usually do at this hour, vs today
        if let card = self.hourProfileCard(sessionMetas: sessionMetas, liveSession: liveSession, now: now) {
            cards.append(card)
        }

        // Cost-per-commit (last 30 days from session-meta + synthetic pricing)
        if let card = self.costPerCommitCard(aggregate: aggregate, sessionMetas: sessionMetas) {
            cards.append(card)
        }

        // Project leaderboard
        if let card = self.projectLeaderboardCard(sessionMetas: sessionMetas) {
            cards.append(card)
        }

        // Bad day detector — facets across recent sessions
        if let card = self.badDayCard(sessionMetas: sessionMetas) {
            cards.append(card)
        }

        // API equivalent — full lifetime synthetic API cost
        if let agg = aggregate, agg.lifetimeSyntheticCostUSD > 1 {
            let cost = agg.lifetimeSyntheticCostUSD
            let perDay = (agg.daysSinceFirstSession ?? 1) > 0
                ? cost / Double(agg.daysSinceFirstSession ?? 1) : cost
            cards.append(
                ClaudePatternCard(
                    kind: .apiEquivalent,
                    title: "API equivalent: $\(Self.formatMoney(cost))",
                    body: "If you'd paid for these tokens at the standard API price, that's roughly $\(Self.formatMoney(cost)) lifetime — about $\(Self.formatMoney(perDay))/day across \(agg.daysSinceFirstSession ?? 0) days.",
                    footnote: "your subscription pays for itself when this exceeds your plan",
                    highlightValue: "$\(Self.formatMoney(cost))",
                    progressPercent: nil,
                    tone: .positive,
                    sortPriority: 65))
        }

        // Overage card — only when the user has overage credits enabled
        if let extra = oauth?.extraUsage, extra.isEnabled, extra.monthlyLimit > 0 {
            let pct = Int(min(100, max(0, extra.utilization)).rounded())
            let used = String(format: "$%.0f", extra.usedCredits)
            let cap = String(format: "$%.0f", extra.monthlyLimit)
            let bodyText: String
            let toneVal: ClaudePatternTone
            if extra.utilization >= 80 {
                bodyText = "You've used \(used) of \(cap) in monthly overage credits. Approaching the cap — review what's burning."
                toneVal = .caution
            } else if extra.utilization >= 50 {
                bodyText = "Halfway through your monthly overage budget — \(used) of \(cap) spent."
                toneVal = .neutral
            } else {
                bodyText = "Plenty of overage runway: \(used) of \(cap) used this month."
                toneVal = .positive
            }
            cards.append(
                ClaudePatternCard(
                    kind: .overage,
                    title: "Overage \(used) of \(cap)",
                    body: bodyText,
                    footnote: "monthly overage credit pool",
                    highlightValue: "\(pct)%",
                    progressPercent: extra.utilization,
                    tone: toneVal,
                    sortPriority: extra.utilization >= 70 ? 95 : 60))
        }

        // Monthly Wrap — current month's totals from session-meta
        if let card = self.monthlyWrapCard(sessionMetas: sessionMetas, facets: facets, now: now) {
            cards.append(card)
        }

        // Overage trajectory — projects when the monthly cap will be hit at current pace
        if let card = self.overageForecastCard(oauth: oauth, recentDailySpend: recentDailySpend, now: now) {
            cards.append(card)
        }

        // Thinking-token spend — extended thinking is invisible cost
        if let card = self.thinkingSpendCard(liveSession: liveSession) {
            cards.append(card)
        }

        // Anxiety meter — slash-command frequency reveals stress
        if let card = self.anxietyMeterCard() {
            cards.append(card)
        }

        // Idle session reclaim — old JSONLs taking up space
        if let card = self.idleReclaimCard() {
            cards.append(card)
        }

        // Plugin marketplace popularity — your plugins ranked, plus popular ones missing
        if let card = self.pluginPopularityCard() {
            cards.append(card)
        }

        // Bash command leaderboard
        if let agg = aggregate {
            let bash = agg.toolLeaderboard.bashCommands
            if let top = bash.first, top.count >= 5 {
                let leaderboard = bash.prefix(5).map { "\($0.name) \($0.count)×" }.joined(separator: " · ")
                cards.append(
                    ClaudePatternCard(
                        kind: .bashLeaderboard,
                        title: "Top shell command: \(top.name)",
                        body: "Across your last \(agg.toolLeaderboard.scannedFileCount) sessions, you ran \(top.name) \(top.count) times via Claude. Top 5: \(leaderboard).",
                        footnote: "candidates for shell aliases",
                        highlightValue: "\(top.count)×",
                        progressPercent: nil,
                        tone: .neutral,
                        sortPriority: 38))
            }

            let mcp = agg.toolLeaderboard.mcpServers
            if let top = mcp.first, top.count >= 3 {
                let leaderboard = mcp.prefix(4).map { "\($0.name) \($0.count)" }.joined(separator: " · ")
                cards.append(
                    ClaudePatternCard(
                        kind: .mcpLeaderboard,
                        title: "Top MCP server: \(top.name)",
                        body: "\(top.count) tool calls to \(top.name) MCP server in recent sessions. Server mix: \(leaderboard).",
                        footnote: "MCP servers earning their config",
                        highlightValue: "\(top.count)",
                        progressPercent: nil,
                        tone: .neutral,
                        sortPriority: 36))
            }

            let skills = agg.toolLeaderboard.skills
            if let top = skills.first, top.count >= 1 {
                let leaderboard = skills.prefix(4).map { "\(Self.shortSkillName($0.name)) \($0.count)" }.joined(separator: " · ")
                cards.append(
                    ClaudePatternCard(
                        kind: .skillLeaderboard,
                        title: "Top skill: \(Self.shortSkillName(top.name))",
                        body: "You invoked \(Self.shortSkillName(top.name)) \(top.count) times. Recent skill mix: \(leaderboard).",
                        footnote: "skills you actually use",
                        highlightValue: "\(top.count)",
                        progressPercent: nil,
                        tone: .positive,
                        sortPriority: 40))
            }

            // FUN: most expensive single turn ever (recent JSONLs)
            if let card = self.mostExpensiveTurnCard(root: Self.claudeRoot()) {
                cards.append(card)
            }

            // FUN: overage receipts ($X = N lattes / games / etc.)
            if let card = self.overageReceiptsCard(oauth: oauth) {
                cards.append(card)
            }

            // FUN: pasted novel — paste-cache size
            if let card = self.pastedNovelCard() {
                cards.append(card)
            }

            // FUN: context deaths (/compact count)
            if let card = self.contextDeathsCard() {
                cards.append(card)
            }

            // FUN: regret index (/rewind count)
            if let card = self.regretIndexCard() {
                cards.append(card)
            }

            // FUN: the very first prompt
            if let card = self.firstPromptEverCard() {
                cards.append(card)
            }

            // FUN: burnstar sign — derived persona
            if let card = self.burnstarSignCard(aggregate: agg, sessionMetas: sessionMetas, liveSession: liveSession) {
                cards.append(card)
            }

            // FUN: codename collector — saved plan filenames
            if let card = self.codenameCollectorCard() {
                cards.append(card)
            }

            // FUN: weekend warrior — session distribution by day-of-week
            if let card = self.weekendWarriorCard(sessionMetas: sessionMetas) {
                cards.append(card)
            }

            // FUN: achievements unlocked
            if let card = self.achievementsCard(aggregate: agg, sessionMetas: sessionMetas, liveSession: liveSession) {
                cards.append(card)
            }

            // FUN: anniversary — round-number day/session/streak
            if let card = self.anniversaryCard(aggregate: agg) {
                cards.append(card)
            }

            // FUN: skip list — rest days
            if let card = self.skipListCard(aggregate: agg) {
                cards.append(card)
            }

            // Beta gate timeline — your own anthropic-beta header as a calendar
            if !agg.betaGates.isEmpty {
                let mostRecent = agg.betaGates.first!
                let labels = agg.betaGates.prefix(4).map { gate in
                    if let date = gate.date {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "MMM yyyy"
                        return "\(gate.humanLabel) (\(formatter.string(from: date)))"
                    }
                    return gate.humanLabel
                }.joined(separator: " · ")
                let mostRecentLabel: String
                if let date = mostRecent.date {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "MMM d, yyyy"
                    mostRecentLabel = formatter.string(from: date)
                } else {
                    mostRecentLabel = "—"
                }
                cards.append(
                    ClaudePatternCard(
                        kind: .betaTimeline,
                        title: "\(agg.betaGates.count) Anthropic betas active",
                        body: "Your `anthropic-beta` header carries \(agg.betaGates.count) experiments. Most recent: \(mostRecent.humanLabel) (\(mostRecentLabel)). Recent trail: \(labels).",
                        footnote: "experiments you're opted into",
                        highlightValue: "\(agg.betaGates.count)",
                        progressPercent: nil,
                        tone: .positive,
                        sortPriority: 48))
            }
        }

        if let agg = aggregate,
           agg.lifetimeCacheReadTokens > 0
        {
            let denominator = max(1, agg.lifetimeInputTokens + agg.lifetimeCacheReadTokens + agg.lifetimeCacheCreationTokens)
            let cachePct = Double(agg.lifetimeCacheReadTokens) / Double(denominator) * 100
            // Synthetic API-cost savings: cache reads are ~10% of regular input cost on the
            // common Sonnet-grade tier, so the saved delta = cacheReadTokens × (input - cacheRead price).
            let savingsUSD = Double(agg.lifetimeCacheReadTokens) / 1_000_000.0 * (3.0 - 0.30)
            cards.append(
                ClaudePatternCard(
                    kind: .cacheSavings,
                    title: "Cache hit \(Int(cachePct.rounded()))%",
                    body: "Your prompt cache replays \(Int(cachePct.rounded()))% of input tokens. On API pricing that's roughly $\(Self.formatMoney(savingsUSD)) you'd be paying instead.",
                    footnote: "lifetime savings (synthetic)",
                    highlightValue: "$\(Self.formatMoney(savingsUSD))",
                    progressPercent: cachePct,
                    tone: .positive,
                    sortPriority: cachePct >= 80 ? 70 : 40))
        }

        if let agg = aggregate, agg.longestSessionMinutes > 60 {
            let label: String
            let m = agg.longestSessionMinutes
            if m >= 1440 {
                let d = m / 1440
                let hr = (m % 1440) / 60
                label = hr == 0 ? "\(d)d" : "\(d)d \(hr)h"
            } else {
                let h = m / 60
                let mm = m % 60
                label = mm == 0 ? "\(h)h" : "\(h)h \(mm)m"
            }
            let dateLabel: String
            if let date = agg.longestSessionDate {
                let f = DateFormatter()
                f.dateFormat = "MMM d"
                dateLabel = f.string(from: date)
            } else { dateLabel = "—" }
            cards.append(
                ClaudePatternCard(
                    kind: .marathon,
                    title: "Longest session: \(label)",
                    body: "\(dateLabel) · \(agg.longestSessionMessageCount.formatted()) messages — your record so far.",
                    footnote: "personal best",
                    highlightValue: label,
                    progressPercent: nil,
                    tone: .neutral,
                    sortPriority: 25))
        }

        if let agg = aggregate, agg.streakDays > 1 {
            let dayN = agg.daysSinceFirstSession ?? agg.streakDays
            cards.append(
                ClaudePatternCard(
                    kind: .streak,
                    title: "Day \(dayN) · \(agg.streakDays)-day streak",
                    body: "You've used Claude Code on \(agg.streakDays) consecutive days. \(agg.totalSessions) total sessions, \(agg.totalMessages.formatted()) messages.",
                    footnote: "consistency wins",
                    highlightValue: "\(agg.streakDays)d",
                    progressPercent: min(100, Double(agg.streakDays) * 3),
                    tone: .positive,
                    sortPriority: agg.streakDays >= 7 ? 60 : 35))
        }

        if let agg = aggregate, !agg.modelMix.isEmpty {
            let top = agg.modelMix.first!
            let body = agg.modelMix.prefix(3)
                .map { "\($0.modelName) \(Int($0.percent.rounded()))%" }
                .joined(separator: " · ")
            cards.append(
                ClaudePatternCard(
                    kind: .modelMix,
                    title: "You're \(Int(top.percent.rounded()))% \(top.modelName)",
                    body: body,
                    footnote: "lifetime model split",
                    highlightValue: "\(Int(top.percent.rounded()))%",
                    progressPercent: top.percent,
                    tone: .neutral,
                    sortPriority: 30))
        }

        if let live = liveSession, !live.toolHistogram.isEmpty {
            let topTool = live.toolHistogram.first!
            let total = live.toolHistogram.reduce(0) { $0 + $1.count }
            let pct = total > 0 ? Double(topTool.count) / Double(total) * 100 : 0
            cards.append(
                ClaudePatternCard(
                    kind: .toolBias,
                    title: "Top tool right now: \(topTool.name)",
                    body: "\(Int(pct.rounded()))% of this session's tool calls are \(topTool.name). Chain so far: \(live.activeTaskChain.suffix(4).joined(separator: " → "))",
                    footnote: "live session",
                    highlightValue: "\(topTool.count)×",
                    progressPercent: pct,
                    tone: .neutral,
                    sortPriority: 50))
        }

        let allFriction = sessionMetas.reduce(0) { $0 + $1.toolErrors }
        let allInterrupts = sessionMetas.reduce(0) { $0 + $1.userInterruptions }
        if allFriction + allInterrupts > 0, sessionMetas.count >= 5 {
            let avgFriction = Double(allFriction) / Double(max(1, sessionMetas.count))
            cards.append(
                ClaudePatternCard(
                    kind: .wrongPath,
                    title: "Friction: \(allFriction) errors, \(allInterrupts) interrupts",
                    body: "Across \(sessionMetas.count) recent sessions, you averaged \(String(format: "%.1f", avgFriction)) tool errors per session.",
                    footnote: "lower is better",
                    highlightValue: "\(allFriction)",
                    progressPercent: min(100, avgFriction * 20),
                    tone: avgFriction > 3 ? .caution : .neutral,
                    sortPriority: avgFriction > 3 ? 75 : 25))
        }

        let totalLines = sessionMetas.reduce(0) { $0 + $1.linesAdded }
        let totalCommits = sessionMetas.reduce(0) { $0 + $1.gitCommits }
        if totalLines > 0 || totalCommits > 0 {
            let perCommit = totalCommits > 0 ? totalLines / totalCommits : 0
            cards.append(
                ClaudePatternCard(
                    kind: .codeImpact,
                    title: "+\(totalLines.formatted()) lines · \(totalCommits) commits",
                    body: totalCommits > 0
                        ? "About \(perCommit) lines per commit across \(sessionMetas.count) recent sessions."
                        : "Lines shipped across \(sessionMetas.count) recent sessions — Claude moved real code.",
                    footnote: "last 30 days",
                    highlightValue: "+\(Self.compact(totalLines))",
                    progressPercent: nil,
                    tone: .positive,
                    sortPriority: 45))
        }

        if let agg = aggregate, agg.speculationTimeSavedMs > 0 {
            let seconds = agg.speculationTimeSavedMs / 1000
            let minutes = seconds / 60
            let label = minutes >= 1 ? "\(minutes) min" : "\(seconds)s"
            cards.append(
                ClaudePatternCard(
                    kind: .speculation,
                    title: "Speculation saved you \(label)",
                    body: "Speculative decoding shaved \(label) off your wait time — a hidden Anthropic optimisation that just runs.",
                    footnote: "lifetime",
                    highlightValue: label,
                    progressPercent: nil,
                    tone: .positive,
                    sortPriority: 20))
        }

        if let facets, let summary = facets.briefSummary {
            let outcome = facets.outcome ?? "—"
            let helpful = facets.helpfulness ?? "—"
            let toneVal: ClaudePatternTone = outcome.contains("achieved") ? .positive
                : (facets.totalFriction >= 3 ? .caution : .neutral)
            cards.append(
                ClaudePatternCard(
                    kind: .wrap,
                    title: "Last session: \(outcome.replacingOccurrences(of: "_", with: " "))",
                    body: Self.truncate(summary, to: 160),
                    footnote: "Claude was \(helpful)",
                    highlightValue: nil,
                    progressPercent: nil,
                    tone: toneVal,
                    sortPriority: facets.totalFriction >= 3 ? 70 : 40))
        }

        return cards
    }

    private static func rankCards(_ cards: [ClaudePatternCard]) -> [ClaudePatternCard] {
        cards.sorted { lhs, rhs in
            if lhs.sortPriority != rhs.sortPriority {
                return lhs.sortPriority > rhs.sortPriority
            }
            return lhs.title < rhs.title
        }
    }

    // MARK: - Card builders

    private func hourProfileCard(
        sessionMetas: [ParsedSessionMeta],
        liveSession: ClaudeSessionStats?,
        now: Date) -> ClaudePatternCard?
    {
        // Build a baseline of which tools you typically use during the current hour.
        // Today's tool histogram comes from the live session (or recent metas if idle).
        let currentHour = Calendar.current.component(.hour, from: now)

        // Step 1: identify metas whose `messageHours` overlap the current hour.
        let inHour = sessionMetas.filter { meta in
            meta.messageHours.contains(currentHour)
        }
        guard inHour.count >= 3 else { return nil }

        var baseline: [String: Int] = [:]
        for meta in inHour {
            for (tool, count) in meta.toolCounts {
                baseline[tool, default: 0] += count
            }
        }
        let baselineTotal = baseline.values.reduce(0, +)
        guard baselineTotal > 0 else { return nil }
        let topBaseline = baseline.sorted { $0.value > $1.value }.prefix(3)
        let baselineLabel = topBaseline
            .map { "\($0.key) \(Int(Double($0.value) / Double(baselineTotal) * 100))%" }
            .joined(separator: " · ")

        // Step 2: today's mix.
        var todayMix: [String: Int] = [:]
        if let live = liveSession {
            for tool in live.toolHistogram { todayMix[tool.name, default: 0] += tool.count }
        }
        let todayTotal = todayMix.values.reduce(0, +)
        let topToday = todayMix.max { $0.value < $1.value }?.key

        // Step 3: detect anomaly — today's top tool isn't in the baseline top 3.
        let baselineTopNames = Set(topBaseline.map { $0.key })
        let isAnomalous = topToday.map { !baselineTopNames.contains($0) } ?? false

        let hourLabel = Self.formatHour(currentHour)
        let body: String
        if let topToday, todayTotal > 0 {
            let todayPct = Int(Double(todayMix[topToday] ?? 0) / Double(todayTotal) * 100)
            if isAnomalous {
                body = "Right now (\(hourLabel)) you usually do \(baselineLabel). Today you're \(todayPct)% \(topToday) — different day."
            } else {
                body = "Right now (\(hourLabel)) you usually do \(baselineLabel). Today is on rhythm."
            }
        } else {
            body = "Right now (\(hourLabel)) you usually do \(baselineLabel)."
        }

        return ClaudePatternCard(
            kind: .hourProfile,
            title: "What you do at \(hourLabel)",
            body: body,
            footnote: "based on \(inHour.count) sessions in this hour",
            highlightValue: nil,
            progressPercent: nil,
            tone: isAnomalous ? .caution : .neutral,
            sortPriority: isAnomalous ? 85 : 35)
    }

    private func costPerCommitCard(
        aggregate: ClaudeAggregateStats?,
        sessionMetas: [ParsedSessionMeta]) -> ClaudePatternCard?
    {
        let commits = sessionMetas.reduce(0) { $0 + $1.gitCommits }
        guard commits > 0 else { return nil }
        // Approximate session cost using sonnet-grade pricing on session-meta totals.
        // (Per-session model breakdown isn't in session-meta; we assume the lifetime mix.)
        let totalInput = sessionMetas.reduce(0) { $0 + $1.inputTokens }
        let totalOutput = sessionMetas.reduce(0) { $0 + $1.outputTokens }
        let totalCost: Double
        if let agg = aggregate, agg.lifetimeSyntheticCostUSD > 0,
           let topModel = agg.modelMix.first?.modelName
        {
            // Use the dominant model's pricing as a proxy.
            let actualModel = agg.lifetimeModelTokens.first?.modelName ?? topModel
            totalCost = ClaudePricing.synthesizeUSD(
                model: actualModel,
                input: totalInput,
                output: totalOutput,
                cacheRead: 0,
                cacheCreate: 0)
        } else {
            totalCost = ClaudePricing.synthesizeUSD(
                model: "sonnet",
                input: totalInput,
                output: totalOutput,
                cacheRead: 0,
                cacheCreate: 0)
        }
        guard totalCost > 0.5 else { return nil }
        let perCommit = totalCost / Double(commits)
        let dollars = String(format: "%.2f", perCommit)
        return ClaudePatternCard(
            kind: .costPerCommit,
            title: "$\(dollars) per commit",
            body: "Across \(sessionMetas.count) recent sessions and \(commits) commits, your synthetic API cost averages $\(dollars) per shipped commit.",
            footnote: "synthetic API equivalent · last 30 days",
            highlightValue: "$\(dollars)",
            progressPercent: nil,
            tone: perCommit > 5 ? .caution : .positive,
            sortPriority: perCommit > 10 ? 75 : 40)
    }

    private func projectLeaderboardCard(sessionMetas: [ParsedSessionMeta]) -> ClaudePatternCard? {
        guard sessionMetas.count >= 3 else { return nil }
        var counts: [String: (sessions: Int, tokens: Int, lines: Int)] = [:]
        for meta in sessionMetas {
            let key = meta.projectName
            var current = counts[key] ?? (0, 0, 0)
            current.sessions += 1
            current.tokens += meta.inputTokens + meta.outputTokens
            current.lines += meta.linesAdded
            counts[key] = current
        }
        guard counts.count >= 2 else { return nil }
        let sorted = counts.sorted { $0.value.sessions > $1.value.sessions }.prefix(3)
        guard let top = sorted.first else { return nil }
        let totalSessions = sessionMetas.count
        let topPct = Int(Double(top.value.sessions) / Double(totalSessions) * 100)
        let leaderboard = sorted
            .map { "\($0.key) \($0.value.sessions)" }
            .joined(separator: " · ")
        return ClaudePatternCard(
            kind: .projectLeaderboard,
            title: "Top project: \(top.key)",
            body: "\(topPct)% of your last \(totalSessions) sessions were on \(top.key). Top three: \(leaderboard).",
            footnote: "last 30 days · sessions",
            highlightValue: "\(topPct)%",
            progressPercent: Double(topPct),
            tone: .neutral,
            sortPriority: topPct > 60 ? 55 : 30)
    }

    private func badDayCard(sessionMetas: [ParsedSessionMeta]) -> ClaudePatternCard? {
        // Look at the last 5 sessions. If 3+ have notable interruptions or errors, surface.
        let recent = sessionMetas.prefix(5)
        guard recent.count >= 3 else { return nil }
        let badCount = recent.filter { $0.userInterruptions >= 2 || $0.toolErrors >= 5 }.count
        guard badCount >= 3 else { return nil }
        let totalErrors = recent.reduce(0) { $0 + $1.toolErrors }
        let totalInterrupts = recent.reduce(0) { $0 + $1.userInterruptions }
        return ClaudePatternCard(
            kind: .badDay,
            title: "This stretch is rough",
            body: "Last \(recent.count) sessions had \(totalErrors) tool errors and \(totalInterrupts) interrupts. Maybe recap, restart, or pull a smaller scope.",
            footnote: "friction signal — recent sessions",
            highlightValue: "\(badCount)/\(recent.count)",
            progressPercent: Double(badCount) / Double(recent.count) * 100,
            tone: .caution,
            sortPriority: 90)
    }

    private func monthlyWrapCard(
        sessionMetas: [ParsedSessionMeta],
        facets: ClaudeFacets?,
        now: Date) -> ClaudePatternCard?
    {
        let calendar = Calendar.current
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let monthMetas = sessionMetas.filter { ($0.startTime ?? .distantPast) >= monthStart }
        guard monthMetas.count >= 3 else { return nil }

        let turns = monthMetas.reduce(0) { $0 + $1.userMessageCount }
        let commits = monthMetas.reduce(0) { $0 + $1.gitCommits }
        let lines = monthMetas.reduce(0) { $0 + $1.linesAdded }
        let topProject = monthMetas
            .reduce(into: [String: Int]()) { dict, meta in dict[meta.projectName, default: 0] += 1 }
            .max { $0.value < $1.value }?.key ?? "—"

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM yyyy"
        let monthLabel = monthFormatter.string(from: now)

        let summaryLine = facets?.briefSummary.map { Self.truncate($0, to: 90) }
            ?? "\(monthMetas.count) sessions, top project \(topProject)."

        return ClaudePatternCard(
            kind: .monthlyWrap,
            title: "\(monthLabel) so far",
            body: "\(turns.formatted()) turns · \(commits) commits · +\(lines.formatted()) lines · top project \(topProject). \(summaryLine)",
            footnote: "month-to-date recap",
            highlightValue: "\(monthMetas.count)",
            progressPercent: nil,
            tone: .positive,
            sortPriority: 50)
    }

    private func overageForecastCard(oauth: ClaudeOAuthUsage?, recentDailySpend: Double?, now: Date) -> ClaudePatternCard? {
        guard let extra = oauth?.extraUsage,
              extra.isEnabled,
              extra.monthlyLimit > 0,
              extra.usedCredits > 0
        else { return nil }

        let calendar = Calendar.current
        guard calendar.dateInterval(of: .month, for: now) != nil else { return nil }
        let dayOfMonth = calendar.component(.day, from: now)
        let totalDays = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let daysRemaining = max(1, totalDays - dayOfMonth)

        // Prefer the recent-rate signal when available — it's a real
        // 7-day rolling slope, decoupled from a heavy first-of-month
        // that month-to-date averaging would let dominate for weeks.
        // Fall back to MTD avg only when we don't have enough samples.
        let dailyBurn: Double
        let usingRecentRate: Bool
        if let recent = recentDailySpend, recent >= 0 {
            dailyBurn = recent
            usingRecentRate = true
        } else {
            dailyBurn = extra.usedCredits / Double(max(1, dayOfMonth))
            usingRecentRate = false
        }

        let projectedTotal = extra.usedCredits + dailyBurn * Double(daysRemaining)
        let projectedPct = min(200, projectedTotal / extra.monthlyLimit * 100)
        let willHit = projectedTotal >= extra.monthlyLimit
        let projectionFootnote = usingRecentRate
            ? "based on last 7 days"
            : "based on month-to-date average · less reliable"

        let body: String
        let toneVal: ClaudePatternTone
        let footnote: String
        let highlight: String

        if willHit, dailyBurn > 0 {
            // Days until cap is hit at current burn
            let remainingBudget = extra.monthlyLimit - extra.usedCredits
            let daysToCap = max(0, Int((remainingBudget / dailyBurn).rounded()))
            let capDate = calendar.date(byAdding: .day, value: daysToCap, to: now) ?? now
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            body = "At $\(Self.formatMoney(dailyBurn))/day you'll hit your $\(Self.formatMoney(extra.monthlyLimit)) overage cap by \(formatter.string(from: capDate)) — \(daysToCap) day\(daysToCap == 1 ? "" : "s") away. Projected total: $\(Self.formatMoney(projectedTotal))."
            toneVal = daysToCap <= 3 ? .caution : .neutral
            footnote = projectionFootnote
            highlight = formatter.string(from: capDate)
        } else {
            body = "At $\(Self.formatMoney(dailyBurn))/day you're on track for $\(Self.formatMoney(projectedTotal)) by month end — \(Int(projectedPct.rounded()))% of your $\(Self.formatMoney(extra.monthlyLimit)) overage cap."
            toneVal = .positive
            footnote = projectionFootnote
            highlight = "$\(Self.formatMoney(projectedTotal))"
        }

        return ClaudePatternCard(
            kind: .overageForecast,
            title: willHit ? "Cap projected by month end" : "Pacing under cap",
            body: body,
            footnote: footnote,
            highlightValue: highlight,
            progressPercent: min(100, projectedPct),
            tone: toneVal,
            sortPriority: willHit ? 88 : 55)
    }

    private func thinkingSpendCard(liveSession: ClaudeSessionStats?) -> ClaudePatternCard? {
        guard let live = liveSession,
              live.thinkingBlockCount > 0,
              live.assistantMessageCount > 0
        else { return nil }
        let pct = Double(live.thinkingBlockCount) / Double(live.assistantMessageCount) * 100
        let pctRounded = Int(pct.rounded())
        return ClaudePatternCard(
            kind: .thinkingSpend,
            title: "\(live.thinkingBlockCount) thinking turns",
            body: "\(pctRounded)% of this session's assistant turns include extended-thinking blocks. Reasoning tokens count against output budget but don't show in the UI — they're the invisible part of your spend.",
            footnote: "live session · thinking is on",
            highlightValue: "\(pctRounded)%",
            progressPercent: pct,
            tone: pct > 60 ? .caution : .neutral,
            sortPriority: pct > 60 ? 70 : 35)
    }

    private func anxietyMeterCard() -> ClaudePatternCard? {
        let slashCounts = self.slashCommandCounts()
        guard !slashCounts.isEmpty else { return nil }

        let sorted = slashCounts.sorted { $0.value > $1.value }
        let top = sorted.prefix(5)
        let leaderboard = top.map { "\($0.key) \($0.value)×" }.joined(separator: " · ")

        // Anxiety signals: /context (window pressure), /compact (manual escape), /rate-limit-options (limits)
        let anxietyPrefixes = ["/context", "/compact", "/rate-limit-options"]
        let anxietyTotal = slashCounts.filter { anxietyPrefixes.contains($0.key) }.values.reduce(0, +)

        let title: String
        let body: String
        let toneVal: ClaudePatternTone
        let priority: Double

        if anxietyTotal >= 30 {
            title = "Anxiety meter: \(anxietyTotal) anxious commands"
            body = "You've typed \(slashCounts["/context"] ?? 0)× /context · \(slashCounts["/compact"] ?? 0)× /compact · \(slashCounts["/rate-limit-options"] ?? 0)× /rate-limit-options. Top 5: \(leaderboard)."
            toneVal = .caution
            priority = 78
        } else if let first = top.first {
            title = "Top slash command: \(first.key)"
            body = "You've typed \(first.key) \(first.value) times. Full top 5: \(leaderboard)."
            toneVal = .neutral
            priority = 35
        } else {
            return nil
        }

        return ClaudePatternCard(
            kind: .anxietyMeter,
            title: title,
            body: body,
            footnote: "from your typed history",
            highlightValue: top.first.map { "\($0.value)" },
            progressPercent: nil,
            tone: toneVal,
            sortPriority: priority)
    }

    private func idleReclaimCard() -> ClaudePatternCard? {
        let projectsRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        guard let enumerator = FileManager.default.enumerator(
            at: projectsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles])
        else { return nil }

        let cutoff = Date().addingTimeInterval(-48 * 3600)
        var idleCount = 0
        var idleBytes: Int64 = 0
        var projectSet: Set<String> = []

        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let mtime = values.contentModificationDate,
                  let size = values.fileSize
            else { continue }
            if mtime < cutoff {
                idleCount += 1
                idleBytes += Int64(size)
                projectSet.insert(url.deletingLastPathComponent().lastPathComponent)
            }
        }
        guard idleCount >= 5 else { return nil }

        let mb = Double(idleBytes) / 1_048_576
        let label: String
        if mb >= 100 { label = String(format: "%.0fMB", mb) }
        else if mb >= 10 { label = String(format: "%.1fMB", mb) }
        else { label = String(format: "%.2fMB", mb) }

        return ClaudePatternCard(
            kind: .idleReclaim,
            title: "\(idleCount) idle sessions · \(label)",
            body: "You have \(idleCount) JSONL transcripts older than 48h across \(projectSet.count) project folders. Reclaim \(label) by archiving sessions you're done with.",
            footnote: "no live work in 48h",
            highlightValue: label,
            progressPercent: nil,
            tone: idleCount > 200 ? .caution : .neutral,
            sortPriority: idleCount > 200 ? 55 : 25)
    }

    private func pluginPopularityCard() -> ClaudePatternCard? {
        let pluginsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/plugins")
        let installedURL = pluginsDir.appendingPathComponent("installed_plugins.json")
        let countsURL = pluginsDir.appendingPathComponent("install-counts-cache.json")

        guard let installedData = try? Data(contentsOf: installedURL),
              let installed = try? JSONSerialization.jsonObject(with: installedData) as? [String: Any],
              let pluginsMap = installed["plugins"] as? [String: Any],
              let countsData = try? Data(contentsOf: countsURL),
              let counts = try? JSONSerialization.jsonObject(with: countsData) as? [String: Any],
              let countsArr = counts["counts"] as? [[String: Any]]
        else { return nil }

        var rankings: [(plugin: String, installs: Int)] = []
        for entry in countsArr {
            guard let name = entry["plugin"] as? String,
                  let installCount = entry["unique_installs"] as? Int
            else { continue }
            rankings.append((name, installCount))
        }
        guard !rankings.isEmpty else { return nil }
        rankings.sort { $0.installs > $1.installs }

        let installedNames = Set(pluginsMap.keys)
        var bestRank: (name: String, rank: Int, installs: Int)?
        for (idx, item) in rankings.enumerated() {
            if installedNames.contains(item.plugin) {
                bestRank = (item.plugin, idx + 1, item.installs)
                break
            }
        }

        let topMissing = rankings.prefix(8).first { !installedNames.contains($0.plugin) }
        let totalCommunityInstalls = pluginsMap.keys
            .compactMap { name in rankings.first(where: { $0.plugin == name })?.installs }
            .reduce(0, +)

        let body: String
        let highlight: String?
        if let best = bestRank, let missing = topMissing {
            let bestPlugin = Self.shortPluginName(best.name)
            let missingPlugin = Self.shortPluginName(missing.plugin)
            body = "Your top plugin is `\(bestPlugin)` — ranked #\(best.rank) of \(rankings.count) (\(Self.formatCount(best.installs)) installs). Most popular plugin you don't have: `\(missingPlugin)` (\(Self.formatCount(missing.installs)))."
            highlight = "#\(best.rank)"
        } else if let best = bestRank {
            let bestPlugin = Self.shortPluginName(best.name)
            body = "Your top plugin is `\(bestPlugin)` — ranked #\(best.rank) of \(rankings.count) marketplace plugins (\(Self.formatCount(best.installs)) total installs)."
            highlight = "#\(best.rank)"
        } else if let missing = topMissing {
            let missingPlugin = Self.shortPluginName(missing.plugin)
            body = "Most popular plugin you don't have: `\(missingPlugin)` — \(Self.formatCount(missing.installs)) installs across the Claude Code community."
            highlight = Self.formatCount(missing.installs)
        } else {
            return nil
        }

        return ClaudePatternCard(
            kind: .pluginPopularity,
            title: "\(installedNames.count) plugins · \(Self.formatCount(totalCommunityInstalls)) community reach",
            body: body,
            footnote: "marketplace install counts",
            highlightValue: highlight,
            progressPercent: nil,
            tone: .neutral,
            sortPriority: 42)
    }

    private static func shortSkillName(_ raw: String) -> String {
        // Skills look like "workbench:research" — keep as-is, but trim if very long.
        if raw.count > 28 { return String(raw.prefix(27)) + "…" }
        return raw
    }

    private static func shortPluginName(_ qualified: String) -> String {
        // "frontend-design@claude-plugins-official" → "frontend-design"
        qualified.split(separator: "@").first.map(String.init) ?? qualified
    }

    private static func formatCount(_ value: Int) -> String {
        switch value {
        case 1_000_000...:
            return String(format: "%.1fM", Double(value) / 1_000_000)
        case 100_000...:
            return "\(value / 1_000)k"
        case 1_000...:
            return String(format: "%.1fk", Double(value) / 1_000)
        default:
            return "\(value)"
        }
    }

    // MARK: - health indicators

    private func buildHealth(
        root: URL,
        liveSession: ClaudeSessionStats?,
        oauth: ClaudeOAuthUsage?,
        now: Date) -> [ClaudeHealthIndicator]
    {
        var indicators: [ClaudeHealthIndicator] = []

        if oauth != nil {
            indicators.append(
                ClaudeHealthIndicator(label: "OAuth", detail: "live", status: .ok))
        } else {
            let credentialsPath = root.appendingPathComponent(".credentials.json")
            if FileManager.default.fileExists(atPath: credentialsPath.path) {
                indicators.append(
                    ClaudeHealthIndicator(label: "OAuth", detail: "creds present, fetch failed", status: .warn))
            } else {
                indicators.append(
                    ClaudeHealthIndicator(label: "OAuth", detail: "no live token", status: .unknown))
            }
        }

        let stats = self.recentTengEvents(root: root, now: now)
        if stats.stalls > 0 {
            indicators.append(
                ClaudeHealthIndicator(
                    label: "Stalls",
                    detail: "\(stats.stalls) today",
                    status: stats.stalls > 3 ? .error : .warn))
        } else {
            indicators.append(
                ClaudeHealthIndicator(label: "Stalls", detail: "none today", status: .ok))
        }

        if stats.mcpFailed > 0 {
            indicators.append(
                ClaudeHealthIndicator(
                    label: "MCP",
                    detail: "\(stats.mcpSucceeded) ok / \(stats.mcpFailed) failed",
                    status: .warn))
        } else if stats.mcpSucceeded > 0 {
            indicators.append(
                ClaudeHealthIndicator(label: "MCP", detail: "\(stats.mcpSucceeded) servers ok", status: .ok))
        }

        if stats.rateLimited > 0 {
            indicators.append(
                ClaudeHealthIndicator(
                    label: "Limits",
                    detail: "\(stats.rateLimited) rate-limit hits",
                    status: .warn))
        }

        if let latest = stats.latestCompactionAt {
            let age = max(0, Int(now.timeIntervalSince(latest)))
            let label: String
            if age < 60 { label = "\(age)s ago" }
            else if age < 3_600 { label = "\(age / 60)m ago" }
            else if age < 86_400 { label = "\(age / 3_600)h ago" }
            else { label = "\(age / 86_400)d ago" }
            indicators.append(
                ClaudeHealthIndicator(
                    label: "Compact",
                    detail: label,
                    status: age < 1_800 ? .warn : .ok))
        }

        if let live = liveSession {
            let used = live.lastInputTokens + live.lastCacheReadTokens + live.lastCacheCreateTokens
            let context = Self.inferContextWindow(model: live.modelName, observedUsedTokens: used)
            let pct = Int(min(100, Double(used) / Double(max(1, context)) * 100).rounded())
            let status: ClaudeHealthStatus = pct >= 86 ? .warn : (pct >= 70 ? .warn : .ok)
            indicators.append(
                ClaudeHealthIndicator(
                    label: "Context",
                    detail: "\(pct)% used (\(Self.compact(used))/\(Self.compact(context)))",
                    status: status))
        }

        return indicators
    }

    private func recentTengEvents(root: URL, now: Date) -> TengEventStats {
        var result = TengEventStats()
        let dir = root.appendingPathComponent("telemetry")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return result }

        let dayAgo = now.addingTimeInterval(-86_400)
        let recent = files
            .filter { $0.pathExtension == "json" }
            .filter {
                let date = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return date > dayAgo
            }
            .prefix(60)

        for url in recent {
            guard let content = Self.boundedText(from: url, maxBytes: 1_500_000) else { continue }
            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let payload = object["event_data"] as? [String: Any],
                      let name = payload["event_name"] as? String
                else { continue }
                let timestamp = (payload["client_timestamp"] as? String).flatMap(ClaudeDate.parse)
                switch name {
                case "tengu_streaming_stall", "tengu_streaming_stall_summary":
                    result.stalls += 1
                case "tengu_mcp_server_connection_succeeded":
                    result.mcpSucceeded += 1
                case "tengu_mcp_server_connection_failed":
                    result.mcpFailed += 1
                case "tengu_claudeai_limits_status_changed", "tengu_rate_limit_options_menu_cancel":
                    result.rateLimited += 1
                case "tengu_compact", "tengu_compact_cache_sharing_success", "tengu_post_compact_file_restore_success":
                    result.compactions += 1
                    if let ts = timestamp,
                       result.latestCompactionAt.map({ ts > $0 }) ?? true
                    {
                        result.latestCompactionAt = ts
                    }
                default:
                    break
                }
            }
        }
        return result
    }

    private struct TengEventStats {
        var stalls = 0
        var mcpSucceeded = 0
        var mcpFailed = 0
        var rateLimited = 0
        var compactions = 0
        var latestCompactionAt: Date?
    }

    // MARK: - fun cards (12 of them)

    private func mostExpensiveTurnCard(root: URL) -> ClaudePatternCard? {
        let projectsDir = root.appendingPathComponent("projects")
        guard let enumerator = FileManager.default.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])
        else { return nil }

        var files: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            files.append((url, mtime))
        }
        let recent = files.sorted { $0.1 > $1.1 }.prefix(20).map { $0.0 }

        var bestCost: Double = 0
        var bestModel = ""
        var bestProject = ""
        var bestDate: Date?
        var bestInput = 0
        var bestOutput = 0

        for url in recent {
            guard let content = Self.boundedText(from: url, maxBytes: 1_500_000) else { continue }
            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      object["type"] as? String == "assistant",
                      let message = object["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any]
                else { continue }
                let model = (message["model"] as? String) ?? "claude"
                let input = Self.intValue(usage["input_tokens"])
                let output = Self.intValue(usage["output_tokens"])
                let cacheRead = Self.intValue(usage["cache_read_input_tokens"])
                let cacheCreate = Self.intValue(usage["cache_creation_input_tokens"])
                let cost = ClaudePricing.synthesizeUSD(model: model, input: input, output: output, cacheRead: cacheRead, cacheCreate: cacheCreate)
                if cost > bestCost {
                    bestCost = cost
                    bestModel = model
                    bestInput = input
                    bestOutput = output
                    bestProject = (object["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? "—"
                    bestDate = (object["timestamp"] as? String).flatMap(ClaudeDate.parse)
                }
            }
        }
        guard bestCost > 0.10 else { return nil }
        let dateLabel: String
        if let bestDate {
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            dateLabel = f.string(from: bestDate)
        } else { dateLabel = "—" }
        let cost = String(format: "$%.2f", bestCost)
        return ClaudePatternCard(
            kind: .mostExpensiveTurn,
            title: "Priciest turn ever: \(cost)",
            body: "On \(dateLabel) in \(bestProject), one turn cost \(cost) synthetic — \(Self.compact(bestInput)) in / \(Self.compact(bestOutput)) out via \(Self.shortModelName(bestModel)).",
            footnote: "biggest spike across recent sessions",
            highlightValue: cost,
            progressPercent: nil,
            tone: bestCost > 5 ? .caution : .neutral,
            sortPriority: 32)
    }

    private func overageReceiptsCard(oauth: ClaudeOAuthUsage?) -> ClaudePatternCard? {
        guard let extra = oauth?.extraUsage,
              extra.isEnabled,
              extra.usedCredits >= 50
        else { return nil }
        let used = extra.usedCredits
        let lattes = Int(used / 6.50)
        let games = Int(used / 70.0)
        let lunches = Int(used / 18.0)
        let pizzas = Int(used / 22.0)
        let body = "$\(Self.formatMoney(used)) overage = \(lattes.formatted()) lattes · \(games) AAA games · \(lunches.formatted()) takeaway lunches · \(pizzas.formatted()) large pizzas. We'd never tell, but Claude is one expensive friend."
        return ClaudePatternCard(
            kind: .overageReceipts,
            title: "Translated to dinners",
            body: body,
            footnote: "current month overage spend",
            highlightValue: "$\(Self.formatMoney(used))",
            progressPercent: nil,
            tone: .neutral,
            sortPriority: 28)
    }

    private func pastedNovelCard() -> ClaudePatternCard? {
        let pasteDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/paste-cache")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: pasteDir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles])
        else { return nil }
        var totalBytes: Int64 = 0
        var biggest: Int64 = 0
        for url in files {
            guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) else { continue }
            totalBytes += size
            biggest = max(biggest, size)
        }
        guard totalBytes > 50_000 else { return nil }
        let kb = Double(totalBytes) / 1024
        let mb = kb / 1024
        let comparison: String
        // Average novel ~800KB (200k words × 4 chars)
        if mb >= 5 { comparison = "≈ 6 paperback novels" }
        else if mb >= 1.5 { comparison = "≈ 2 short novels (Of Mice and Men × 2)" }
        else if mb >= 0.6 { comparison = "≈ a thin paperback (Animal Farm)" }
        else { comparison = "≈ a long blog post" }
        let label = mb >= 1
            ? String(format: "%.1f MB", mb)
            : String(format: "%.0f KB", kb)
        return ClaudePatternCard(
            kind: .pastedNovel,
            title: "You've pasted \(label)",
            body: "Across \(files.count) cached pastes, you've handed Claude \(label) of content. \(comparison). The biggest single paste was \(Self.compact(Int(biggest / 1024)))KB.",
            footnote: "deduplicated paste cache",
            highlightValue: label,
            progressPercent: nil,
            tone: .positive,
            sortPriority: 22)
    }

    private func slashCommandCounts() -> [String: Int] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/history.jsonl")
        guard let signature = Self.fileSignature(for: url) else { return [:] }
        if let cached = self.slashCommandCountsCache,
           cached.signature == signature
        {
            return cached.counts
        }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var counts: [String: Int] = [:]
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let display = object["display"] as? String,
                  display.hasPrefix("/")
            else { continue }
            let first = display.split(separator: " ", maxSplits: 1).first.map(String.init) ?? display
            counts[first, default: 0] += 1
        }
        self.slashCommandCountsCache = (signature: signature, counts: counts)
        return counts
    }

    private func contextDeathsCard() -> ClaudePatternCard? {
        let counts = self.slashCommandCounts()
        let compactCount = counts["/compact"] ?? 0
        guard compactCount >= 2 else { return nil }
        let body: String
        if compactCount >= 20 {
            body = "You manually compacted \(compactCount) times. That's a lot of small surrenders."
        } else if compactCount >= 5 {
            body = "You manually compacted \(compactCount) times — each one a quiet 'this conversation got too long.'"
        } else {
            body = "You manually compacted \(compactCount) times. The context window has bested you a few."
        }
        return ClaudePatternCard(
            kind: .contextDeaths,
            title: "Context deaths: \(compactCount)",
            body: body,
            footnote: "/compact lifetime",
            highlightValue: "\(compactCount)",
            progressPercent: nil,
            tone: compactCount >= 20 ? .caution : .neutral,
            sortPriority: 24)
    }

    private func regretIndexCard() -> ClaudePatternCard? {
        let counts = self.slashCommandCounts()
        let rewindCount = counts["/rewind"] ?? 0
        guard rewindCount >= 5 else { return nil }
        let body: String
        if rewindCount >= 100 {
            body = "You've hit /rewind \(rewindCount) times — a quiet ledger of choices you took back. Statistically, that's healthy reflection."
        } else if rewindCount >= 25 {
            body = "/rewind hit \(rewindCount) times. You're not afraid to undo, which most users never bother with."
        } else {
            body = "You've used /rewind \(rewindCount) times. A small but specific habit."
        }
        return ClaudePatternCard(
            kind: .regretIndex,
            title: "Regret index: \(rewindCount)",
            body: body,
            footnote: "/rewind lifetime",
            highlightValue: "\(rewindCount)",
            progressPercent: nil,
            tone: .neutral,
            sortPriority: 26)
    }

    private func firstPromptEverCard() -> ClaudePatternCard? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/history.jsonl")
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        // Walk lines until we find a non-slash, non-empty display.
        var found: (text: String, timestamp: Double, project: String)?
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let display = object["display"] as? String
            else { continue }
            let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("/") else { continue }
            let ts = (object["timestamp"] as? Double) ?? 0
            let project = (object["project"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? "—"
            found = (trimmed, ts, project)
            break
        }
        guard let first = found else { return nil }
        let text = first.text.count > 100 ? String(first.text.prefix(99)) + "…" : first.text
        let dateLabel: String
        if first.timestamp > 0 {
            let date = Date(timeIntervalSince1970: first.timestamp / 1000)
            let f = DateFormatter()
            f.dateFormat = "MMM d, yyyy"
            dateLabel = f.string(from: date)
        } else {
            dateLabel = "—"
        }
        return ClaudePatternCard(
            kind: .firstPromptEver,
            title: "Your first ever prompt",
            body: "\"\(text)\" — sent \(dateLabel) in \(first.project). The thing that started everything.",
            footnote: "the original ask",
            highlightValue: nil,
            progressPercent: nil,
            tone: .positive,
            sortPriority: 36)
    }

    private func burnstarSignCard(
        aggregate: ClaudeAggregateStats,
        sessionMetas: [ParsedSessionMeta],
        liveSession: ClaudeSessionStats?) -> ClaudePatternCard?
    {
        // Derive a 1-2 word persona from the dominant signal.
        let totalTools = aggregate.toolLeaderboard.totalToolCalls
        let bashCount = aggregate.toolLeaderboard.bashCommands.first?.count ?? 0
        let mcpCount = aggregate.toolLeaderboard.mcpServers.reduce(0) { $0 + $1.count }
        let peakStart = aggregate.peakHourBand?.start ?? -1
        let denominator = max(1, aggregate.lifetimeInputTokens + aggregate.lifetimeCacheReadTokens + aggregate.lifetimeCacheCreationTokens)
        let cacheRatio = Double(aggregate.lifetimeCacheReadTokens) / Double(denominator)

        // Languages count across recent metas
        var langs: Set<String> = []
        for meta in sessionMetas.prefix(20) {
            for (k, _) in meta.languages { langs.insert(k) }
        }

        let sign: (name: String, descriptor: String)
        if peakStart >= 22 || peakStart <= 4 {
            sign = ("The Insomniac", "your peak coding band starts after dark")
        } else if peakStart >= 5, peakStart <= 7 {
            sign = ("The Dawn Patrol", "you start before most people wake up")
        } else if cacheRatio >= 0.95 {
            sign = ("The Magpie", "you collect cache like shiny things")
        } else if mcpCount > totalTools / 4 {
            sign = ("The MCP Conductor", "your tools live in other servers")
        } else if langs.count >= 5 {
            sign = ("The Polyglot", "\(langs.count) programming languages in recent rotation")
        } else if bashCount > totalTools / 3 {
            sign = ("The Shell Wizard", "Bash is your love language")
        } else if (liveSession?.toolHistogram.first?.name) == "Edit" {
            sign = ("The Refactorer", "you'd rather rewrite than start over")
        } else if aggregate.longestSessionMinutes > 360 {
            sign = ("The Marathoner", "your longest session was \(aggregate.longestSessionMinutes / 60) hours")
        } else {
            sign = ("The Steady Hand", "no extreme — just consistent")
        }

        return ClaudePatternCard(
            kind: .burnstarSign,
            title: "Your burnstar: \(sign.name)",
            body: "Based on your peak hours, tool mix, language palette and cache ratio: \(sign.descriptor).",
            footnote: "frivolous · derived from your data",
            highlightValue: nil,
            progressPercent: nil,
            tone: .positive,
            sortPriority: 30)
    }

    private func codenameCollectorCard() -> ClaudePatternCard? {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/plans")
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        let codenames = files
            .filter { $0.pathExtension == "md" }
            .map { $0.deletingPathExtension().lastPathComponent }
        guard !codenames.isEmpty else { return nil }
        let sample = codenames.prefix(4).joined(separator: " · ")
        let body: String
        if codenames.count == 1 {
            body = "Anthropic auto-generated this codename for your saved plan: \(codenames[0]). Charming."
        } else {
            body = "Anthropic auto-generated these for your saved plans: \(sample)\(codenames.count > 4 ? " · …" : ""). Each plan is named after a 2-word adjective + animal."
        }
        return ClaudePatternCard(
            kind: .codenameCollector,
            title: codenames.count == 1 ? "Your plan: \(codenames[0])" : "Codename collector: \(codenames.count)",
            body: body,
            footnote: "plan-mode codenames",
            highlightValue: codenames.count > 1 ? "\(codenames.count)" : nil,
            progressPercent: nil,
            tone: .positive,
            sortPriority: 18)
    }

    private func weekendWarriorCard(sessionMetas: [ParsedSessionMeta]) -> ClaudePatternCard? {
        guard sessionMetas.count >= 5 else { return nil }
        var weekend = 0
        var weekday = 0
        let calendar = Calendar.current
        for meta in sessionMetas {
            guard let start = meta.startTime else { continue }
            let weekdayNumber = calendar.component(.weekday, from: start) // 1=Sun, 7=Sat
            if weekdayNumber == 1 || weekdayNumber == 7 { weekend += 1 } else { weekday += 1 }
        }
        let total = weekend + weekday
        guard total >= 5 else { return nil }
        let pct = Int(Double(weekend) / Double(total) * 100)
        let body: String
        let toneVal: ClaudePatternTone
        if pct >= 30 {
            body = "\(pct)% of your sessions happen on Saturday or Sunday. You don't really clock out."
            toneVal = .caution
        } else if pct >= 15 {
            body = "\(pct)% weekend coding. Healthy balance — Claude shows up when you do."
            toneVal = .neutral
        } else if pct >= 5 {
            body = "\(pct)% of your sessions are on weekends. You mostly keep them sacred."
            toneVal = .positive
        } else {
            body = "\(pct)% weekend coding. You guard your weekends well."
            toneVal = .positive
        }
        return ClaudePatternCard(
            kind: .weekendWarrior,
            title: "Weekend coding: \(pct)%",
            body: body,
            footnote: "Saturday + Sunday share of recent sessions",
            highlightValue: "\(pct)%",
            progressPercent: Double(pct),
            tone: toneVal,
            sortPriority: 24)
    }

    private func achievementsCard(
        aggregate: ClaudeAggregateStats,
        sessionMetas: [ParsedSessionMeta],
        liveSession: ClaudeSessionStats?) -> ClaudePatternCard?
    {
        var unlocked: [String] = []
        // Insomniac — significant late-night activity
        if let band = aggregate.peakHourBand, (band.start >= 22 || band.start <= 4) {
            unlocked.append("Insomnia coder")
        }
        // Marathoner — longest session > 4h
        if aggregate.longestSessionMinutes > 240 {
            unlocked.append("Marathoner")
        }
        // Polyglot — 5+ distinct languages across recent sessions
        var langs: Set<String> = []
        for meta in sessionMetas.prefix(30) {
            for (k, _) in meta.languages { langs.insert(k) }
        }
        if langs.count >= 5 {
            unlocked.append("Polyglot (\(langs.count) langs)")
        }
        // Plugin curator — 5+ plugins installed
        let pluginsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/plugins/installed_plugins.json")
        if let data = try? Data(contentsOf: pluginsURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let plugins = json["plugins"] as? [String: Any],
           plugins.count >= 5
        {
            unlocked.append("Plugin curator (\(plugins.count))")
        }
        // Skill master — 10+ user skills
        let skillsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills")
        if let skills = try? FileManager.default.contentsOfDirectory(atPath: skillsURL.path),
           skills.count >= 10
        {
            unlocked.append("Skill chef (\(skills.count))")
        }
        // Cache master — lifetime cache > 90%
        let denom = max(1, aggregate.lifetimeInputTokens + aggregate.lifetimeCacheReadTokens + aggregate.lifetimeCacheCreationTokens)
        let cachePct = Double(aggregate.lifetimeCacheReadTokens) / Double(denom)
        if cachePct >= 0.90 {
            unlocked.append("Cache master")
        }
        // Streak runner — 7+ day streak
        if aggregate.streakDays >= 7 {
            unlocked.append("Streak runner (\(aggregate.streakDays)d)")
        }
        // Multimodal — used Edit, Bash, WebFetch and Skill recently
        let toolNames = Set(aggregate.toolLeaderboard.bashCommands.map { _ in "Bash" })
            .union(["Bash"])
        var seen: Set<String> = []
        if let live = liveSession {
            for tool in live.toolHistogram { seen.insert(tool.name) }
        }
        let multimodalSet: Set<String> = ["Edit", "Bash", "WebFetch", "Skill"]
        if multimodalSet.isSubset(of: seen) || (toolNames.contains("Bash") && seen.contains("Edit") && (seen.contains("WebFetch") || seen.contains("Skill"))) {
            unlocked.append("Multimodal")
        }

        guard unlocked.count >= 2 else { return nil }
        let badge = unlocked.first ?? "—"
        let listing = unlocked.joined(separator: " · ")
        return ClaudePatternCard(
            kind: .achievements,
            title: "Achievements: \(unlocked.count) unlocked",
            body: "\(listing). Top badge: \(badge).",
            footnote: "derived from your usage patterns",
            highlightValue: "\(unlocked.count)",
            progressPercent: nil,
            tone: .positive,
            sortPriority: 44)
    }

    private func anniversaryCard(aggregate: ClaudeAggregateStats) -> ClaudePatternCard? {
        let day = aggregate.daysSinceFirstSession ?? 0
        let sessions = aggregate.totalSessions
        let messages = aggregate.totalMessages
        let dayMilestones: Set<Int> = [10, 30, 60, 90, 100, 120, 180, 200, 300, 365]
        let sessionMilestones: Set<Int> = [50, 100, 200, 250, 500, 1000]
        let messageMilestones: Set<Int> = [1000, 5000, 10000, 25000, 50000, 100000, 250000]
        let streakMilestones: Set<Int> = [7, 14, 30, 60, 100]

        var celebration: String?
        if dayMilestones.contains(day) {
            celebration = "Day \(day) of using Claude Code."
        } else if let _ = sessionMilestones.first(where: { $0 == sessions }) {
            celebration = "\(sessions)th lifetime session."
        } else if let _ = messageMilestones.first(where: { $0 == messages }) {
            celebration = "\(messages.formatted()) lifetime messages crossed."
        } else if streakMilestones.contains(aggregate.streakDays) {
            celebration = "\(aggregate.streakDays)-day streak — that's a habit."
        }
        guard let line = celebration else { return nil }
        return ClaudePatternCard(
            kind: .anniversary,
            title: "Milestone today",
            body: line + " Worth a deep breath.",
            footnote: "round-number celebration",
            highlightValue: "🎉",
            progressPercent: nil,
            tone: .positive,
            sortPriority: 92)
    }

    private func skipListCard(aggregate: ClaudeAggregateStats) -> ClaudePatternCard? {
        // Count skipped days in last 30 (days with 0 messages)
        let calendar = Calendar.current
        let last30Start = calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: Date())) ?? Date()
        let activeDates = Set(
            aggregate.dailyMessageCounts
                .filter { $0.messageCount > 0 && $0.date >= last30Start }
                .map { calendar.startOfDay(for: $0.date) })
        var skips = 0
        for offset in 0..<30 {
            if let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: Date())),
               !activeDates.contains(day)
            {
                skips += 1
            }
        }
        guard skips >= 2 else { return nil }
        let body: String
        if skips >= 15 {
            body = "You took \(skips) days off in the last 30. Either you've been busy elsewhere or you're a healthier coder than most."
        } else if skips >= 5 {
            body = "You skipped \(skips) days in the last 30. Probably the right ratio."
        } else {
            body = "Only \(skips) rest days in the last 30. Don't forget to close the laptop."
        }
        return ClaudePatternCard(
            kind: .skipList,
            title: "Rest days: \(skips) of 30",
            body: body,
            footnote: "days with no Claude activity · last 30",
            highlightValue: "\(skips)",
            progressPercent: Double(skips) / 30 * 100,
            tone: skips < 3 ? .caution : .positive,
            sortPriority: 22)
    }

    // MARK: - tool leaderboards (scan recent JSONLs)

    private func scanRecentJsonlsForTools(root: URL, limit: Int) -> ClaudeToolLeaderboard {
        let projectsDir = root.appendingPathComponent("projects")
        guard let enumerator = FileManager.default.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])
        else { return .empty }

        var files: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            files.append((url, mtime))
        }
        let recent = files.sorted { $0.1 > $1.1 }.prefix(limit).map { $0.0 }

        var bash: [String: Int] = [:]
        var mcp: [String: Int] = [:]
        var skill: [String: Int] = [:]
        var web: [String: Int] = [:]
        var totalTools = 0

        for url in recent {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      object["type"] as? String == "assistant",
                      let message = object["message"] as? [String: Any],
                      let contentArr = message["content"] as? [[String: Any]]
                else { continue }
                for item in contentArr where (item["type"] as? String) == "tool_use" {
                    guard let name = item["name"] as? String else { continue }
                    totalTools += 1
                    let input = item["input"] as? [String: Any]
                    if name == "Bash", let cmd = input?["command"] as? String {
                        let first = cmd.split(separator: " ").first.map(String.init) ?? cmd
                        bash[first, default: 0] += 1
                    } else if name == "Skill", let s = input?["skill"] as? String {
                        skill[s, default: 0] += 1
                    } else if name == "WebFetch", let u = input?["url"] as? String,
                              let host = URL(string: u)?.host
                    {
                        web[host, default: 0] += 1
                    } else if name.hasPrefix("mcp__") {
                        // mcp__<server>__<tool>
                        let parts = name.dropFirst("mcp__".count).split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false)
                        let server = parts.first.map(String.init) ?? "unknown"
                        mcp[server, default: 0] += 1
                    }
                }
            }
        }

        return ClaudeToolLeaderboard(
            bashCommands: Self.topCounts(bash, limit: 8),
            mcpServers: Self.topCounts(mcp, limit: 5),
            skills: Self.topCounts(skill, limit: 6),
            webFetchHosts: Self.topCounts(web, limit: 6),
            totalToolCalls: totalTools,
            scannedFileCount: recent.count)
    }

    private static func topCounts(_ map: [String: Int], limit: Int) -> [ClaudeToolCount] {
        map.map { ClaudeToolCount(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - beta gates

    private func readBetaGates(root: URL) -> [ClaudeBetaGate] {
        // Pull the most recent telemetry envelope and parse its `betas` field.
        let dir = root.appendingPathComponent("telemetry")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])
        else { return [] }
        let mostRecent = files
            .filter { $0.pathExtension == "json" }
            .map { url -> (URL, Date) in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return (url, date)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .map { $0.0 }

        for url in mostRecent {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let payload = object["event_data"] as? [String: Any],
                      let betas = payload["betas"] as? String,
                      !betas.isEmpty
                else { continue }
                return Self.parseBetaGates(betas)
            }
        }
        return []
    }

    private static func parseBetaGates(_ raw: String) -> [ClaudeBetaGate] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let altFormatter = DateFormatter()
        altFormatter.dateFormat = "yyyyMMdd"
        altFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        return raw.split(separator: ",").compactMap { token -> ClaudeBetaGate? in
            let name = token.trimmingCharacters(in: .whitespaces)
            // Try YYYY-MM-DD suffix first (e.g., oauth-2025-04-20)
            let dateRegex = try? NSRegularExpression(pattern: #"(\d{4})-(\d{2})-(\d{2})$"#)
            let plainRegex = try? NSRegularExpression(pattern: #"-?(\d{8})$"#)
            let range = NSRange(name.startIndex..., in: name)
            var date: Date?
            if let m = dateRegex?.firstMatch(in: name, range: range), m.numberOfRanges >= 4,
               let r = Range(m.range, in: name)
            {
                let dateStr = String(name[r])
                date = formatter.date(from: dateStr)
            } else if let m = plainRegex?.firstMatch(in: name, range: range), m.numberOfRanges >= 2,
                      let r = Range(m.range(at: 1), in: name)
            {
                date = altFormatter.date(from: String(name[r]))
            }

            // Strip the trailing date for the human label
            var humanLabel = name
            if let r = humanLabel.range(of: #"-?\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) {
                humanLabel.removeSubrange(r)
            } else if let r = humanLabel.range(of: #"-?\d{8}$"#, options: .regularExpression) {
                humanLabel.removeSubrange(r)
            }
            humanLabel = humanLabel
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .trimmingCharacters(in: .whitespaces)
            return ClaudeBetaGate(name: name, date: date, humanLabel: humanLabel)
        }
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    // MARK: - today breakdown

    private func buildTodayBreakdown(
        sessionMetas: [ParsedSessionMeta],
        liveSession: ClaudeSessionStats?,
        now: Date) -> ClaudeTodayBreakdown
    {
        let calendar = Calendar.current
        var hours = Array(repeating: 0, count: 24)
        var languages: [String: Int] = [:]
        var linesAdded = 0
        var linesRemoved = 0
        var filesModified = 0
        var commits = 0

        for meta in sessionMetas {
            guard let start = meta.startTime, calendar.isDate(start, inSameDayAs: now) else { continue }
            for h in meta.messageHours where (0..<24).contains(h) {
                hours[h] += 1
            }
            for (lang, count) in meta.languages {
                languages[lang, default: 0] += count
            }
            linesAdded += meta.linesAdded
            linesRemoved += meta.linesRemoved
            filesModified += meta.filesModified
            commits += meta.gitCommits
        }

        // Live session: count its assistant messages by hour-of-day from JSONL timestamps.
        // We don't have per-message timestamps in ClaudeSessionStats, so approximate using
        // the sessionStartedAt + uniform spread up to lastActivityAt at granularity of 1 turn/hour bucket.
        // Better: compute the hour for sessionStartedAt and lastActivityAt; if they differ, spread the
        // assistant messages linearly across the spanned hours.
        if let live = liveSession,
           let start = live.sessionStartedAt,
           let last = live.lastActivityAt,
           calendar.isDate(start, inSameDayAs: now) || calendar.isDate(last, inSameDayAs: now)
        {
            // Clamp to today's portion only — sessions that crossed midnight
            // (e.g. start=yesterday 22:00, end=today 02:00) would otherwise
            // produce an invalid Int range.
            let startHour = calendar.isDate(start, inSameDayAs: now)
                ? calendar.component(.hour, from: start) : 0
            let endHour = calendar.isDate(last, inSameDayAs: now)
                ? calendar.component(.hour, from: last) : 23
            let safeStart = min(startHour, endHour)
            let safeEnd = max(startHour, endHour)
            let span = max(1, safeEnd - safeStart + 1)
            let perHour = max(1, live.assistantMessageCount / span)
            for h in safeStart...safeEnd where (0..<24).contains(h) {
                hours[h] += perHour
            }
        }

        let langs = languages
            .map { ClaudeToolCount(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { $0 }

        return ClaudeTodayBreakdown(
            hourBuckets: hours,
            languages: langs,
            linesAdded: linesAdded,
            linesRemoved: linesRemoved,
            filesModified: filesModified,
            gitCommits: commits)
    }

    // MARK: - misc

    private func planName(
        from oauth: ClaudeOAuthUsage?,
        aggregate: ClaudeAggregateStats?,
        liveSession: ClaudeSessionStats?) -> String?
    {
        if let tier = oauth?.rateLimitTier, !tier.isEmpty {
            return Self.prettyPlanName(forTier: tier)
        }
        // Anthropic doesn't always return `rate_limit_tier`. Fall back to the
        // monthly overage cap (`extra_usage.monthly_limit`) which differs sharply
        // between tiers: Pro ≈ $200, Max 5× ≈ $1–2k, Max 20× = $10k+.
        if let extra = oauth?.extraUsage, extra.monthlyLimit > 0 {
            return Self.prettyPlanName(forMonthlyLimit: extra.monthlyLimit)
        }
        // Keychain credential carries `subscriptionType` (e.g. "max",
        // "max_20x", "pro"). It's the most reliable local plan signal
        // Claude Code stores — works even when both the API tier and
        // overage cap are empty. `prettyPlanName(forTier:)` already
        // handles "max"/"pro"/"5x"/"20x" patterns.
        if let sub = oauth?.subscriptionType, !sub.isEmpty {
            return Self.prettyPlanName(forTier: sub)
        }
        if (aggregate?.totalSessions ?? 0) > 50 { return "Pro/Max" }
        return nil
    }

    static func prettyPlanName(forMonthlyLimit limit: Double) -> String {
        switch limit {
        case 8_000...:
            return "Max 20×"
        case 800..<8_000:
            return "Max 5×"
        case 50..<800:
            return "Pro"
        default:
            return "Free/Pro"
        }
    }

    /// Maps the raw `rate_limit_tier` string (e.g. `claude_max_20x_2025`) to a
    /// short human label (`Max 20×`). Falls back to a Title-Cased version of
    /// whatever Anthropic returned.
    static func prettyPlanName(forTier tier: String) -> String {
        let raw = tier.lowercased()

        // Look for explicit multipliers: 20x, 5x, 1x.
        let multiplierPattern = #"(\d{1,3})\s*x"#
        let multiplier: String? = {
            guard let regex = try? NSRegularExpression(pattern: multiplierPattern) else { return nil }
            let range = NSRange(raw.startIndex..., in: raw)
            guard let match = regex.firstMatch(in: raw, range: range), match.numberOfRanges >= 2,
                  let r = Range(match.range(at: 1), in: raw)
            else { return nil }
            return String(raw[r])
        }()

        if raw.contains("max") {
            if let m = multiplier { return "Max \(m)×" }
            return "Max"
        }
        if raw.contains("ultra") {
            if let m = multiplier { return "Ultra \(m)×" }
            return "Ultra"
        }
        if raw.contains("enterprise") { return "Enterprise" }
        if raw.contains("team") { return "Team" }
        if raw.contains("pro") {
            if let m = multiplier { return "Pro \(m)×" }
            return "Pro"
        }
        // Unknown tier — pretty-cased fallback so we still surface something.
        return tier
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func accountLabel(root: URL, oauth: ClaudeOAuthUsage?) -> String? {
        if oauth != nil { return "OAuth · live" }
        let path = root.appendingPathComponent(".credentials.json")
        if FileManager.default.fileExists(atPath: path.path) {
            return "OAuth account"
        }
        return "Local account"
    }

    private func modelMixFromLive(_ live: ClaudeSessionStats?) -> [ModelUsageShare] {
        guard let model = live?.modelName else { return [] }
        return [ModelUsageShare(modelName: Self.shortModelName(model), percent: 100)]
    }

    private static func shortModelName(_ model: String) -> String {
        let lowered = model.lowercased()
        if lowered.contains("opus-4-7") { return "opus 4.7" }
        if lowered.contains("opus") { return "opus" }
        if lowered.contains("sonnet") { return "sonnet" }
        if lowered.contains("haiku") { return "haiku" }
        return model
    }

    fileprivate static func truncate(_ value: String, to length: Int) -> String {
        let cleaned = value.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count <= length { return cleaned }
        return String(cleaned.prefix(length - 1)) + "…"
    }

    fileprivate static func intValue(_ any: Any?) -> Int {
        if let value = any as? Int { return value }
        if let value = any as? Double { return Int(value) }
        if let value = any as? String { return Int(value) ?? 0 }
        return 0
    }

    fileprivate static func extractText(from content: Any) -> String? {
        if let str = content as? String { return str }
        if let array = content as? [[String: Any]] {
            for entry in array {
                if let type = entry["type"] as? String, type == "text",
                   let text = entry["text"] as? String { return text }
            }
        }
        return nil
    }

    fileprivate static func formatMoney(_ value: Double) -> String {
        if value >= 100 { return String(format: "%.0f", value) }
        if value >= 10 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }

    fileprivate static func compact(_ value: Int) -> String {
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

    private static func formatHour(_ hour: Int) -> String {
        let normalized = ((hour % 24) + 24) % 24
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        let date = Calendar.current.date(bySettingHour: normalized, minute: 0, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date).lowercased()
    }

    private static func hourBandContains(start: Int, end: Int, hour: Int) -> Bool {
        let s = ((start % 24) + 24) % 24
        let e = ((end % 24) + 24) % 24
        if s <= e { return hour >= s && hour < e }
        return hour >= s || hour < e
    }
}

// MARK: - Pricing (synthetic API equivalents)

public enum ClaudePricing {
    /// Per-million-token rates approximating public Anthropic API pricing.
    /// Prompt cache reads are ~1/10 of input; cache writes vary by tier.
    /// Numbers are intentionally rounded for "what would I pay on API?" math.
    public struct Rates {
        public let input: Double
        public let output: Double
        public let cacheRead: Double
        public let cacheCreate: Double
    }

    public static func rates(for model: String) -> Rates {
        let m = model.lowercased()
        if m.contains("opus") {
            // Current Opus family pricing. Opus 4.5+ uses the lower
            // $5/$25 API price; Opus 4 and 4.1 remain at legacy $15/$75.
            if m.contains("4-5") || m.contains("4.5")
                || m.contains("4-6") || m.contains("4.6")
                || m.contains("4-7") || m.contains("4.7")
            {
                return Rates(input: 5.0, output: 25.0, cacheRead: 0.50, cacheCreate: 6.25)
            }
            if m.trimmingCharacters(in: .whitespacesAndNewlines) == "opus" {
                return Rates(input: 5.0, output: 25.0, cacheRead: 0.50, cacheCreate: 6.25)
            }
            return Rates(input: 15.0, output: 75.0, cacheRead: 1.50, cacheCreate: 18.75)
        }
        if m.contains("haiku-4-5") || m.contains("haiku 4.5") {
            return Rates(input: 1.0, output: 5.0, cacheRead: 0.10, cacheCreate: 1.25)
        }
        if m.contains("haiku") {
            return Rates(input: 0.80, output: 4.0, cacheRead: 0.08, cacheCreate: 1.0)
        }
        // sonnet + unknown default to sonnet pricing
        return Rates(input: 3.0, output: 15.0, cacheRead: 0.30, cacheCreate: 3.75)
    }

    public static func synthesizeUSD(model: String, input: Int, output: Int, cacheRead: Int, cacheCreate: Int) -> Double {
        let r = rates(for: model)
        let mtok = 1_000_000.0
        return Double(input) / mtok * r.input
            + Double(output) / mtok * r.output
            + Double(cacheRead) / mtok * r.cacheRead
            + Double(cacheCreate) / mtok * r.cacheCreate
    }
}

// MARK: - Raw decoders

private struct StatsCacheRaw: Decodable {
    let version: Int?
    let lastComputedDate: String?
    let dailyActivity: [DailyActivityRaw]?
    let dailyModelTokens: [ModelTokensRaw]?
    let modelUsage: [String: ModelUsageRaw]?
    let totalSessions: Int?
    let totalMessages: Int?
    let longestSession: LongestSessionRaw?
    let firstSessionDate: String?
    let hourCounts: [String: Int]?
    let totalSpeculationTimeSavedMs: Int?
}

private struct DailyActivityRaw: Decodable {
    let date: String
    let messageCount: Int?
    let sessionCount: Int?
    let toolCallCount: Int?
}

private struct ModelTokensRaw: Decodable {
    let date: String
    let tokensByModel: [String: Int]?
}

private struct ModelUsageRaw: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadInputTokens: Int?
    let cacheCreationInputTokens: Int?
    let webSearchRequests: Int?
    let costUSD: Double?
    let contextWindow: Int?
    let maxOutputTokens: Int?
}

private struct LongestSessionRaw: Decodable {
    let sessionId: String?
    let duration: Double?
    let messageCount: Int?
    let timestamp: String?
}

private struct SessionMetaRaw: Decodable {
    let sessionId: String?
    let projectPath: String?
    let startTime: String?
    let durationMinutes: Int?
    let userMessageCount: Int?
    let assistantMessageCount: Int?
    let toolCounts: [String: Int]?
    let languages: [String: Int]?
    let gitCommits: Int?
    let gitPushes: Int?
    let inputTokens: Int?
    let outputTokens: Int?
    let firstPrompt: String?
    let userInterruptions: Int?
    let toolErrors: Int?
    let usesTaskAgent: Bool?
    let usesMcp: Bool?
    let usesWebSearch: Bool?
    let usesWebFetch: Bool?
    let linesAdded: Int?
    let linesRemoved: Int?
    let filesModified: Int?
    let messageHours: [Int]?
    let userMessageTimestamps: [String]?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case projectPath = "project_path"
        case startTime = "start_time"
        case durationMinutes = "duration_minutes"
        case userMessageCount = "user_message_count"
        case assistantMessageCount = "assistant_message_count"
        case toolCounts = "tool_counts"
        case languages
        case gitCommits = "git_commits"
        case gitPushes = "git_pushes"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case firstPrompt = "first_prompt"
        case userInterruptions = "user_interruptions"
        case toolErrors = "tool_errors"
        case usesTaskAgent = "uses_task_agent"
        case usesMcp = "uses_mcp"
        case usesWebSearch = "uses_web_search"
        case usesWebFetch = "uses_web_fetch"
        case linesAdded = "lines_added"
        case linesRemoved = "lines_removed"
        case filesModified = "files_modified"
        case messageHours = "message_hours"
        case userMessageTimestamps = "user_message_timestamps"
    }
}

private struct FileSignature: Equatable {
    let fileSize: Int
    let modifiedAt: Date?
}

struct ParsedSessionMeta {
    let sessionId: String
    let projectPath: String?
    let projectName: String
    let startTime: Date?
    let durationMinutes: Int
    let userMessageCount: Int
    let assistantMessageCount: Int
    let toolCounts: [String: Int]
    let languages: [String: Int]
    let gitCommits: Int
    let gitPushes: Int
    let inputTokens: Int
    let outputTokens: Int
    let firstPrompt: String?
    let userInterruptions: Int
    let toolErrors: Int
    let linesAdded: Int
    let linesRemoved: Int
    let filesModified: Int
    let messageHours: [Int]

    fileprivate init?(raw: SessionMetaRaw) {
        guard let id = raw.sessionId else { return nil }
        self.sessionId = id
        self.projectPath = raw.projectPath
        self.projectName = raw.projectPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Claude session"
        self.startTime = ClaudeDate.parse(raw.startTime)
        self.durationMinutes = raw.durationMinutes ?? 0
        self.userMessageCount = raw.userMessageCount ?? 0
        self.assistantMessageCount = raw.assistantMessageCount ?? 0
        self.toolCounts = raw.toolCounts ?? [:]
        self.languages = raw.languages ?? [:]
        self.gitCommits = raw.gitCommits ?? 0
        self.gitPushes = raw.gitPushes ?? 0
        self.inputTokens = raw.inputTokens ?? 0
        self.outputTokens = raw.outputTokens ?? 0
        self.firstPrompt = raw.firstPrompt
        self.userInterruptions = raw.userInterruptions ?? 0
        self.toolErrors = raw.toolErrors ?? 0
        self.linesAdded = raw.linesAdded ?? 0
        self.linesRemoved = raw.linesRemoved ?? 0
        self.filesModified = raw.filesModified ?? 0
        self.messageHours = raw.messageHours ?? []
    }

    static func projectName(fromEncodedFolder folder: String) -> String {
        // Folder names encode the cwd as "-<dash-separated-path>", e.g.
        // "/home/user/dev/foo" becomes "-home-user-dev-foo". We grab the last
        // segment after the final dash to get a project label.
        if let idx = folder.lastIndex(of: "-") {
            let suffix = folder[folder.index(after: idx)...]
            if !suffix.isEmpty { return String(suffix) }
        }
        return folder
    }
}

private struct FacetsRaw: Decodable {
    let sessionId: String?
    let outcome: String?
    let claudeHelpfulness: String?
    let sessionType: String?
    let underlyingGoal: String?
    let briefSummary: String?
    let frictionDetail: String?
    let primarySuccess: String?
    let frictionCounts: [String: Int]?
    let userSatisfactionCounts: [String: Int]?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case outcome
        case claudeHelpfulness = "claude_helpfulness"
        case sessionType = "session_type"
        case underlyingGoal = "underlying_goal"
        case briefSummary = "brief_summary"
        case frictionDetail = "friction_detail"
        case primarySuccess = "primary_success"
        case frictionCounts = "friction_counts"
        case userSatisfactionCounts = "user_satisfaction_counts"
    }
}

enum ClaudeDate {
    static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let d = isoFractional.date(from: value) { return d }
        if let d = iso.date(from: value) { return d }
        return nil
    }

    static func parseDay(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return dayFormatter.date(from: value)
    }
}
