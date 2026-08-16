import SwiftUI

@MainActor
final class QuotaMonitorModel: ObservableObject {
    @Published private(set) var snapshots: [ProviderSnapshot]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var history: [ProviderSnapshot] = []

    private var coordinator: RefreshCoordinator
    private var automaticRefreshTask: Task<Void, Never>?
    private var popoverVisible = false
    private let notificationService = NotificationService()
    private let historyStore: HistoryStore
    private var didLoadHistory = false

    init(
        providers: [any QuotaProvider]? = nil
    ) {
        historyStore = HistoryStore(fileURL: Self.defaultHistoryURL())
        snapshots = ProviderID.allCases.map { provider in
            .unavailable(
                provider,
                state: provider == .zai ? .unsupportedContract : .notConfigured
            )
        }
        coordinator = RefreshCoordinator(
            providers: providers ?? Self.configuredProviders(defaults: .standard),
            store: SnapshotStore()
        )
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        snapshots = await coordinator.refreshAll()
        lastRefreshAt = Date()
        isRefreshing = false
        history.append(contentsOf: snapshots)
        try? await historyStore.save(history)
        await deliverQuotaNotificationsIfAllowed()
    }

    func cancel() {
        automaticRefreshTask?.cancel()
        automaticRefreshTask = nil
        Task { await coordinator.cancelAll() }
    }

    func startAutomaticRefresh() {
        guard automaticRefreshTask == nil else { return }
        automaticRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.loadHistoryIfNeeded()
            while !Task.isCancelled {
                await self.refresh()
                let failures = self.snapshots.filter { $0.state == .failed || $0.state == .offline }.count
                let interval = RefreshPolicy.standard.interval(
                    popoverVisible: self.popoverVisible,
                    idle: false,
                    consecutiveFailures: failures
                )
                try? await Task.sleep(for: interval)
            }
        }
    }

    func setPopoverVisible(_ visible: Bool) {
        popoverVisible = visible
        automaticRefreshTask?.cancel()
        automaticRefreshTask = nil
        startAutomaticRefresh()
    }

    func handleWake() {
        automaticRefreshTask?.cancel()
        automaticRefreshTask = nil
        startAutomaticRefresh()
    }

    func applyProviderConfiguration(
        codexEnabled: Bool,
        codexExecutablePath: String,
        claudeEnabled: Bool,
        claudeSnapshotPath: String,
        grokEnabled: Bool,
        grokAuthPath: String
    ) async {
        await coordinator.cancelAll()
        let providers = Self.providers(
            codexEnabled: codexEnabled,
            codexExecutablePath: codexExecutablePath,
            claudeEnabled: claudeEnabled,
            claudeSnapshotPath: claudeSnapshotPath,
            grokEnabled: grokEnabled,
            grokAuthPath: grokAuthPath
        )
        coordinator = RefreshCoordinator(providers: providers, store: SnapshotStore())
        isRefreshing = false
        await refresh()
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
            UserDefaults.standard.set(granted, forKey: "notifications.authorized")
            return granted
        } catch {
            return false
        }
    }

    func deleteHistory() async -> Bool {
        do {
            try await historyStore.delete()
            history = []
            return true
        } catch {
            return false
        }
    }

    private func loadHistoryIfNeeded() async {
        guard !didLoadHistory else { return }
        didLoadHistory = true
        history = (try? await historyStore.load()) ?? []
    }

    private func deliverQuotaNotificationsIfAllowed() async {
        let defaults = UserDefaults.standard
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
        providers(
            codexEnabled: defaults.bool(forKey: "codex.readOnlyEnabled"),
            codexExecutablePath: defaults.string(forKey: "codex.executablePath") ?? "/opt/homebrew/bin/codex",
            claudeEnabled: defaults.bool(forKey: "claude.snapshotEnabled"),
            claudeSnapshotPath: defaults.string(forKey: "claude.snapshotPath") ?? "",
            grokEnabled: defaults.bool(forKey: "grok.readOnlyEnabled"),
            grokAuthPath: defaults.string(forKey: "grok.authPath")
                ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".grok/auth.json").path
        )
    }

    private static func defaultHistoryURL() -> URL {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return FileManager.default.temporaryDirectory.appending(path: "QuotaBeaconTests/history.json")
        }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appending(path: "QuotaBeacon/history-v1.json")
    }

    private static func providers(
        codexEnabled: Bool,
        codexExecutablePath: String,
        claudeEnabled: Bool,
        claudeSnapshotPath: String,
        grokEnabled: Bool,
        grokAuthPath: String
    ) -> [any QuotaProvider] {
        let claude: any QuotaProvider
        if claudeEnabled, !claudeSnapshotPath.isEmpty {
            let url = URL(fileURLWithPath: claudeSnapshotPath).standardizedFileURL
            claude = ClaudeStatusSnapshotProvider(
                snapshotURL: url,
                validator: CredentialFileValidator(allowedRoots: [url.deletingLastPathComponent()])
            )
        } else {
            claude = StateOnlyProvider(id: .claude, state: .notConfigured)
        }

        let codex: any QuotaProvider
        if codexEnabled, !codexExecutablePath.isEmpty {
            codex = CodexAppServerProvider(executableURL: URL(fileURLWithPath: codexExecutablePath))
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
        return [
            claude,
            codex,
            grok,
            StateOnlyProvider(id: .zai, state: .unsupportedContract)
        ]
    }
}
