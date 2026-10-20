import Foundation
import XCTest
@testable import Toolbox

@MainActor private final class AuthGate<Value: Sendable> {
    private var pending: CheckedContinuation<Value, Error>?
    private var started: CheckedContinuation<Void, Never>?
    func call() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            started?.resume(); started = nil
        }
    }
    func waitForCall() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func succeed(_ value: Value) { pending?.resume(returning: value); pending = nil }
}

final class ChatGPTAccountTests: XCTestCase {
    @MainActor private func session(expired: Bool = false, suffix: String = "one") -> ChatGPTSession {
        ChatGPTSession(clientID: "issued-\(suffix)", subject: "subject-\(suffix)", email: "fixture@example.invalid",
                       accessToken: "fixture-access", refreshToken: "fixture-refresh", idToken: "fixture-id",
                       expiresAt: expired ? .distantPast : .distantFuture,
                       scopes: ["openid", "offline_access", "resource.invoke", "chatgpt.tokens.use.direct"])
    }

    @MainActor func testSignOutDiscardsStaleLoginAndRepeatedTapIsRejected() async throws {
        let gate = AuthGate<ChatGPTSession>()
        var saved: Data?
        let account = ChatGPTAccount(load: { nil }, save: { saved = $0 }, authorize: { _ in try await gate.call() }, revoke: { _ in })
        let attempt = Task { try await account.signIn(newAccount: true) }
        await gate.waitForCall()
        do { try await account.signIn(); XCTFail("Repeated sign-in was accepted") } catch { }
        await account.signOut()
        gate.succeed(session())
        do { try await attempt.value; XCTFail("Stale sign-in was accepted") } catch { }
        XCTAssertFalse(account.connected)
        XCTAssertTrue(account.records.registrations.isEmpty)
        let stored = try JSONDecoder().decode(ChatGPTAccounts.self, from: XCTUnwrap(saved))
        XCTAssertTrue(stored.registrations.isEmpty)
    }

    @MainActor func testConcurrentRefreshPersistsRotatedSetOnceBeforeReturning() async throws {
        let old = session(expired: true)
        let initial = try JSONEncoder().encode(ChatGPTAccounts(registrations: [old], selectedID: old.clientID))
        let gate = AuthGate<ChatGPTSession>()
        var calls = 0
        var writes: [Data] = []
        let account = ChatGPTAccount(load: { initial }, save: { writes.append($0) }, refresh: { _ in calls += 1; return try await gate.call() }, revoke: { _ in })
        let first = Task { try await account.credential() }
        await gate.waitForCall()
        let second = Task { try await account.credential() }
        var rotated = session(); rotated.accessToken = "rotated-access"; rotated.refreshToken = "rotated-refresh"
        gate.succeed(rotated)
        let firstValue = try await first.value
        let secondValue = try await second.value
        XCTAssertEqual(firstValue, "rotated-access"); XCTAssertEqual(secondValue, "rotated-access")
        XCTAssertEqual(calls, 1); XCTAssertEqual(writes.count, 1)
        let stored = try JSONDecoder().decode(ChatGPTAccounts.self, from: XCTUnwrap(writes.first))
        XCTAssertEqual(stored.registrations.first?.refreshToken, "rotated-refresh")
        XCTAssertEqual(stored.registrations.first?.accessToken, "rotated-access")
    }

    @MainActor func testRefreshAfterLogoutCannotRestoreTokensAndMappingSurvives() async throws {
        let old = session(expired: true)
        let initial = try JSONEncoder().encode(ChatGPTAccounts(registrations: [old], selectedID: old.clientID))
        let gate = AuthGate<ChatGPTSession>()
        let account = ChatGPTAccount(load: { initial }, save: { _ in }, refresh: { _ in try await gate.call() }, revoke: { _ in })
        let attempt = Task { try await account.credential() }
        await gate.waitForCall()
        await account.signOut()
        gate.succeed(session())
        do { _ = try await attempt.value; XCTFail("Stale refresh was accepted") } catch { }
        XCTAssertFalse(account.connected)
        XCTAssertEqual(account.selected?.clientID, old.clientID)
        XCTAssertEqual(account.selected?.subject, old.subject)
        XCTAssertEqual(account.selected?.idToken, "")
        XCTAssertEqual(account.selected?.refreshToken, "")
    }

    @MainActor func testFailedPersistenceDoesNotExposeRefreshedCredentials() async throws {
        let old = session(expired: true)
        let initial = try JSONEncoder().encode(ChatGPTAccounts(registrations: [old], selectedID: old.clientID))
        let rotated = session()
        let account = ChatGPTAccount(load: { initial }, save: { _ in throw ShortcutError.message("fixture storage failure") }, refresh: { _ in rotated }, revoke: { _ in })
        do { _ = try await account.credential(); XCTFail("Unpersisted token exposed") } catch { }
        XCTAssertFalse(account.connected)
    }

    @MainActor func testSwitchClearsModelsAndRejectsOldCatalogCompletion() async throws {
        let one = session(); let two = session(suffix: "two")
        let initial = try JSONEncoder().encode(ChatGPTAccounts(registrations: [one, two], selectedID: one.clientID))
        let gate = AuthGate<[ShortcutAIModel]>()
        let account = ChatGPTAccount(load: { initial }, save: { _ in }, fetchModels: { _ in try await gate.call() }, revoke: { _ in })
        let attempt = Task { try await account.refreshModels() }
        await gate.waitForCall()
        try account.select(two.clientID)
        gate.succeed([ShortcutAIModel(id: "old-account-only", name: "Old")])
        do { try await attempt.value; XCTFail("Stale catalog was accepted") } catch { }
        XCTAssertTrue(account.models.isEmpty)
        XCTAssertEqual(account.model, "")
        XCTAssertEqual(account.selected?.clientID, two.clientID)
    }
}
