import Foundation
import XCTest
@testable import Toolbox

final class ShortcutAITests: XCTestCase {
    func testIdentityClaimsAndPlanPermissionFailClosed() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let valid: [String: Any] = ["iss": "https://auth.openai.com", "aud": "issued", "sub": "subject",
                                    "exp": 2000.0, "nonce": "nonce"]
        XCTAssertEqual(try ChatGPTProtocol.identityClaims(valid, clientID: "issued", nonce: "nonce", now: now).0, "subject")
        let mutations: [(String, Any)] = [("iss", "https://example.invalid"), ("aud", "other"), ("exp", 500.0), ("nonce", "other"), ("sub", ""), ("nbf", 3000.0)]
        for (key, value) in mutations {
            var invalid = valid; invalid[key] = value
            XCTAssertThrowsError(try ChatGPTProtocol.identityClaims(invalid, clientID: "issued", nonce: "nonce", now: now))
        }
        var multiple = valid; multiple["aud"] = ["issued", "other"]
        XCTAssertThrowsError(try ChatGPTProtocol.identityClaims(multiple, clientID: "issued", nonce: "nonce", now: now))
        let scopes = ["openid", "offline_access", "resource.invoke", "chatgpt.tokens.use.direct"]
        try ChatGPTProtocol.tokenPolicy(type: "Bearer", expiresIn: 3600, scopes: scopes)
        for omitted in scopes { XCTAssertThrowsError(try ChatGPTProtocol.tokenPolicy(type: "Bearer", expiresIn: 3600, scopes: scopes.filter { $0 != omitted })) }
        XCTAssertThrowsError(try ChatGPTProtocol.tokenPolicy(type: "Basic", expiresIn: 3600, scopes: scopes))
        XCTAssertThrowsError(try ChatGPTProtocol.tokenPolicy(type: "Bearer", expiresIn: .infinity, scopes: scopes))
    }

    func testCallbackRejectsDuplicateStateWrongStateAndPath() throws {
        let valid = "GET /auth/callback?state=expected&code=code&client_id=issued HTTP/1.1\r\n\r\n"
        let values = try ChatGPTProtocol.callback(valid, state: "expected")
        XCTAssertEqual(try ChatGPTProtocol.clientID(values, previous: nil), "issued")
        XCTAssertThrowsError(try ChatGPTProtocol.callback(valid, state: "other"))
        XCTAssertThrowsError(try ChatGPTProtocol.callback(valid.replacingOccurrences(of: "state=expected", with: "state=expected&state=expected"), state: "expected"))
        XCTAssertThrowsError(try ChatGPTProtocol.callback(valid.replacingOccurrences(of: "/auth/callback", with: "/callback"), state: "expected"))
        XCTAssertThrowsError(try ChatGPTProtocol.clientID(values, previous: "different"))
        XCTAssertThrowsError(try ChatGPTProtocol.clientID(["code": "code"], previous: nil))
        XCTAssertThrowsError(try ChatGPTProtocol.clientID(["code": "code", "client_id": "dynamic_agent_client"], previous: nil))
        XCTAssertThrowsError(try ChatGPTProtocol.clientID(["code": "code", "error": "access_denied"], previous: "issued"))
        XCTAssertEqual(try ChatGPTProtocol.clientID(["code": "code"], previous: "issued"), "issued")
    }

    private func feed(_ payload: [String: Any], into stream: inout ShortcutResponseStream) throws {
        let json = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        try stream.line("data: \(json)"); try stream.line("")
    }

    func testPartialOutputAndFailedTerminalNeverBecomeDraft() throws {
        for terminal in ["response.failed", "response.incomplete", "error", "response.refusal.done"] {
            var stream = ShortcutResponseStream()
            try feed(["type": "response.output_text.delta", "delta": "partial"], into: &stream)
            XCTAssertThrowsError(try stream.finish())
            XCTAssertThrowsError(try feed(["type": terminal], into: &stream))
        }
        var stream = ShortcutResponseStream()
        try stream.line("data: [DONE]")
        XCTAssertThrowsError(try stream.line(""))
    }

    func testCompleteStreamRequiresCompletedStatusAndFrameBoundary() throws {
        var stream = ShortcutResponseStream()
        try feed(["type": "response.output_text.delta", "delta": "日本語"], into: &stream)
        try feed(["type": "response.completed", "response": ["status": "completed"]], into: &stream)
        XCTAssertEqual(try stream.finish(), "日本語")
        var invalid = ShortcutResponseStream()
        XCTAssertThrowsError(try feed(["type": "response.completed", "response": ["status": "incomplete"]], into: &invalid))
        var unframed = ShortcutResponseStream()
        try unframed.line(#"data: {"type":"response.completed","response":{"status":"completed"}}"#)
        XCTAssertThrowsError(try unframed.finish())
    }

    func testOnlySelectedDraftMaterialIsSentAndSupportedFieldsAreUsed() throws {
        var draft = ShortcutDraft.example
        draft.revisions = [ShortcutRevision(name: "HISTORY_SECRET", source: draft.source, summary: "HISTORY_SECRET")]
        let without = try ShortcutAI.body(instruction: "Make a draft", selectedDraft: nil, model: "test-model")
        XCTAssertFalse(String(decoding: without, as: UTF8.self).contains(draft.name))
        let with = try ShortcutAI.body(instruction: "Change this", selectedDraft: draft, model: "test-model")
        XCTAssertFalse(String(decoding: with, as: UTF8.self).contains("HISTORY_SECRET"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: with) as? [String: Any])
        XCTAssertEqual(Set(body.keys), Set(["model", "instructions", "input", "store", "stream"]))
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual((body["input"] as? [[String: String]])?.count, 2)
    }

    func testModelsPreserveServerOrderHideUnavailableAndDoNotUseGenericFallback() throws {
        let data = Data(#"{"models":[{"slug":"z","display_name":"First","visibility":"list"},{"slug":"hidden","visibility":"hide"},{"slug":"a","visibility":"list"},{"slug":"z","visibility":"list"}]}"#.utf8)
        XCTAssertEqual(try ShortcutAI.modelChoices(data).map(\.id), ["z", "a"])
        XCTAssertThrowsError(try ShortcutAI.modelChoices(Data(#"{"data":[{"id":"gpt-test"}]}"#.utf8)))
    }

    func testProposalRejectsInvalidWorkflowAndDoesNotCarryHistory() throws {
        XCTAssertThrowsError(try ShortcutAI.proposal(#"{"name":"Bad","summary":"","workflow":{"WFWorkflowActions":null}}"#))
        let sample = ShortcutDraft.example
        let payload = try JSONSerialization.data(withJSONObject: ["name": "Generated", "summary": "Draft", "workflow": try ShortcutFormat.workflow(sample.source)])
        let value = try ShortcutAI.proposal(String(decoding: payload, as: UTF8.self))
        XCTAssertEqual(value.actionCount, 1)
        XCTAssertTrue(value.revisions.isEmpty)
        XCTAssertNotEqual(value.id, sample.id)
    }
}
