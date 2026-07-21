import XCTest
@testable import N1KOState

final class WP6ReleaseHardeningTests: XCTestCase {
    func testDiskAndExportDiagnosticsShareSecretRedaction() {
        let raw = "token=private-token /Users/test/project response_owner_id=owner-1"
        let logged = DiagLog.sanitizedMessage(raw)
        let exported = DiagnosticExporter.redactedLog(raw)

        XCTAssertEqual(logged, exported)
        XCTAssertFalse(exported.contains("private-token"))
        XCTAssertFalse(exported.contains("/Users/test"))
        XCTAssertFalse(exported.contains("owner-1"))
    }

    func testDiagnosticPrivacyManifestStatesLocalExplicitAndNoAutomaticUpload() {
        let text = DiagnosticExporter.privacyManifest
        XCTAssertTrue(text.contains("created locally"))
        XCTAssertTrue(text.contains("user selects"))
        XCTAssertTrue(text.contains("never uploads it automatically"))
        XCTAssertTrue(text.contains("Review the archive before sharing"))
    }
}
