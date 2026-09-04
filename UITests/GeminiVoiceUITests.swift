import XCTest

final class GeminiVoiceUITests: XCTestCase {
  func testLaunchShowsRelayAndSetupInstructions() {
    let app = XCUIApplication()
    app.launchEnvironment["GEMINI_VOICE_DISABLE_RELAY_AUTOSTART"] = "1"
    app.launch()

    XCTAssertTrue(app.staticTexts["Gemini Voice"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["relay-control-button"].exists)
    XCTAssertTrue(app.buttons["camera-ocr-button"].exists)
    XCTAssertTrue(app.staticTexts["One-time setup"].exists)

    let settings = app.buttons["Gemini settings"]
    if !settings.isHittable {
      app.swipeUp()
    }
    XCTAssertTrue(settings.waitForExistence(timeout: 2))
    settings.tap()

    let activeModel = app.descendants(matching: .any)["active-transcription-model"]
    XCTAssertTrue(reveal(activeModel, in: app))

    let translationStatus = app.descendants(matching: .any)["translation-always-available"]
    XCTAssertTrue(reveal(translationStatus, in: app))

    let translationPicker = app.descendants(matching: .any)["translation-language-picker"]
    XCTAssertTrue(reveal(translationPicker, in: app))

    let translationModel = app.descendants(matching: .any)["active-translation-model"]
    XCTAssertTrue(reveal(translationModel, in: app))
  }

  private func reveal(
    _ element: XCUIElement,
    in app: XCUIApplication,
    maximumSwipes: Int = 5
  ) -> Bool {
    for _ in 0..<maximumSwipes {
      if element.exists && element.isHittable {
        return true
      }
      app.swipeUp()
    }
    return element.waitForExistence(timeout: 2)
  }
}
