import XCTest
@testable import LazyFlow

@MainActor
final class CorrectionEngineTests: XCTestCase {
    func testAppSpecificCorrectionOverridesMoreFrequentGlobalCorrection() {
        var global = CorrectionEntry(heard: "lazy flow", correct: "Lazy Flow")
        global.frequency = 100
        let appSpecific = CorrectionEntry(
            heard: "lazy flow",
            correct: "LazyFlow",
            bundleIdentifier: "com.apple.dt.Xcode"
        )

        let selected = CorrectionStore.selectRelevantCorrections(
            from: [global, appSpecific],
            transcript: "open lazy flow",
            bundleID: "com.apple.dt.Xcode"
        )

        XCTAssertEqual(selected.map(\.id), [appSpecific.id])
    }

    func testLongerOverlappingPhraseWins() {
        let short = CorrectionEntry(heard: "flow", correct: "FLOW")
        let long = CorrectionEntry(heard: "lazy flow", correct: "LazyFlow")
        let selected = CorrectionStore.selectRelevantCorrections(
            from: [short, long],
            transcript: "launch lazy flow now",
            bundleID: nil
        )

        let result = CorrectionEngine.apply(
            "launch lazy flow now",
            corrections: selected
        )

        XCTAssertEqual(result.text, "launch LazyFlow now")
        XCTAssertEqual(result.appliedIDs, [long.id])
    }

    func testCorrectionsDoNotCascade() {
        let first = CorrectionEntry(heard: "alpha", correct: "beta")
        let second = CorrectionEntry(heard: "beta", correct: "gamma")

        let result = CorrectionEngine.apply(
            "alpha",
            corrections: [first, second]
        )

        XCTAssertEqual(result.text, "beta")
        XCTAssertEqual(result.appliedIDs, [first.id])
    }

    func testCorrectionRequiresAWholePhraseBoundary() {
        let correction = CorrectionEntry(heard: "flow", correct: "stream")
        let selected = CorrectionStore.selectRelevantCorrections(
            from: [correction],
            transcript: "workflow",
            bundleID: nil
        )

        XCTAssertTrue(selected.isEmpty)
    }
}
