import XCTest

@testable import GeminiVoice

final class KeyboardInteractionStateTests: XCTestCase {
  func testAllPagesProduceFourRowsWithPositiveKeyWidths() {
    var state = KeyboardInteractionState()
    assertValidLayout(state.layout(inputKind: .standard, needsInputModeSwitchKey: true))

    state.tapPage()
    assertValidLayout(state.layout(inputKind: .standard, needsInputModeSwitchKey: true))

    state.tapShift(at: 1)
    assertValidLayout(state.layout(inputKind: .standard, needsInputModeSwitchKey: true))
  }

  func testSingleShiftIsConsumedAfterText() {
    var state = KeyboardInteractionState()
    state.tapShift(at: 1)
    XCTAssertTrue(state.usesUppercaseLetters)

    state.consumeText()
    XCTAssertEqual(state.capitalization, .lowercase)
  }

  func testDoubleShiftEnablesCapsLockUntilShiftIsTappedAgain() {
    var state = KeyboardInteractionState()
    state.tapShift(at: 1)
    state.tapShift(at: 1.2)
    XCTAssertTrue(state.isCapsLocked)

    state.consumeText()
    XCTAssertTrue(state.isCapsLocked)

    state.tapShift(at: 2)
    XCTAssertEqual(state.capitalization, .lowercase)
  }

  func testPageKeysCycleLettersNumbersSymbolsAndBack() {
    var state = KeyboardInteractionState()
    state.tapPage()
    XCTAssertEqual(state.page, .numbers)
    state.tapShift(at: 1)
    XCTAssertEqual(state.page, .symbols)
    state.tapShift(at: 2)
    XCTAssertEqual(state.page, .numbers)
    state.tapPage()
    XCTAssertEqual(state.page, .letters)
  }

  func testAutomaticCapitalizationDoesNotOverrideCapsLock() {
    var state = KeyboardInteractionState()
    state.tapShift(at: 1)
    state.tapShift(at: 1.2)
    state.applyAutomaticCapitalization(.lowercase)
    XCTAssertEqual(state.capitalization, .capsLock)
  }

  func testInputKindsExposeUsefulContextKeys() {
    let state = KeyboardInteractionState()
    XCTAssertTrue(
      actions(in: state.layout(inputKind: .email, needsInputModeSwitchKey: false))
        .contains(.text("@")))
    XCTAssertTrue(
      actions(in: state.layout(inputKind: .url, needsInputModeSwitchKey: false))
        .contains(.text(".com")))
    XCTAssertFalse(
      actions(in: state.layout(inputKind: .url, needsInputModeSwitchKey: false))
        .contains(.space))
  }

  func testNextKeyboardKeyTracksSystemRequirement() {
    let state = KeyboardInteractionState()
    XCTAssertTrue(
      actions(in: state.layout(inputKind: .standard, needsInputModeSwitchKey: true))
        .contains(.nextKeyboard))
    XCTAssertFalse(
      actions(in: state.layout(inputKind: .standard, needsInputModeSwitchKey: false))
        .contains(.nextKeyboard))
  }

  func testEnglishAlternateCharactersPreserveShiftCase() {
    var state = KeyboardInteractionState()
    XCTAssertEqual(Array(state.alternateCharacters(for: "a").prefix(3)), ["a", "à", "á"])

    state.tapShift(at: 1)
    XCTAssertEqual(Array(state.alternateCharacters(for: "A").prefix(3)), ["A", "À", "Á"])
  }

  private func actions(in rows: [KeyboardLayoutRow]) -> [KeyboardKeyAction] {
    rows.flatMap(\.keys).map(\.action)
  }

  private func assertValidLayout(
    _ rows: [KeyboardLayoutRow],
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(rows.count, 4, file: file, line: line)
    XCTAssertTrue(rows.allSatisfy { !$0.keys.isEmpty }, file: file, line: line)
    XCTAssertTrue(rows.flatMap(\.keys).allSatisfy { $0.width > 0 }, file: file, line: line)
    let allActions = actions(in: rows)
    XCTAssertEqual(allActions.filter { $0 == .backspace }.count, 1, file: file, line: line)
    XCTAssertEqual(allActions.filter { $0 == .returnKey }.count, 1, file: file, line: line)
    XCTAssertEqual(allActions.filter { $0 == .page }.count, 1, file: file, line: line)
  }
}
