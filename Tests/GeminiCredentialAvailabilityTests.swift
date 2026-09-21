import XCTest

@testable import GeminiVoice

final class GeminiCredentialAvailabilityTests: XCTestCase {
  func testRejectsMissingAndPlaceholderCredentials() {
    XCTAssertFalse(GeminiCredentialAvailability.isUsable(""))
    XCTAssertFalse(GeminiCredentialAvailability.isUsable("   \n"))
    XCTAssertFalse(GeminiCredentialAvailability.isUsable("YOUR_GEMINI_API_KEY"))
    XCTAssertFalse(GeminiCredentialAvailability.isUsable("__GEMINI_API_KEY__"))
  }

  func testAcceptsConfiguredCredentialAfterTrimmingWhitespace() {
    XCTAssertTrue(
      GeminiCredentialAvailability.isUsable("  test-configured-key  ")
    )
  }
}
