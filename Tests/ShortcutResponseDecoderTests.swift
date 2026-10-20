import Foundation
import XCTest
@testable import Toolbox

final class ShortcutResponseDecoderTests: XCTestCase {
    private let draftText = #"{"name":"Fixture","summary":"Synthetic","workflow":{"WFWorkflowActions":[]}}"#

    private func event(_ value: [String: Any]) throws -> String {
        "data: " + String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self) + "\n\n"
    }

    private func sse() throws -> String {
        try event(["type": "response.created", "response": ["status": "in_progress"]]) +
            event(["type": "response.output_text.delta", "delta": draftText]) +
            event(["type": "response.completed", "response": ["status": "completed"]])
    }

    private func response(status: String = "completed") -> [String: Any] {
        ["id": "resp_fixture", "object": "response", "status": status,
         "output": [["type": "message", "role": "assistant", "status": "completed",
                     "content": [["type": "output_text", "text": draftText]]]]]
    }

    private func decode(_ body: Data, mime: String?, status: Int = 200) throws -> String {
        var decoder = ShortcutResponseDecoder(status: status, contentType: mime)
        for byte in body { _ = try decoder.append(byte) }
        return try decoder.finish()
    }

    func testMissingMIMEReproducesOldGuardBoundaryButValidSSEIsAccepted() throws {
        let http = try XCTUnwrap(HTTPURLResponse(url: URL(string: "https://example.invalid/responses")!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:]))
        XCTAssertNotEqual(http.mimeType, "text/event-stream") // Published guard would reject before inspecting bytes.
        let text = try decode(Data(sse().utf8), mime: nil)
        XCTAssertEqual(text, draftText)
        XCTAssertEqual(try ShortcutAI.proposal(text).name, "Fixture")
    }

    func testNormalizeCaseParametersAndRequireValidBodyRegardlessOfHeader() throws {
        XCTAssertEqual(ShortcutResponseDecoder.normalizedMIME(" Text/Event-Stream ; charset=UTF-8 "), "text/event-stream")
        for mime in ["Text/Event-Stream; charset=UTF-8", "application/octet-stream", "application/json"] {
            XCTAssertEqual(try decode(Data(sse().utf8), mime: mime), draftText)
            XCTAssertThrowsError(try decode(Data("<html>not a response</html>".utf8), mime: mime))
        }
        XCTAssertThrowsError(try decode(Data(sse().utf8), mime: "text/html"))
        XCTAssertThrowsError(try decode(Data(sse().utf8), mime: "text/event-stream", status: 503))
    }

    func testCompletedJSONExtractsOnlyAssistantOutputAndStillValidatesDraft() throws {
        let types: [String?] = ["Application/JSON; charset=utf-8", nil]
        for mime in types {
            let text = try decode(JSONSerialization.data(withJSONObject: response()), mime: mime)
            XCTAssertEqual(text, draftText)
            XCTAssertEqual(try ShortcutAI.proposal(text).name, "Fixture")
        }
        var badDraft = response()
        badDraft["output"] = [["type": "message", "role": "assistant", "status": "completed",
                               "content": [["type": "output_text", "text": "not a shortcut"]]]]
        let text = try decode(JSONSerialization.data(withJSONObject: badDraft), mime: "application/json")
        XCTAssertThrowsError(try ShortcutAI.proposal(text))
    }

    func testJSONRejectsPartialErrorRefusalToolsAndUnvalidatedDraft() throws {
        for status in ["in_progress", "queued", "incomplete", "failed"] {
            XCTAssertThrowsError(try decode(JSONSerialization.data(withJSONObject: response(status: status)), mime: "application/json"))
        }
        for body in [#"{"detail":"fixture admission failure"}"#, #"{"error":{"code":"fixture"}}"#, draftText] {
            XCTAssertThrowsError(try decode(Data(body.utf8), mime: "application/json"))
        }
        let invalidOutputs: [[[String: Any]]] = [
            [["type": "function_call", "name": "fixture"]],
            [["type": "message", "role": "assistant", "status": "completed", "content": [["type": "refusal", "refusal": "fixture"]]]]
        ]
        for output in invalidOutputs {
            var value = response(); value["output"] = output
            XCTAssertThrowsError(try decode(JSONSerialization.data(withJSONObject: value), mime: "application/json"))
        }
    }

    func testSSERequiresSuccessfulTerminalAndRejectsJunkOrTruncatedFrames() throws {
        let created = try event(["type": "response.created", "response": ["status": "in_progress"]])
        let delta = try event(["type": "response.output_text.delta", "delta": draftText])
        for body in [created, created + delta, String(try sse().dropLast()),
                     try sse() + "<html>junk</html>\n", created + delta + "data: [DONE]\n\n"] {
            XCTAssertThrowsError(try decode(Data(body.utf8), mime: nil))
        }
        for terminal in ["response.failed", "response.incomplete", "error"] {
            XCTAssertThrowsError(try decode(Data((created + delta + event(["type": terminal])).utf8), mime: nil))
        }
    }

    func testDiagnosticsNeverEchoUnknownHeaderOrBodyAndJSONIsBounded() throws {
        let decoder = ShortcutResponseDecoder(status: 200, contentType: "application/PRIVATE_FIXTURE; token=PRIVATE_FIXTURE")
        XCTAssertEqual(decoder.diagnostic, "HTTP 200 · Content-Type: other")
        XCTAssertFalse(decoder.diagnostic.contains("PRIVATE_FIXTURE"))
        do {
            _ = try decode(Data("{\"detail\":\"PRIVATE_BODY_FIXTURE\"}".utf8), mime: nil)
            XCTFail("Invalid body accepted")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains("PRIVATE_BODY_FIXTURE"))
            XCTAssertTrue(error.localizedDescription.contains("Content-Type: missing"))
            XCTAssertTrue(error.localizedDescription.contains("利用枠・モデル・接続を確認してください。"))
        }
        XCTAssertThrowsError(try decode(Data(("{" + String(repeating: " ", count: 4_000_000)).utf8), mime: "application/json"))
    }
}
