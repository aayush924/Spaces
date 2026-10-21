import Foundation
import Observation

/// App-wide connection and profile settings. The base URL and profile metadata
/// live in UserDefaults; the session token lives in the Keychain.
@MainActor
@Observable
final class AppSettings {
    static let defaultBaseURL = "http://localhost:8000"
    private static let baseURLKey = "serverBaseURL"
    private static let profileNameKey = "profileName"
    private static let profileEmailKey = "profileEmail"
    private static let tokenAccount = "apiToken"

    private(set) var baseURL: String
    private(set) var token: String
    private(set) var profileName: String
    private(set) var profileEmail: String

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keychain: KeychainStore

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
        let storedURL = defaults.string(forKey: Self.baseURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = (storedURL?.isEmpty == false) ? storedURL! : Self.defaultBaseURL
        self.token = keychain.string(for: Self.tokenAccount) ?? ""
        let storedEmail = defaults.string(forKey: Self.profileEmailKey) ?? ""
        self.profileEmail = storedEmail
        let storedName = defaults.string(forKey: Self.profileNameKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let storedName, !storedName.isEmpty {
            self.profileName = storedName
        } else if !storedEmail.isEmpty {
            self.profileName = Self.defaultName(from: storedEmail)
        } else {
            self.profileName = "Profile"
        }
    }

    var isConfigured: Bool { !token.isEmpty }

    /// A client snapshot for the current settings.
    var api: APIClient { APIClient(baseURL: baseURL, token: token) }

    static func defaultName(from email: String) -> String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = trimmed.split(separator: "@", maxSplits: 1).first.map(String.init) ?? trimmed
        return prefix.isEmpty ? "Profile" : prefix
    }

    func setSession(token newToken: String, email: String, name: String?) {
        let tok = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (cleanName?.isEmpty == false) ? cleanName! : Self.defaultName(from: cleanEmail)

        token = tok
        profileEmail = cleanEmail
        profileName = resolvedName

        keychain.set(tok, for: Self.tokenAccount)
        defaults.set(cleanEmail, forKey: Self.profileEmailKey)
        defaults.set(resolvedName, forKey: Self.profileNameKey)
    }

    func updateProfileName(_ newName: String) {
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        profileName = clean
        defaults.set(clean, forKey: Self.profileNameKey)
    }

    func logout() {
        token = ""
        profileEmail = ""
        profileName = "Profile"
        keychain.set(nil, for: Self.tokenAccount)
        defaults.removeObject(forKey: Self.profileEmailKey)
        defaults.removeObject(forKey: Self.profileNameKey)
    }

    func update(baseURL newURL: String, token newToken: String) {
        let url = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let tok = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        baseURL = url.isEmpty ? Self.defaultBaseURL : url
        token = tok
        defaults.set(baseURL, forKey: Self.baseURLKey)
        keychain.set(tok, for: Self.tokenAccount)
    }
}
