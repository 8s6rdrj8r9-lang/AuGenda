//
//  AuGendaWatch_Watch_AppUITests.swift
//  AuGendaWatch Watch AppUITests
//
//  Created by Arthur Ens on 2026-05-29.
//

import XCTest

final class AuGendaWatch_Watch_AppUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsCaptureSurface() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.staticTexts["CAPTURE"].waitForExistence(timeout: 5),
            "The Watch orientation surface must always expose capture"
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
