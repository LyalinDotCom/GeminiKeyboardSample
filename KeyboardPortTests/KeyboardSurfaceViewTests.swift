import UIKit
import XCTest

@MainActor
final class KeyboardSurfaceViewTests: XCTestCase {
  func testTypingConsumesSingleShiftAndUsesUppercaseText() throws {
    let (surface, delegate) = makeSurface()

    surface.activate(try button("keyboard-shift-key", in: surface).key.action)
    XCTAssertNotNil(findButton("keyboard-key-Q", in: surface))

    let q = try button("keyboard-key-Q", in: surface)
    surface.activate(q.key.action)

    XCTAssertEqual(delegate.insertedText, ["Q"])
    XCTAssertEqual(surface.interactionState.capitalization, .lowercase)
    XCTAssertNotNil(findButton("keyboard-key-q", in: surface))
  }

  func testSpaceAndDeleteDispatchExactlyOnceForATap() throws {
    let (surface, delegate) = makeSurface()

    surface.activate(try button("keyboard-space-key", in: surface).key.action)
    surface.activate(try button("keyboard-delete-key", in: surface).key.action)

    XCTAssertEqual(delegate.insertedText, [" "])
    XCTAssertEqual(delegate.deleteCount, 1)
  }

  func testPageKeysRenderNumbersThenSymbols() throws {
    let (surface, _) = makeSurface()

    surface.activate(try button("keyboard-page-key", in: surface).key.action)
    XCTAssertEqual(surface.interactionState.page, .numbers)
    XCTAssertNotNil(findButton("keyboard-key-1", in: surface))

    surface.activate(try button("keyboard-shift-key", in: surface).key.action)
    XCTAssertEqual(surface.interactionState.page, .symbols)
    XCTAssertNotNil(findButton("keyboard-key-[", in: surface))
  }

  func testContextChangesRebuildTheBottomRow() {
    let (surface, _) = makeSurface()

    surface.updateInputContext(
      kind: .email,
      returnKeyType: .send,
      needsInputModeSwitchKey: false
    )
    XCTAssertNotNil(findButton("keyboard-key-@", in: surface))
    XCTAssertNotNil(findButton("keyboard-space-key", in: surface))
    XCTAssertNil(findButton("keyboard-next-keyboard-key", in: surface))
    XCTAssertEqual(findButton("keyboard-return-key", in: surface)?.accessibilityLabel, "send")

    surface.updateInputContext(
      kind: .url,
      returnKeyType: .go,
      needsInputModeSwitchKey: true
    )
    XCTAssertNotNil(findButton("keyboard-key-.com", in: surface))
    XCTAssertNil(findButton("keyboard-space-key", in: surface))
    XCTAssertNotNil(findButton("keyboard-next-keyboard-key", in: surface))
  }

  func testRenderedPhoneLayoutHasNoAmbiguousSubviews() {
    let (surface, _) = makeSurface()
    surface.layoutIfNeeded()
    XCTAssertFalse(allSubviews(of: surface).contains(where: \.hasAmbiguousLayout))
  }

  func testWideLayoutKeepsTypingKeysAtAUsableSize() throws {
    let surface = KeyboardSurfaceView(frame: CGRect(x: 0, y: 0, width: 1_024, height: 260))
    surface.layoutIfNeeded()

    let q = try button("keyboard-key-q", in: surface)
    XCTAssertLessThan(q.bounds.width, 90)
    XCTAssertFalse(allSubviews(of: surface).contains(where: \.hasAmbiguousLayout))
  }

  func testTrailingAlternateCalloutStartsOnTheBaseCharacterAndStaysOnscreen() {
    let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 220))
    let key = UIView(frame: CGRect(x: 348, y: 90, width: 38, height: 44))
    let callout = KeyboardAlternateCalloutView()
    container.addSubview(key)

    let rightAnchoredOptions = ["ō", "õ", "ø", "œ", "ö", "ô", "ó", "ò", "o"]
    callout.show(
      options: rightAnchoredOptions,
      above: key,
      in: container,
      anchoredToTrailingEdge: true
    )

    XCTAssertEqual(callout.selectedText, "o")
    XCTAssertLessThanOrEqual(callout.frame.maxX, container.bounds.maxX - 4)
  }

  private func makeSurface() -> (KeyboardSurfaceView, DelegateSpy) {
    let surface = KeyboardSurfaceView(frame: CGRect(x: 0, y: 0, width: 390, height: 220))
    let delegate = DelegateSpy()
    surface.delegate = delegate
    surface.updateInputContext(
      kind: .standard,
      returnKeyType: .default,
      needsInputModeSwitchKey: true
    )
    surface.layoutIfNeeded()
    return (surface, delegate)
  }

  private func button(
    _ identifier: String,
    in surface: KeyboardSurfaceView,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws -> KeyboardKeyButton {
    try XCTUnwrap(findButton(identifier, in: surface), file: file, line: line)
  }

  private func findButton(
    _ identifier: String,
    in surface: KeyboardSurfaceView
  ) -> KeyboardKeyButton? {
    allSubviews(of: surface)
      .compactMap { $0 as? KeyboardKeyButton }
      .first { $0.accessibilityIdentifier == identifier }
  }

  private func allSubviews(of view: UIView) -> [UIView] {
    view.subviews + view.subviews.flatMap(allSubviews)
  }
}

@MainActor
private final class DelegateSpy: KeyboardSurfaceViewDelegate {
  var insertedText: [String] = []
  var deleteCount = 0
  var cursorOffsets: [Int] = []
  var clickCount = 0

  func keyboardSurface(_ surface: KeyboardSurfaceView, insertText text: String) {
    insertedText.append(text)
  }

  func keyboardSurfaceDeleteBackward(_ surface: KeyboardSurfaceView) {
    deleteCount += 1
  }

  func keyboardSurface(_ surface: KeyboardSurfaceView, adjustTextPositionBy offset: Int) {
    cursorOffsets.append(offset)
  }

  func keyboardSurfacePlayInputClick(_ surface: KeyboardSurfaceView) {
    clickCount += 1
  }

  func keyboardSurface(
    _ surface: KeyboardSurfaceView,
    showInputModeListFrom button: UIButton,
    event: UIEvent
  ) {}
}
