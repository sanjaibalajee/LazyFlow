import XCTest
@testable import LazyFlow

final class MobileContractTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "LazyFlowMobileTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testToneRoundTripsThroughSharedContract() {
        let store = SharedDictationStore(defaults: defaults)
        store.setTone(.veryCasual)
        XCTAssertEqual(store.snapshot().tone, .veryCasual)
    }

    func testPublishedResultIsAcknowledged() {
        let store = SharedDictationStore(defaults: defaults)
        store.setPhase(.ready, renewSession: true)
        store.publish("Hello from LazyFlow")

        let published = store.snapshot()
        XCTAssertEqual(published.phase, .resultReady)
        XCTAssertEqual(published.result, "Hello from LazyFlow")
        XCTAssertFalse(published.resultID.isEmpty)

        store.acknowledgeResult()
        let acknowledged = store.snapshot()
        XCTAssertEqual(acknowledged.phase, .ready)
        XCTAssertTrue(acknowledged.result.isEmpty)
    }

    func testEveryEditableToneContainsMeaningPreservationRule() {
        for tone in MobileTone.allCases where tone != .verbatim {
            XCTAssertTrue(tone.editingInstructions.contains("Preserve the speaker's meaning"))
        }
    }

    @MainActor
    func testHistoryPersistsProcessingMetadata() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LazyFlowHistory-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = HistoryStore(fileURL: fileURL)
        store.add(
            ProcessingResult(
                transcript: "hello there",
                finalText: "Hello there.",
                transcriptionLabel: "Whisper Large V3 Turbo",
                rewriteLabel: "GPT-OSS 20B"
            ),
            tone: .clean
        )

        let reloaded = HistoryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.entries.first?.finalText, "Hello there.")
        XCTAssertEqual(reloaded.entries.first?.rewriteLabel, "GPT-OSS 20B")
    }

    func testGroqModelIdentifiersMatchProductionEndpoints() {
        XCTAssertEqual(GroqSpeechModel.turbo.rawValue, "whisper-large-v3-turbo")
        XCTAssertEqual(GroqSpeechModel.accurate.rawValue, "whisper-large-v3")
        XCTAssertEqual(GroqRewriteModel.fast.rawValue, "openai/gpt-oss-20b")
        XCTAssertEqual(GroqRewriteModel.quality.rawValue, "openai/gpt-oss-120b")
    }

    func testKeychainRoundTrip() throws {
        let account = "test_\(UUID().uuidString)"
        defer { try? MobileKeychain.delete(for: account) }

        try MobileKeychain.save("gsk_test_value", for: account)
        XCTAssertEqual(MobileKeychain.load(for: account), "gsk_test_value")
        try MobileKeychain.delete(for: account)
        XCTAssertNil(MobileKeychain.load(for: account))
    }
}
