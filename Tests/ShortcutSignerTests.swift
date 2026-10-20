import Foundation
import XCTest
@testable import Toolbox

@MainActor
final class ShortcutSignerTests: XCTestCase {
    private func response(_ status: Int = 200, url: URL = ShortcutSigner.endpoint, headers: [String: String]? = nil) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    func testRequestUsesOriginalShortcutyEndpointAndBinaryPlist() throws {
        let draft = ShortcutDraft.example
        let request = try ShortcutSigner.request(for: draft)
        XCTAssertEqual(request.url, URL(string: "https://sign.shortcuty.app/api/v1/sign"))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Filename"), "Toolbox.shortcut")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(request.httpBody)
        let workflow = try XCTUnwrap(PropertyListSerialization.propertyList(from: body, options: [], format: nil) as? [String: Any])
        try ShortcutSigner.validateWorkflow(workflow, source: draft.source)
        XCTAssertNil(workflow["revisions"])
    }

    func testOnlyMatchingWorkflowIsAccepted() throws {
        let source = ShortcutDraft.example.source
        var workflow = try ShortcutFormat.workflow(source)
        XCTAssertNoThrow(try ShortcutSigner.validateWorkflow(workflow, source: source))
        workflow["WFWorkflowActions"] = []
        XCTAssertThrowsError(try ShortcutSigner.validateWorkflow(workflow, source: source))
        workflow = try ShortcutFormat.workflow(source)
        workflow["UnexpectedServiceField"] = "changed"
        XCTAssertThrowsError(try ShortcutSigner.validateWorkflow(workflow, source: source))
    }

    func testMalformedAndUnsignedServiceResponsesAreRejected() throws {
        let source = ShortcutDraft.example.source
        for data in [Data(), Data("AEA1".utf8), Data("AEA1garbage".utf8), try ShortcutFormat.plist(source)] {
            XCTAssertThrowsError(try ShortcutSigner.validateSignedData(data, source: source))
        }
    }

    func testAllRedirectsAndOtherHostsAreRejected() {
        XCTAssertThrowsError(try ShortcutSigner.validateHTTP(response(302)))
        XCTAssertThrowsError(try ShortcutSigner.validateHTTP(response(url: URL(string: "https://other.example/sign")!)))
        XCTAssertThrowsError(try ShortcutSigner.validateHTTP(response(url: URL(string: "http://sign.shortcuty.app/api/v1/sign")!)))
    }

    func testServiceErrorsAndOversizeAreRejected() {
        for code in [400, 401, 402, 403, 413, 422, 429, 500, 502, 503, 504] {
            XCTAssertThrowsError(try ShortcutSigner.validateHTTP(response(code)))
        }
        XCTAssertThrowsError(try ShortcutSigner.validateHTTP(response(headers: ["Content-Length": "16000001"])))
        XCTAssertNoThrow(try ShortcutSigner.validateHTTP(response()))
        XCTAssertThrowsError(try ShortcutSigner.validateSignedData(Data(count: 16_000_001), source: ShortcutDraft.example.source))
    }

    func testInjectedTransportErrorDoesNotCreateSuccessfulExport() async {
        let http = response(502)
        do {
            _ = try await ShortcutSigner.sign(.example) { _ in
                ShortcutSigningResponse(data: Data("AEA1".utf8), response: http)
            }
            XCTFail("HTTP failure must not produce an exported file")
        } catch { XCTAssertTrue(error.localizedDescription.contains("502")) }
    }

    func testInjectedTransportCannotPassHeaderOnlyResponse() async {
        let http = response()
        do {
            _ = try await ShortcutSigner.sign(.example) { _ in
                ShortcutSigningResponse(data: Data("AEA1fake".utf8), response: http)
            }
            XCTFail("Malformed AEA must not produce an exported file")
        } catch { /* Expected: real archive decoding rejects the fake prefix. */ }
    }

    func testCancellationStopsBeforeUpload() async {
        let task = Task {
            try await ShortcutSigner.sign(.example) { _ in
                throw ShortcutError.message("Transport must not be called")
            }
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}

extension ShortcutSignerTests {
    func testBookkeepingNeverHidesExistingValuesOrSemanticChanges() throws {
        let original = try ShortcutFormat.workflow(ShortcutDraft.example.source)
        var accepted = original
        accepted["WFWorkflowClientVersion"] = "5037.0.17"
        accepted["WFQuickActionSurfaces"] = []
        accepted["WFWorkflowOutputContentItemClasses"] = []
        accepted["WFWorkflowHasShortcutInputVariables"] = false
        XCTAssertNoThrow(try ShortcutSigner.validateWorkflow(accepted, source: ShortcutDraft.example.source))
        let mutations: [(String, Any)] = [
            ("WFWorkflowActions", []), ("WFWorkflowMinimumClientVersion", 999),
            ("WFWorkflowMinimumClientVersionString", "999"),
            ("WFWorkflowInputContentItemClasses", ["WFImageContentItem"]),
            ("WFWorkflowHasOutputFallback", true), ("WFWorkflowHasShortcutInputVariables", true),
            ("WFQuickActionSurfaces", ["Finder"]), ("WFWorkflowOutputContentItemClasses", ["WFImageContentItem"]),
            ("WFWorkflowHasShortcutInputVariables", 0), ("WFWorkflowHasOutputFallback", 0), ("UnexpectedServiceField", false)
        ]
        for (key, value) in mutations {
            var bad = accepted; bad[key] = value
            XCTAssertThrowsError(try ShortcutSigner.validateWorkflow(bad, source: ShortcutDraft.example.source), key)
        }
        var changedAction = accepted
        changedAction["WFWorkflowActions"] = [["WFWorkflowActionIdentifier": "is.workflow.actions.alert", "WFWorkflowActionParameters": ["WFAlertActionMessage": "changed"]]]
        XCTAssertThrowsError(try ShortcutSigner.validateWorkflow(changedAction, source: ShortcutDraft.example.source))
        var booleanMutation = accepted
        var actions = original["WFWorkflowActions"] as! [[String: Any]]
        var parameters = actions[0]["WFWorkflowActionParameters"] as! [String: Any]
        parameters["WFAlertActionCancelButtonShown"] = 0
        actions[0]["WFWorkflowActionParameters"] = parameters
        booleanMutation["WFWorkflowActions"] = actions
        XCTAssertThrowsError(try ShortcutSigner.validateWorkflow(booleanMutation, source: ShortcutDraft.example.source))
        for value in ["", "5037", "5037..17", "5037.0.17/evil", String(repeating: "1", count: 65) + ".0"] {
            var bad = accepted; bad["WFWorkflowClientVersion"] = value
            XCTAssertThrowsError(try ShortcutSigner.validateWorkflow(bad, source: ShortcutDraft.example.source))
        }
        var missing = accepted; missing.removeValue(forKey: "WFWorkflowHasOutputFallback")
        XCTAssertThrowsError(try ShortcutSigner.validateWorkflow(missing, source: ShortcutDraft.example.source))
        var existing = original; existing["WFQuickActionSurfaces"] = ["Finder"]
        XCTAssertThrowsError(try ShortcutSigner.validateWorkflow(accepted, source: ShortcutFormat.json(existing)))
    }
}
