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
