//
//  AuGendaWatch_Watch_AppUITestsLaunchTests.swift
//  AuGendaWatch Watch AppUITests
//
//  Created by Arthur Ens on 2026-05-29.
//

import XCTest

final class AuGendaWatch_Watch_AppUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.staticTexts["CAPTURE"].waitForExistence(timeout: 5),
            "Every Watch launch configuration must expose capture"
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Watch capture surface"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
