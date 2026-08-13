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
}
