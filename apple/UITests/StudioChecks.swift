import XCTest

final class StudioChecks: XCTestCase {
    @MainActor
    func testColorSelectionAndLandscapeDrawing() throws {
        #if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        #endif
        let app = XCUIApplication()
        app.launch()
        let canvas = app.otherElements["drawingCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        app.buttons["青"].tap()
        let picker = app.buttons["chooseColor"]
        let original = picker.value as? String
        picker.tap()
        XCTAssertTrue(app.sliders["redSlider"].waitForExistence(timeout: 5))
        // Merely opening the picker must preserve the existing precise color.
        app.buttons["finishChoosingColor"].tap()
        XCTAssertEqual(picker.value as? String, original)
        picker.tap()
        app.sliders["redSlider"].adjust(toNormalizedSliderPosition: 0.8)
        let changedLevel = app.staticTexts["redLevel"].label
        let colorShot = XCTAttachment(screenshot: app.screenshot())
        colorShot.name = "Display P3 color selection"
        colorShot.lifetime = .keepAlways
        add(colorShot)
        app.buttons["finishChoosingColor"].tap()
        let changed = picker.value as? String
        XCTAssertNotEqual(changed, original)
        picker.tap()
        XCTAssertEqual(app.staticTexts["redLevel"].label, changedLevel)
        app.buttons["finishChoosingColor"].tap()
        #if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        #endif
        XCTAssertTrue(app.frame.contains(canvas.frame))
        XCTAssertTrue(picker.isHittable)
        let before = canvas.value as? String
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.4))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.6)))
        XCTAssertNotEqual(canvas.value as? String, before)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        // Capture the display: application-only cropping on some Simulator
        // versions applies portrait coordinates to a rotated surface.
        let landscapeShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landscapeShot.name = "Landscape drawing"
        landscapeShot.lifetime = .keepAlways
        add(landscapeShot)
    }

    @MainActor
    func testDrawUndoRedoAndRestore() throws {
        let app = XCUIApplication()
        app.launch()
        let canvas = app.otherElements["drawingCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        // Use the UI to start a blank drawing; this also works on repeated runs.
        app.buttons["ファイル"].tap()
        app.buttons["キャンバスを空にする"].tap()
        app.buttons["空にする（取り消し可能）"].tap()
        XCTAssertEqual(canvas.value as? String, "0本の線")
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.3))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.65))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(app.buttons["取り消す"].isEnabled)
        XCTAssertEqual(canvas.value as? String, "1本の線")
        app.buttons["取り消す"].tap()
        XCTAssertEqual(canvas.value as? String, "0本の線")
        app.buttons["やり直す"].tap()
        XCTAssertEqual(canvas.value as? String, "1本の線")
        XCTAssertTrue(app.staticTexts["保存済み"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        XCTAssertEqual(canvas.value as? String, "1本の線")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
    @MainActor
    func testPaperPresetsColorAndRestore() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.otherElements["drawingCanvas"].waitForExistence(timeout: 15))
        app.buttons["ファイル"].tap()
        app.buttons["新しい用紙"].tap()
        app.buttons["paperUse"].tap()
        app.buttons["漫画・同人誌"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "4961 × 7016")).firstMatch.exists)
        app.buttons["paperUse"].tap()
        app.buttons["画面用イラスト"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "2048 × 2048")).firstMatch.exists)
        app.buttons["paperUse"].tap()
        app.buttons["印刷用イラスト"].tap()
        app.buttons["paperPreset"].tap()
        app.buttons["はがき"].tap()
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Paper presets and physical dimensions"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["createPaper"].tap()
        let settings = app.buttons["paperSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        XCTAssertTrue(settings.label.contains("1181 × 1748"))
        let initialColor = settings.value as? String
        settings.tap()
        app.buttons["paperColor2"].tap()
        app.buttons["applyPaperColor"].tap()
        let changedColor = settings.value as? String
        XCTAssertNotEqual(changedColor, initialColor)
        app.buttons["取り消す"].tap()
        XCTAssertEqual(settings.value as? String, initialColor)
        app.buttons["やり直す"].tap()
        XCTAssertEqual(settings.value as? String, changedColor)
        app.sliders["pigmentStrength"].adjust(toNormalizedSliderPosition: 0.9)
        let canvas = app.otherElements["drawingCanvas"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.4))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.6)))
        XCTAssertEqual(canvas.value as? String, "1本の線")
        XCTAssertTrue(app.staticTexts["保存済み"].waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        XCTAssertEqual(settings.value as? String, changedColor)
        XCTAssertTrue(settings.label.contains("1181 × 1748"))
        XCTAssertEqual(canvas.value as? String, "1本の線")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        let tinted = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        tinted.name = "Pastel on tinted paper"; tinted.lifetime = .keepAlways; add(tinted)
    }

}
