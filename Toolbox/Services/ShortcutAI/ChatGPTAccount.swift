import Foundation
import Observation
import Security

enum ChatGPTKeychain {
    private static let service = "com.hority.toolbox.chatgpt"

    static func read(_ account: String) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let result = SecItemCopyMatching(query as CFDictionary, &item)
        if result == errSecItemNotFound { return nil }
        guard result == errSecSuccess else { throw ShortcutError.message("認証情報を読み込めませんでした（\(result)）。") }
        return item as? Data
    }

    static func write(_ account: String, data: Data?) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        guard let data else {
            let result = SecItemDelete(query as CFDictionary)
            guard result == errSecSuccess || result == errSecItemNotFound else { throw ShortcutError.message("認証情報を削除できませんでした。") }
            return
        }
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw ShortcutError.message("認証情報を更新できませんでした。") }
        var new = query
        new[kSecValueData as String] = data
        new[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(new as CFDictionary, nil) == errSecSuccess else { throw ShortcutError.message("認証情報を保存できませんでした。") }
    }

    static func string(_ account: String) throws -> String { try read(account).map { String(decoding: $0, as: UTF8.self) } ?? "" }
    static func set(_ account: String, value: String) throws {
        try write(account, data: value.isEmpty ? nil : Data(value.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
    }
}

struct ChatGPTAccounts: Codable {
    var registrations: [ChatGPTSession] = []
    var selectedID: String?
}

@MainActor @Observable final class ChatGPTAccount {
    private(set) var records = ChatGPTAccounts()
    private(set) var epoch = UUID()
    private(set) var authenticating = false
    private(set) var models: [ShortcutAIModel] = []
    var model = ""
    var notice: String?
    @ObservationIgnored private var refreshTask: Task<ChatGPTSession, Error>?
    @ObservationIgnored private var refreshID: UUID?
    @ObservationIgnored private var storageReadable = true
    @ObservationIgnored private let save: (Data) throws -> Void
    @ObservationIgnored private let authorize: (ChatGPTSession?) async throws -> ChatGPTSession
    @ObservationIgnored private let refresh: (ChatGPTSession) async throws -> ChatGPTSession
    @ObservationIgnored private let revoke: (ChatGPTSession) async throws -> Void
    @ObservationIgnored private var catalogID = UUID()
    @ObservationIgnored private let fetchModels: (String) async throws -> [ShortcutAIModel]
    @ObservationIgnored private let cancelLogin: () -> Void

    var selected: ChatGPTSession? { records.registrations.first { $0.clientID == records.selectedID } }
    var connected: Bool { selected.map { !$0.accessToken.isEmpty && !$0.refreshToken.isEmpty } ?? false }

    init(load: () throws -> Data? = { try ChatGPTKeychain.read("accounts") },
         save: @escaping (Data) throws -> Void = { try ChatGPTKeychain.write("accounts", data: $0) },
         authorize: ((ChatGPTSession?) async throws -> ChatGPTSession)? = nil,
         cancelLogin: (() -> Void)? = nil,
         refresh: @escaping (ChatGPTSession) async throws -> ChatGPTSession = { try await ChatGPTLogin.refresh($0) },
         fetchModels: @escaping (String) async throws -> [ShortcutAIModel] = { try await ShortcutAI.models(credential: $0) },
         revoke: @escaping (ChatGPTSession) async throws -> Void = { try await ChatGPTLogin.revoke($0) }) {
        let login = ChatGPTLogin()
        self.authorize = authorize ?? { try await login.signIn(previous: $0) }
        self.cancelLogin = cancelLogin ?? { login.cancel() }
        self.save = save; self.refresh = refresh; self.revoke = revoke; self.fetchModels = fetchModels
        do {
            if let data = try load() { records = try JSONDecoder().decode(ChatGPTAccounts.self, from: data) }
        } catch { storageReadable = false; notice = "認証情報を読み込めませんでした。端末のロック解除後に開き直してください。" }
    }

    private func persist(_ next: ChatGPTAccounts) throws {
        guard storageReadable else { throw ShortcutError.message("認証情報を読み込めなかったため保存を中止しました。開き直してください。") }
        try save(JSONEncoder().encode(next))
        records = next
    }

    func assertCurrent(_ value: UUID) throws {
        try Task.checkCancellation()
        guard value == epoch else { throw CancellationError() }
    }

    private func invalidate() {
        epoch = UUID()
        cancelLogin()
        refreshTask?.cancel(); refreshTask = nil; refreshID = nil
        authenticating = false
        models = []; model = ""
    }

    func select(_ id: String) throws {
        guard records.registrations.contains(where: { $0.clientID == id }) else { return }
        invalidate()
        var next = records; next.selectedID = id
        try persist(next)
    }

    func signIn(newAccount: Bool = false) async throws {
        guard storageReadable else { throw ShortcutError.message("認証情報を読み込めなかったためログインを中止しました。開き直してください。") }
        guard !authenticating, refreshTask == nil else { throw ShortcutError.message("認証処理が進行中です。") }
        authenticating = true
        let version = epoch
        let previous = newAccount ? nil : selected
        defer { if version == epoch { authenticating = false } }
        let result = try await authorize(previous)
        try assertCurrent(version)
        if let previous {
            guard previous.clientID == result.clientID, previous.subject == result.subject else {
                throw ShortcutError.message("アカウントが一致しません。")
            }
        }
        var next = records
        if let index = next.registrations.firstIndex(where: { $0.clientID == result.clientID }) {
            guard next.registrations[index].subject == result.subject else { throw ShortcutError.message("登録情報が一致しません。") }
            next.registrations[index] = result
        } else { next.registrations.append(result) }
        next.selectedID = result.clientID
        try persist(next)
        // New credentials invalidate all model choices and in-flight results from the prior session.
        epoch = UUID(); models = []; model = ""; authenticating = false
    }

    func cancelSignIn() { invalidate() }

    func signOut() async {
        let old = selected
        invalidate()
        let version = epoch
        var next = records
        if let index = next.registrations.firstIndex(where: { $0.clientID == old?.clientID }) {
            next.registrations[index].accessToken = ""
            next.registrations[index].refreshToken = ""
            next.registrations[index].idToken = ""
            next.registrations[index].scopes = []
            next.registrations[index].expiresAt = .distantPast
        }
        // Stop using credentials immediately, even if Keychain deletion fails.
        records = next
        do { try persist(next) }
        catch { notice = "ログアウトしましたが、Keychainの削除に失敗しました。端末のロック解除後に再度ログアウトしてください。" }
        guard let old, !old.refreshToken.isEmpty else { return }
        do { try await revoke(old) }
        catch {
            if epoch == version { notice = "端末からログアウトしました。接続解除は確認できません。ChatGPTの設定でもこのアプリを解除してください。" }
        }
    }

    func credential() async throws -> String {
        guard !authenticating, let current = selected, connected else { throw ShortcutError.message("ChatGPTにログインしてください。") }
        let version = epoch
        if current.expiresAt > Date().addingTimeInterval(90) { return current.accessToken }
        if let refreshTask {
            let result = try await refreshTask.value
            try assertCurrent(version)
            return result.accessToken
        }
        let id = UUID()
        refreshID = id
        let task = Task { @MainActor in
            let result = try await self.refresh(current)
            try self.assertCurrent(version)
            guard result.clientID == current.clientID, result.subject == current.subject else { throw CancellationError() }
            var next = self.records
            guard let index = next.registrations.firstIndex(where: { $0.clientID == current.clientID }) else { throw CancellationError() }
            next.registrations[index] = result
            // Commit rotating refresh token and access token atomically before any waiter can use either.
            try self.persist(next)
            return result
        }
        refreshTask = task
        defer { if refreshID == id { refreshTask = nil; refreshID = nil } }
        do {
            let result = try await task.value
            try assertCurrent(version)
            return result.accessToken
        } catch {
            if epoch == version {
                // Never retry an old rotating refresh token after an uncertain exchange or failed persistence.
                var next = records
                if let index = next.registrations.firstIndex(where: { $0.clientID == current.clientID }) {
                    next.registrations[index].accessToken = ""; next.registrations[index].refreshToken = ""
                    next.registrations[index].idToken = ""
                }
                records = next
                try? persist(next)
                models = []; model = ""
            }
            throw error
        }
    }

    func refreshModels() async throws {
        let version = epoch
        let requestID = UUID(); catalogID = requestID
        models = []; model = ""
        let token = try await credential()
        let choices = try await fetchModels(token)
        try assertCurrent(version)
        guard catalogID == requestID else { throw CancellationError() }
        models = choices
        model = choices.first?.id ?? ""
        if choices.isEmpty { notice = "このアカウントで利用可能なモデルがありません。" }
    }
}
