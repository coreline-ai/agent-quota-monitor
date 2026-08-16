import Foundation

struct GrokCredential: Sendable {
    let accessToken: String
    let userID: String
}

struct GrokCredentialReader: Sendable {
    let authURL: URL
    let validator: CredentialFileValidator

    func read(now: Date = Date()) throws -> GrokCredential {
        try validator.validate(authURL)
        let data: Data
        do {
            data = try Data(contentsOf: authURL, options: [.mappedIfSafe])
        } catch {
            throw ProviderErrorCode.missingCredential
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderErrorCode.invalidCredential
        }

        let entries = root.compactMap { scope, value -> (Int, [String: Any])? in
            guard let credential = value as? [String: Any] else { return nil }
            let priority = scope.hasPrefix("https://auth.x.ai::") ? 0 : 1
            return (priority, credential)
        }.sorted { $0.0 < $1.0 }

        var foundCredentialMaterial = false
        for (_, entry) in entries {
            guard let token = entry["key"] as? String,
                  !token.isEmpty,
                  let userID = entry["user_id"] as? String,
                  !userID.isEmpty else {
                continue
            }
            foundCredentialMaterial = true
            if let rawExpiration = entry["expires_at"] {
                guard let expiration = expirationDate(rawExpiration), expiration > now else {
                    continue
                }
            }
            return GrokCredential(accessToken: token, userID: userID)
        }
        throw foundCredentialMaterial ? ProviderErrorCode.invalidCredential : ProviderErrorCode.missingCredential
    }

    private func expirationDate(_ value: Any?) -> Date? {
        if let numeric = value as? NSNumber {
            let seconds = numeric.doubleValue > 10_000_000_000
                ? numeric.doubleValue / 1_000
                : numeric.doubleValue
            return Date(timeIntervalSince1970: seconds)
        }
        guard let text = value as? String else { return nil }
        if let numeric = Double(text) {
            let seconds = numeric > 10_000_000_000 ? numeric / 1_000 : numeric
            return Date(timeIntervalSince1970: seconds)
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }
}
