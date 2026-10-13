//
//  AuGendaUITests.swift
//  AuGendaUITests
//
//  Created by Arthur Ens on 2026-05-24.
//

import XCTest

final class AuGendaUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCleanLaunchShowsCapacityChoice() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["capacity.title"].waitForExistence(timeout: 5),
            "A clean test store should begin at the capacity step"
        )
        XCTAssertTrue(app.buttons["capacity.survival"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing"]
            app.launch()
        }
    }
}
