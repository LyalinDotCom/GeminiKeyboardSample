import XCTest

final class KeyboardVisualReviewTests: XCTestCase {
  func testInstalledKeyboardAppearance() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["GEMINI_VOICE_DISABLE_RELAY_AUTOSTART"] = "1"
    app.launchEnvironment["GEMINI_SIMULATOR_HANDOFF_TEST"] = "1"
    app.launch()

    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    settings.launch()
    if !settings.cells["KEYBOARDS"].exists {
      for _ in 0..<5 {
        let back = settings.navigationBars.buttons["BackButton"]
        guard back.exists else { break }
        back.tap()
      }
      tapText("General", in: settings)
      tapText("Keyboard", in: settings)
    }
    settings.cells["KEYBOARDS"].tap()
    if !settings.staticTexts["Gemini Voice"].exists {
      let add = settings.cells["AddNewKeyboard"]
      XCTAssertTrue(add.waitForExistence(timeout: 3), settings.debugDescription)
      add.tap()
      tapText("Gemini Voice", in: settings)
    }
    tapText("Gemini Voice", in: settings)
    let fullAccess = settings.switches["Allow Full Access"].switches.firstMatch
    XCTAssertTrue(fullAccess.waitForExistence(timeout: 3), settings.debugDescription)
    if fullAccess.value as? String != "1" {
      fullAccess.tap()
      let localAllow = settings.alerts.buttons["Allow"]
      if localAllow.waitForExistence(timeout: 1) {
        localAllow.tap()
      } else {
        let systemAllow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
        if systemAllow.waitForExistence(timeout: 1) { systemAllow.tap() }
      }
    }

    XCTAssertEqual(fullAccess.value as? String, "1", settings.debugDescription)
    app.activate()
    app.buttons["relay-control-button"].tap()
    XCTAssertTrue(app.staticTexts["Your keyboard is ready"].waitForExistence(timeout: 5))
    app.tabBars.buttons["Settings"].tap()
    if !app.buttons["Try your keyboard"].isHittable { app.swipeUp() }
    app.buttons["Try your keyboard"].tap()
    app.textViews["keyboard-practice-text"].tap()
    if !app.buttons["keyboard-dictate-button"].exists {
      let nextKeyboard = app.buttons["Next keyboard"]
      XCTAssertTrue(nextKeyboard.waitForExistence(timeout: 3), app.debugDescription)
      nextKeyboard.press(forDuration: 1)
      let keyboard = app.staticTexts["Gemini Voice"]
      XCTAssertTrue(keyboard.waitForExistence(timeout: 3), app.debugDescription)
      keyboard.tap()
    }
    XCTAssertTrue(app.buttons["keyboard-dictate-button"].waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertTrue(app.buttons["keyboard-translate-button"].exists)
    XCTAssertTrue(app.buttons["keyboard-dictate-button"].isEnabled)
    app.textViews["keyboard-practice-text"].typeText("A little less typing. A little more living.")
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "Gemini keyboard"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  private func tapText(_ text: String, in app: XCUIApplication) {
    let element = app.cells.staticTexts[text].firstMatch
    for _ in 0..<5 {
      if element.exists && element.isHittable { element.tap(); return }
      app.swipeUp()
    }
    XCTFail("Could not find \(text). \(app.debugDescription)")
  }
}
