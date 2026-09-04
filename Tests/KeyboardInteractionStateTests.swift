import XCTest

@testable import GeminiVoice

final class KeyboardInteractionStateTests: XCTestCase {
  func testEveryPageHasExactlyOneTitleForEachCharacterKey() {
    var state = KeyboardInteractionState()
    XCTAssertEqual(state.titles.count, 26)

    state.tapPage()
    XCTAssertEqual(state.page, .numbers)
    XCTAssertEqual(state.titles.count, 26)

    state.tapShift(at: 1)
    XCTAssertEqual(state.page, .symbols)
    XCTAssertEqual(state.titles.count, 26)
  }

  func testSingleShiftIsConsumedAfterOneCharacter() {
    var state = KeyboardInteractionState()
    state.tapShift(at: 1)
    XCTAssertTrue(state.usesUppercaseLetters)

    state.consumeCharacter()
    XCTAssertEqual(state.capitalization, .lowercase)
  }

  func testDoubleShiftEnablesCapsLockUntilShiftIsTappedAgain() {
    var state = KeyboardInteractionState()
    state.tapShift(at: 1)
    state.tapShift(at: 1.2)
    XCTAssertTrue(state.isCapsLocked)

    state.consumeCharacter()
    XCTAssertTrue(state.isCapsLocked)

    state.tapShift(at: 2)
    XCTAssertEqual(state.capitalization, .lowercase)
  }

  func testPageKeyReturnsToLettersAndClearsCapitalization() {
    var state = KeyboardInteractionState()
    state.tapShift(at: 1)
    state.tapPage()
    state.tapPage()

    XCTAssertEqual(state.page, .letters)
    XCTAssertEqual(state.capitalization, .lowercase)
  }

  func testAutomaticCapitalizationDoesNotOverrideCapsLock() {
    var state = KeyboardInteractionState()
    state.tapShift(at: 1)
    state.tapShift(at: 1.2)

    state.applyAutomaticCapitalization(.lowercase)

    XCTAssertEqual(state.capitalization, .capsLock)
  }
}
