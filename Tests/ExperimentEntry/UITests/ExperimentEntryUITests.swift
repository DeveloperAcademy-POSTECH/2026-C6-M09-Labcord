import XCTest

@MainActor
final class ExperimentEntryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFigmaScreensAndProtocolSourceBoundaries() {
        let app = launch(["--fixture-home"])
        XCTAssertTrue(app.buttons["entry-add"].waitForExistence(timeout: 10))
        XCTAssertEqual(rows(app).count, 7)
        capture("home-502-12299")
        app.buttons["entry-add"].tap()
        XCTAssertTrue(app.buttons["entry-skip"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["entry-next"].isEnabled)
        capture("registration-502-12563")
        app.buttons["entry-back"].tap()
        XCTAssertEqual(rows(app).count, 7)
    }

    func testCreateCancelSelectAndRelaunchPreserveUUID() {
        let app = launch(["--reset-store", "--observe-events"])
        XCTAssertTrue(app.buttons["entry-add"].waitForExistence(timeout: 10))
        XCTAssertEqual(rows(app).count, 0)
        app.buttons["entry-add"].tap()
        app.buttons["entry-back"].tap()
        XCTAssertEqual(rows(app).count, 0)
        app.buttons["entry-add"].tap()
        app.buttons["entry-skip"].tap()
        XCTAssertTrue(rows(app).firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(rows(app).count, 1)
        let identifier = rows(app).firstMatch.identifier
        let uuid = String(identifier.dropFirst("experiment-row-".count))
        XCTAssertEqual(app.staticTexts["qa-event"].label, "created:\(uuid)")
        capture("created-preparing-experiment")
        app.terminate()
        app.launchArguments = ["--observe-events"]
        app.launch()
        XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 10))
        XCTAssertEqual(rows(app).count, 1)
        app.buttons[identifier].tap()
        XCTAssertEqual(app.staticTexts["qa-event"].label, "selected:\(uuid)")
    }

    func testSaveFailureAndRetryCreateOneExperiment() {
        let app = launch(["--reset-store", "--fail-first-save", "--observe-events"])
        XCTAssertTrue(app.buttons["entry-add"].waitForExistence(timeout: 10))
        app.buttons["entry-add"].tap()
        app.buttons["entry-skip"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.firstMatch.label.contains("저장하지 못했어요"))
        capture("save-failure")
        app.alerts.buttons["재시도"].tap()
        XCTAssertTrue(rows(app).firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(rows(app).count, 1)
        XCTAssertTrue(app.staticTexts["qa-event"].label.hasPrefix("created:"))
    }

    func testLoadFailureRetryAndInputEvents() {
        let app = launch(["--reset-store", "--fail-first-load", "--observe-events"])
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10))
        app.alerts.buttons["재시도"].tap()
        XCTAssertTrue(app.buttons["entry-add"].waitForExistence(timeout: 5))
        app.buttons["entry-settings"].tap()
        XCTAssertEqual(app.staticTexts["qa-event"].label, "settings")
        app.buttons["entry-add"].tap()
        for source in ["photos", "file", "recent"] {
            app.buttons["entry-source-\(source)"].tap()
            XCTAssertEqual(app.staticTexts["qa-event"].label, "source:\(source)")
        }
        XCTAssertFalse(app.buttons["entry-next"].isEnabled)
        app.buttons["entry-back"].tap()
        XCTAssertEqual(rows(app).count, 0)
    }

    func testSwipeEditCancelDeleteAndRelaunch() {
        let app = launch(["--reset-store", "--observe-events"])
        XCTAssertTrue(app.buttons["entry-add"].waitForExistence(timeout: 10))
        for _ in 0..<2 {
            app.buttons["entry-add"].tap()
            app.buttons["entry-skip"].tap()
            XCTAssertTrue(rows(app).firstMatch.waitForExistence(timeout: 10))
        }
        XCTAssertEqual(rows(app).count, 2)
        let identifier = rows(app).firstMatch.identifier
        let uuid = String(identifier.dropFirst("experiment-row-".count))
        let retained = rows(app).element(boundBy: 1).identifier
        app.buttons[identifier].swipeLeft()
        XCTAssertTrue(app.buttons["entry-edit-\(uuid)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["entry-delete-\(uuid)"].exists)
        capture("swipe-edit-and-delete")
        app.buttons["entry-edit-\(uuid)"].tap()
        XCTAssertEqual(app.staticTexts["qa-event"].label, "edit:\(uuid)")
        revealDelete(app, row: identifier, uuid: uuid)
        app.buttons["entry-delete-\(uuid)"].tap()
        XCTAssertTrue(app.alerts["실험을 삭제할까요?"].waitForExistence(timeout: 5))
        capture("delete-confirmation")
        app.alerts.buttons["취소"].tap()
        XCTAssertTrue(app.buttons[identifier].exists)
        XCTAssertEqual(rows(app).count, 2)
        revealDelete(app, row: identifier, uuid: uuid)
        app.buttons["entry-delete-\(uuid)"].tap()
        app.alerts.buttons["삭제"].tap()
        XCTAssertTrue(app.buttons[identifier].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons[retained].exists)
        app.terminate()
        app.launchArguments = ["--observe-events"]
        app.launch()
        XCTAssertTrue(app.buttons[retained].waitForExistence(timeout: 10))
        XCTAssertEqual(rows(app).count, 1)
        XCTAssertFalse(app.buttons[identifier].exists)
    }

    func testDeleteFailurePreservesRowAndRetries() {
        let app = launch(["--reset-store", "--fail-first-delete"])
        XCTAssertTrue(app.buttons["entry-add"].waitForExistence(timeout: 10))
        app.buttons["entry-add"].tap()
        app.buttons["entry-skip"].tap()
        XCTAssertTrue(rows(app).firstMatch.waitForExistence(timeout: 10))
        let identifier = rows(app).firstMatch.identifier
        let uuid = String(identifier.dropFirst("experiment-row-".count))
        revealDelete(app, row: identifier, uuid: uuid)
        app.buttons["entry-delete-\(uuid)"].tap()
        app.alerts.buttons["삭제"].tap()
        XCTAssertTrue(app.alerts["실험을 삭제하지 못했어요"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[identifier].exists)
        capture("delete-failure")
        app.alerts.buttons["재시도"].tap()
        XCTAssertTrue(app.buttons[identifier].waitForNonExistence(timeout: 5))
        XCTAssertEqual(rows(app).count, 0)
    }

    private func revealDelete(_ app: XCUIApplication, row: String, uuid: String) {
        if !app.buttons["entry-delete-\(uuid)"].isHittable {
            app.buttons[row].swipeLeft()
        }
        XCTAssertTrue(app.buttons["entry-delete-\(uuid)"].waitForExistence(timeout: 5))
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func rows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "experiment-row-"))
    }

    private func capture(_ name: String) {
        // 화면 전환과 시스템 표시가 유휴 상태로 정착할 시간을 둡니다.
        Thread.sleep(forTimeInterval: 4)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let app = XCUIApplication()
        let identifiers = ["entry-add", "entry-settings", "entry-back", "entry-skip", "entry-next"]
        let frames = identifiers.compactMap { identifier -> [String: Any]? in
            let button = app.buttons[identifier]
            guard button.exists else { return nil }
            let frame = button.frame
            return ["identifier": identifier, "x": frame.minX, "y": frame.minY,
                    "width": frame.width, "height": frame.height]
        }
        if let data = try? JSONSerialization.data(withJSONObject: frames, options: .sortedKeys) {
            let geometry = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            geometry.name = "geometry-\(name)"
            geometry.lifetime = .keepAlways
            add(geometry)
        }
    }
}
