import XCTest

final class GeminiVoiceUITests: XCTestCase {
  private func launch(missingKey: Bool = false, simulatedRelay: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["GEMINI_VOICE_DISABLE_RELAY_AUTOSTART"] = "1"
    if missingKey { app.launchEnvironment["GEMINI_VOICE_FORCE_MISSING_API_KEY"] = "1" }
    if simulatedRelay { app.launchEnvironment["GEMINI_SIMULATOR_HANDOFF_TEST"] = "1" }
    app.launch()
    return app
  }

  func testMissingAPIKeyLeadsToConnectionSettings() {
    let app = launch(missingKey: true)
    let banner = app.buttons["api-key-required-card"]
    XCTAssertTrue(banner.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["relay-control-button"].isEnabled)
    XCTAssertFalse(app.buttons["camera-ocr-button"].isEnabled)
    capture("Missing key")
    banner.tap()
    app.buttons["gemini-connection-link"].tap()
    XCTAssertTrue(app.secureTextFields["api-key-field"].waitForExistence(timeout: 3))
    capture("Connection")
  }

  func testNavigationAndSettings() {
    let app = launch()
    XCTAssertTrue(app.buttons["relay-control-button"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["camera-ocr-button"].exists)
    capture("Relay paused")

    app.tabBars.buttons["History"].tap()
    XCTAssertTrue(app.staticTexts["Words worth keeping"].waitForExistence(timeout: 3))
    capture("History empty")

    app.tabBars.buttons["Settings"].tap()
    XCTAssertTrue(app.buttons["translation-language-picker"].waitForExistence(timeout: 3))
    capture("Settings")
    if !app.buttons["Models"].isHittable { app.swipeUp() }
    app.buttons["Models"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["active-transcription-model"].exists)
    XCTAssertTrue(app.descendants(matching: .any)["active-translation-model"].exists)
    capture("Models")

    app.tabBars.buttons["Relay"].tap()
    app.buttons["Keyboard setup"].tap()
    XCTAssertTrue(app.staticTexts["Allow Full Access"].waitForExistence(timeout: 3))
    capture("Keyboard setup")
  }

  func testRelayEnableAndPauseWithSimulatedAudio() {
    let app = launch(simulatedRelay: true)
    let control = app.buttons["relay-control-button"]
    XCTAssertTrue(control.waitForExistence(timeout: 5))
    control.tap()
    let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
    if permission.waitForExistence(timeout: 5) {
      permission.buttons["Allow"].tap()
    }
    XCTAssertTrue(app.staticTexts["Your keyboard is ready"].waitForExistence(timeout: 8))
    XCTAssertTrue(app.staticTexts["Auto-pauses in"].exists)
    XCTAssertEqual(control.label, "Pause Relay")
    capture("Relay enabled")
    control.tap()
    XCTAssertTrue(app.staticTexts["Ready when you are"].waitForExistence(timeout: 3))
    XCTAssertEqual(control.label, "Enable Relay")
    XCTAssertFalse(app.staticTexts["Auto-pauses in"].exists)
  }

  func testPhotoPickerCanBeCancelled() {
    let app = launch()
    let photos = app.buttons["photo-ocr-button"]
    if !photos.isHittable { app.swipeUp() }
    photos.tap()
    let cancel = app.buttons["Cancel"]
    XCTAssertTrue(cancel.waitForExistence(timeout: 5))
    cancel.tap()
    XCTAssertTrue(app.buttons["relay-control-button"].waitForExistence(timeout: 5))
  }

  func testHistoryCopyAndVisualStates() {
    let app = XCUIApplication()
    app.launchEnvironment["GEMINI_VOICE_DISABLE_RELAY_AUTOSTART"] = "1"
    app.launchEnvironment["GEMINI_VOICE_VISUAL_TEST_SCENARIO"] = "history"
    app.launch()
    app.tabBars.buttons["History"].tap()
    let text = "Let’s take the scenic route. We can stop for coffee on the way."
    XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 3))
    capture("History with text")
    app.staticTexts[text].tap()
    app.buttons["copy-transcript-button"].tap()
    XCTAssertEqual(app.buttons["copy-transcript-button"].label, "Copied")
    capture("Saved text")

    app.launchEnvironment["GEMINI_VOICE_VISUAL_TEST_SCENARIO"] = "recording"
    app.launch()
    XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["relay-control-button"].isEnabled)
    capture("Listening preview")
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.buttons["relay-control-button"].isEnabled)

    app.launchEnvironment["GEMINI_VOICE_VISUAL_TEST_SCENARIO"] = "handoff"
    app.launch()
    XCTAssertTrue(app.descendants(matching: .any)["keyboard-handoff-overlay"].waitForExistence(timeout: 3))
    capture("Handoff preview")
    app.buttons["Cancel handoff"].tap()
    XCTAssertFalse(app.descendants(matching: .any)["keyboard-handoff-overlay"].exists)
  }

  func testKeyboardPractice() {
    let app = launch()
    app.tabBars.buttons["Settings"].tap()
    if !app.buttons["Try your keyboard"].isHittable { app.swipeUp() }
    app.buttons["Try your keyboard"].tap()
    let editor = app.textViews["keyboard-practice-text"]
    XCTAssertTrue(editor.waitForExistence(timeout: 3))
    editor.tap()
    editor.typeText("A little less typing.")
    XCTAssertEqual(editor.value as? String, "A little less typing.")
    capture("Keyboard practice")
  }

  func testInAppNoteStartsAndCanBeDiscarded() {
    let app = launch(simulatedRelay: true)
    let record = app.buttons["record-note-button"]
    XCTAssertTrue(record.waitForExistence(timeout: 5))
    if !record.isHittable { app.swipeUp() }
    record.tap()
    let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
    if permission.waitForExistence(timeout: 2), permission.buttons["Allow"].exists {
      permission.buttons["Allow"].tap()
    }
    XCTAssertTrue(app.buttons["finish-note-button"].waitForExistence(timeout: 8))
    capture("Record a note")
    app.buttons["cancel-note-button"].tap()
    app.buttons["Discard Recording"].tap()
    XCTAssertTrue(record.waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["finish-note-button"].exists)
  }

  func testSavedNoteCopyAndHistory() {
    let app = XCUIApplication()
    app.launchEnvironment["GEMINI_VOICE_DISABLE_RELAY_AUTOSTART"] = "1"
    app.launchEnvironment["GEMINI_VOICE_VISUAL_TEST_SCENARIO"] = "note-saved"
    app.launch()
    let copy = app.buttons["copy-note-button"]
    XCTAssertTrue(copy.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["saved-note-text"].exists)
    capture("Saved voice note")
    copy.tap()
    XCTAssertEqual(copy.label, "Copied")
    app.buttons["View in History"].tap()
    XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Some days are worth slowing down for.")).firstMatch.exists)
  }

  func testRetentionSettingSavesNumberOfDays() {
    let app = launch()
    app.tabBars.buttons["Settings"].tap()
    app.buttons["history-retention-link"].tap()
    let days = app.textFields["history-retention-days"]
    XCTAssertTrue(days.waitForExistence(timeout: 3))
    capture("History retention")
    days.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
    let existing = days.value as? String ?? "30"
    days.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + "45")
    app.buttons["save-history-retention-button"].tap()
    app.buttons["history-retention-link"].tap()
    XCTAssertEqual(days.value as? String, "45")
    days.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
    days.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (days.value as? String ?? "45").count) + "30")
    app.buttons["save-history-retention-button"].tap()
  }

  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
