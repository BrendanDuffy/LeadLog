//  LeadLogUITests.swift

import XCTest

final class LeadLogUITests: XCTestCase {

    @MainActor
    func testLaunchPerformance() throws {
        // Guards against launch-time regressions.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
