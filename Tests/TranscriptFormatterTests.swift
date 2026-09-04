import XCTest

@testable import GeminiVoice

final class TranscriptFormatterTests: XCTestCase {
  func testTranslationCleanerUnwrapsKnownJSONEnvelopesOnly() {
    XCTAssertEqual(
      TranscriptFormatter.cleanedTranslation("{\"source_Text\":\"Hello\"}"),
      "Hello"
    )
    XCTAssertEqual(
      TranscriptFormatter.cleanedTranslation("{\"translated_text\":\"Hello\"}"),
      "Hello"
    )
    XCTAssertEqual(
      TranscriptFormatter.cleanedTranslation("{\"actual\":\"dictated JSON\"}"),
      "{\"actual\":\"dictated JSON\"}"
    )
  }

  func testCleanerRemovesCommonModelWrappers() {
    XCTAssertEqual(
      TranscriptFormatter.cleaned("  Transcript: \"Meet me at five.\"  "),
      "Meet me at five."
    )
    XCTAssertEqual(
      TranscriptFormatter.cleaned("```\nA fenced transcript.\n```"),
      "A fenced transcript."
    )
  }

  func testInsertionAddsSpaceAfterExistingWord() {
    XCTAssertEqual(
      TranscriptFormatter.textForInsertion("next thought", contextBefore: "Existing"),
      " next thought"
    )
    XCTAssertEqual(
      TranscriptFormatter.textForInsertion("next thought", contextBefore: "Existing "),
      "next thought"
    )
    XCTAssertEqual(
      TranscriptFormatter.textForInsertion(".", contextBefore: "Existing"),
      "."
    )
  }
}
