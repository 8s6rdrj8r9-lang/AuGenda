//
//  AuGendaUITestsLaunchTests.swift
//  AuGendaUITests
//
//  Created by Arthur Ens on 2026-05-24.
//

import XCTest

final class AuGendaUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["capacity.title"].waitForExistence(timeout: 5),
            "Every launch configuration must reach the clean capacity step"
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Clean capacity step"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
