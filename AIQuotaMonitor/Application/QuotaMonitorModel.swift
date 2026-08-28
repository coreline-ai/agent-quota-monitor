import SwiftUI

@MainActor
final class QuotaMonitorModel: ObservableObject {
    @Published private(set) var snapshots: [ProviderSnapshot]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var history: [ProviderSnapshot] = []
    @Published private(set) var historyRevision = 0

    private var coordinator: RefreshCoordinator
    private var automaticRefreshTask: Task<Void, Never>?
    private var inFlightRefresh: InFlightRefresh?
    private var consecutiveRefreshFailures = 0
    private var popoverVisible = false
    private let notificationService = NotificationService()
    private let historyStore: HistoryStore
    private let preferences: UserDefaults
    private var didLoadHistory = false

    private struct InFlightRefresh {
        let id: UUID
        let policy: ProviderRefreshPolicy
        let task: Task<Void, Never>
    }

    init(
        providers: [any QuotaProvider]? = nil,
        historyStore: HistoryStore? = nil,
        preferences: UserDefaults? = nil
    ) {
        let preferences = preferences ?? AppPreferences.current
        self.preferences = preferences
        self.historyStore = historyStore ?? HistoryStore(fileURL: Self.defaultHistoryURL())
        snapshots = ProviderID.allCases.map { provider in
            .unavailable(provider, state: .notConfigured)
        }
        coordinator = RefreshCoordinator(
            providers: providers ?? Self.configuredProviders(defaults: preferences),
            store: SnapshotStore()
        )
    }

    func refresh() async {
        await refresh(policy: .scheduled)
    }

    func refreshManually() async {
        await refresh(policy: .userInitiated)
    }

    private func refresh(policy: ProviderRefreshPolicy) async {
        // A popover open, a manual refresh, and the automatic loop can overlap.
        // The previous early return discarded later requests, which left a newly
        // opened popover showing the prior value until the next polling interval.
        // Let all callers await the same collection. If a manual request joined a
        // scheduled collection, follow it with one user-initiated collection so
        // the explicit request is never reduced to a cached automatic result.
        if let inFlightRefresh {
            let activePolicy = inFlightRefresh.policy
            await inFlightRefresh.task.value
            guard !Task.isCancelled else { return }
            if policy == .userInitiated, activePolicy == .scheduled {
                await refresh(policy: .userInitiated)
            }
            return
        }

        let id = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefresh(id: id, policy: policy)
        }
        inFlightRefresh = InFlightRefresh(id: id, policy: policy, task: task)
        await task.value
    }

    func cancel() {
        automaticRefreshTask?.cancel()
        automaticRefreshTask = nil
        cancelInFlightRefresh()
        let coordinator = coordinator
        Task { await coordinator.cancelAll() }
    }

    func startAutomaticRefresh() {
        guard automaticRefreshTask == nil else { return }
        automaticRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.loadHistoryIfNeeded()
            while !Task.isCancelled {
                await self.refresh()
                guard !Task.isCancelled else { break }
                let interval = RefreshPolicy.standard.interval(
                    popoverVisible: self.popoverVisible,
                    idle: false,
                    consecutiveFailures: self.consecutiveRefreshFailures,
                    configuredMinutes: self.configuredRefreshMinutes
                )
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    break
                }
            }
        }
    }

    func setPopoverVisible(_ visible: Bool) {
        guard popoverVisible != visible else { return }
        popoverVisible = visible
        restartAutomaticRefresh()
    }

    func handleWake() {
        restartAutomaticRefresh()
    }

    func refreshScheduleDidChange() {
        restartAutomaticRefresh()
    }

    private func restartAutomaticRefresh() {
        automaticRefreshTask?.cancel()
        automaticRefreshTask = nil
        startAutomaticRefresh()
    }

    func applyProviderConfiguration(
        codexEnabled: Bool,
        codexExecutablePath: String,
        claudeEnabled: Bool,
        grokEnabled: Bool,
        grokAuthPath: String,
        geminiEnabled: Bool,
        geminiExecutablePath: String,
        zaiEnabled: Bool
    ) async {
        let previousCoordinator = coordinator
        cancelInFlightRefresh()
        await previousCoordinator.cancelAll()
        let providers = Self.providers(
            codexEnabled: codexEnabled,
            codexExecutablePath: codexExecutablePath,
            claudeEnabled: claudeEnabled,
            grokEnabled: grokEnabled,
            grokAuthPath: grokAuthPath,
            geminiEnabled: geminiEnabled,
            geminiExecutablePath: geminiExecutablePath,
            zaiEnabled: zaiEnabled
        )
        coordinator = RefreshCoordinator(providers: providers, store: SnapshotStore())
        consecutiveRefreshFailures = 0
        isRefreshing = false
        await refreshManually()
    }

    var connectedCount: Int {
        snapshots.filter { $0.state == .available || $0.state == .partial || $0.state == .stale }.count
    }

    var errorCount: Int {
        snapshots.filter { $0.state == .failed || $0.state == .authenticationRequired || $0.state == .rateLimited }.count
    }

    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await notificationService.requestAuthorization()
            preferences.set(granted, forKey: "notifications.authorized")
            return granted
        } catch {
            return false
        }
    }

    func deleteHistory() async -> Bool {
        do {
            try await historyStore.delete()
            if !history.isEmpty {
                history = []
                historyRevision &+= 1
            }
            return true
        } catch {
            return false
        }
    }

    private func loadHistoryIfNeeded() async {
        guard !didLoadHistory else { return }
        didLoadHistory = true
        let loaded = (try? await historyStore.load()) ?? []
        if loaded != history {
            history = loaded
            historyRevision &+= 1
        }
    }

    private func performRefresh(id: UUID, policy: ProviderRefreshPolicy) async {
        guard inFlightRefresh?.id == id else { return }
        isRefreshing = true
        defer {
            if inFlightRefresh?.id == id {
                inFlightRefresh = nil
                isRefreshing = false
            }
        }

        let coordinator = coordinator
        let nextSnapshots = await coordinator.refreshAll(policy: policy)
        guard !Task.isCancelled, inFlightRefresh?.id == id else { return }

        snapshots = nextSnapshots
        consecutiveRefreshFailures = Self.nextFailureStreak(
            current: consecutiveRefreshFailures,
            snapshots: nextSnapshots
        )
        lastRefreshAt = Date()

        if let result = try? await historyStore.record(nextSnapshots),
           result.changed,
           !Task.isCancelled,
           inFlightRefresh?.id == id {
            history = result.snapshots
            historyRevision &+= 1
        }
        guard !Task.isCancelled, inFlightRefresh?.id == id else { return }
        await deliverQuotaNotificationsIfAllowed()
    }

    private func cancelInFlightRefresh() {
        inFlightRefresh?.task.cancel()
        inFlightRefresh = nil
        isRefreshing = false
    }

    nonisolated static func nextFailureStreak(
        current: Int,
        snapshots: [ProviderSnapshot]
    ) -> Int {
        let attempts = snapshots.compactMap(\.lastAttempt)
        guard !attempts.isEmpty else { return 0 }
        return attempts.allSatisfy { !$0.succeeded } ? current + 1 : 0
    }

    private func deliverQuotaNotificationsIfAllowed() async {
        guard ProcessInfo.processInfo.environment["AIQUOTAMONITOR_UI_TEST"] != "1" else {
            return
        }
        let defaults = preferences
        guard defaults.bool(forKey: "notifications.authorized"),
              defaults.object(forKey: "notifications.enabled") == nil || defaults.bool(forKey: "notifications.enabled") else {
            return
        }
        if defaults.bool(forKey: "quietHours.enabled") {
            let hour = Calendar.current.component(.hour, from: Date())
            if hour >= 22 || hour < 8 { return }
        }
        for snapshot in snapshots where snapshot.state == .available || snapshot.state == .partial {
            for window in snapshot.windows where window.provenance.freshness != .stale {
                // Antigravity occasionally renders a percentage before its reset
                // evidence is complete. Do not turn that partial observation into
                // an actionable Gemini notification.
                if snapshot.provider == .gemini, window.resetsAt == nil { continue }
                guard let event = QuotaAlertEvaluator.event(for: window.remainingRatio) else { continue }
                let percent = Int((window.remainingRatio * 100).rounded())
                let key = NotificationKey(
                    provider: snapshot.provider,
                    windowInstance: window.windowInstance,
                    event: event
                )
                try? await notificationService.notifyIfNeeded(
                    key: key,
                    title: "\(snapshot.provider.displayName) quota",
                    body: "\(window.kind.label) 잔여량이 \(percent)%입니다."
                )
            }
        }
    }

    private static func configuredProviders(defaults: UserDefaults) -> [any QuotaProvider] {
        let claudeEnabled = defaults.object(forKey: "claude.readOnlyEnabled") != nil
            ? defaults.bool(forKey: "claude.readOnlyEnabled")
            : defaults.bool(forKey: "claude.snapshotEnabled")
        return providers(
            codexEnabled: defaults.bool(forKey: "codex.readOnlyEnabled"),
            codexExecutablePath: defaults.string(forKey: "codex.executablePath")
                ?? ProviderConnectionDefaults.codexExecutablePath(),
            claudeEnabled: claudeEnabled,
            grokEnabled: defaults.bool(forKey: "grok.readOnlyEnabled"),
            grokAuthPath: defaults.string(forKey: "grok.authPath")
                ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".grok/auth.json").path,
            geminiEnabled: defaults.bool(forKey: "gemini.readOnlyEnabled"),
            geminiExecutablePath: defaults.string(forKey: "gemini.executablePath")
                ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin/agy").path,
            zaiEnabled: defaults.bool(forKey: "zai.readOnlyEnabled")
        )
    }

    private static func defaultHistoryURL() -> URL {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return FileManager.default.temporaryDirectory.appending(path: "QuotaBeaconTests/history.json")
        }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appending(path: "QuotaBeacon/history-v1.json")
    }

    private var configuredRefreshMinutes: Int {
        let defaults = preferences
        guard let value = defaults.object(forKey: "refresh.minutes") as? Int,
              [1, 5, 15].contains(value) else {
            return 1
        }
        return value
    }

    private static func providers(
        codexEnabled: Bool,
        codexExecutablePath: String,
        claudeEnabled: Bool,
        grokEnabled: Bool,
        grokAuthPath: String,
        geminiEnabled: Bool,
        geminiExecutablePath: String,
        zaiEnabled: Bool
    ) -> [any QuotaProvider] {
        let claude: any QuotaProvider
        if claudeEnabled {
            claude = ClaudeOAuthUsageProvider()
        } else {
            claude = StateOnlyProvider(id: .claude, state: .notConfigured)
        }

        let codex: any QuotaProvider
        if codexEnabled, !codexExecutablePath.isEmpty {
            let executableURL = URL(fileURLWithPath: codexExecutablePath).standardizedFileURL
            let runtimes = CodexRuntimeLocator().locateAll(explicitURL: executableURL)
            codex = CodexAutoProvider(runtimes: runtimes)
        } else {
            codex = StateOnlyProvider(id: .codex, state: .notConfigured)
        }

        let grok: any QuotaProvider
        if grokEnabled, !grokAuthPath.isEmpty {
            let url = URL(fileURLWithPath: grokAuthPath).standardizedFileURL
            grok = GrokBillingProvider(
                authURL: url,
                validator: CredentialFileValidator(allowedRoots: [url.deletingLastPathComponent()])
            )
        } else {
            grok = StateOnlyProvider(id: .grok, state: .notConfigured)
        }

        let gemini: any QuotaProvider
        if geminiEnabled, !geminiExecutablePath.isEmpty {
            gemini = GeminiCLIQuotaProvider(
                locator: GeminiCLIRuntimeLocator(
                    executableURL: URL(fileURLWithPath: geminiExecutablePath)
                )
            )
        } else {
            gemini = StateOnlyProvider(id: .gemini, state: .notConfigured)
        }

        let zai: any QuotaProvider
        if zaiEnabled {
            zai = ZAIPluginUsageProvider()
        } else {
            zai = StateOnlyProvider(id: .zai, state: .notConfigured)
        }
        return [
            claude,
            codex,
            grok,
            gemini,
            zai
        ]
    }
}
