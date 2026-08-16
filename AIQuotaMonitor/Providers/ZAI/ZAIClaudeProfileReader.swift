import Foundation

struct ZAIClaudeProfile: Equatable, Sendable {
    let baseURL: String
    let authToken: String
}

protocol ZAIProfileReading: Sendable {
    func read() throws -> ZAIClaudeProfile
}

enum ZAIProfileError: Error, Equatable {
    case fileUnavailable
    case unsafeFile
    case profileMissing
    case malformedProfile
    case unsupportedBaseURL
}

struct ZAIClaudeProfileReader: ZAIProfileReading {
    let profileURL: URL

    init(
        profileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.profileURL = profileURL
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: ".zshrc")
    }

    func read() throws -> ZAIClaudeProfile {
        let url = profileURL.standardizedFileURL
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            throw ZAIProfileError.fileUnavailable
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              (values.fileSize ?? 0) <= 1_048_576 else {
            throw ZAIProfileError.unsafeFile
        }
        let contents: String
        do {
            contents = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ZAIProfileError.fileUnavailable
        }
        return try Self.parse(contents)
    }

    static func parse(_ contents: String) throws -> ZAIClaudeProfile {
        let candidate = contents
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .first { line in
                line.trimmingCharacters(in: .whitespaces).hasPrefix("alias claude-glm=")
            }
        guard let candidate,
              let equals = candidate.firstIndex(of: "=") else {
            throw ZAIProfileError.profileMissing
        }

        let rawBody = String(candidate[candidate.index(after: equals)...])
            .trimmingCharacters(in: .whitespaces)
        var words = try ShellWords.parse(rawBody)
        if words.count == 1, words[0].contains(where: \Character.isWhitespace) {
            words = try ShellWords.parse(words[0])
        }

        var baseURL: String?
        var authToken: String?
        var command: String?
        for word in words {
            guard command == nil else { continue }
            if let equals = word.firstIndex(of: "="), equals != word.startIndex {
                let key = String(word[..<equals])
                let value = String(word[word.index(after: equals)...])
                switch key {
                case "ANTHROPIC_BASE_URL": baseURL = value
                case "ANTHROPIC_AUTH_TOKEN": authToken = value
                default: break
                }
            } else {
                command = word
            }
        }

        guard command.map({ URL(fileURLWithPath: $0).lastPathComponent }) == "claude",
              let baseURL,
              let authToken,
              !authToken.isEmpty else {
            throw ZAIProfileError.malformedProfile
        }
        guard let url = URL(string: baseURL),
              url.scheme == "https",
              url.host?.lowercased() == "api.z.ai",
              url.path.hasPrefix("/api/anthropic") else {
            throw ZAIProfileError.unsupportedBaseURL
        }
        return ZAIClaudeProfile(baseURL: baseURL, authToken: authToken)
    }
}

private enum ShellWords {
    private enum Quote { case none, single, double }

    static func parse(_ source: String) throws -> [String] {
        var result: [String] = []
        var current = ""
        var quote = Quote.none
        var escaped = false
        var hasToken = false

        for character in source {
            if escaped {
                current.append(character)
                escaped = false
                hasToken = true
                continue
            }
            switch quote {
            case .single:
                if character == "'" { quote = .none }
                else { current.append(character) }
                hasToken = true
            case .double:
                if character == "\"" { quote = .none }
                else if character == "\\" { escaped = true }
                else { current.append(character) }
                hasToken = true
            case .none:
                if character == "'" {
                    quote = .single
                    hasToken = true
                } else if character == "\"" {
                    quote = .double
                    hasToken = true
                } else if character == "\\" {
                    escaped = true
                    hasToken = true
                } else if character.isWhitespace {
                    if hasToken {
                        result.append(current)
                        current = ""
                        hasToken = false
                    }
                } else {
                    current.append(character)
                    hasToken = true
                }
            }
        }

        guard quote == .none, !escaped else {
            throw ZAIProfileError.malformedProfile
        }
        if hasToken { result.append(current) }
        guard !result.isEmpty else { throw ZAIProfileError.malformedProfile }
        return result
    }
}
