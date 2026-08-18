import Foundation

/// Tries resolved Codex runtimes in deterministic order. This keeps a stale
/// saved path from preventing a working app-bundle or package-manager install
/// from being used, while retaining the existing app-server contract.
struct CodexAutoProvider: QuotaProvider {
    let id = ProviderID.codex
    let runtimes: [CodexRuntime]
    let runner: ProcessRunner

    init(runtimes: [CodexRuntime], runner: ProcessRunner = ProcessRunner()) {
        self.runtimes = runtimes
        self.runner = runner
    }

    func availability() async -> ProviderAvailability {
        runtimes.isEmpty ? .notConfigured : .available
    }

    func fetchQuota() async -> ProviderFetchResult {
        guard !runtimes.isEmpty else {
            return ProviderFetchResult(snapshot: .unavailable(id, state: .notConfigured))
        }

        var lastResult: ProviderFetchResult?
        for runtime in runtimes {
            let result = await CodexAppServerProvider(
                executableURL: runtime.executableURL,
                runtime: runtime,
                runner: runner
            ).fetchQuota()
            lastResult = result
            if result.snapshot.state == .available || result.snapshot.state == .partial {
                return result
            }
            if Task.isCancelled { break }
        }

        return lastResult ?? ProviderFetchResult(snapshot: .unavailable(id, state: .failed))
    }
}
