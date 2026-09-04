import XCTest

@testable import GeminiVoice

final class TranscriptHistoryStoreTests: XCTestCase {
  private var directoryURL: URL!

  override func setUpWithError() throws {
    directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directoryURL)
  }

  func testCompletedTranscriptSurvivesRelaunch() throws {
    let first = TranscriptHistoryStore(directoryURL: directoryURL)
    let saved = try first.add(text: "Recovered words", createdAt: Date(timeIntervalSince1970: 10))

    let reloaded = TranscriptHistoryStore(directoryURL: directoryURL)

    XCTAssertEqual(reloaded.items, [saved])
  }

  func testHistoryKeepsMostRecentTwentyItems() throws {
    let store = TranscriptHistoryStore(directoryURL: directoryURL)
    for index in 0..<25 {
      try store.add(text: "Item \(index)", createdAt: Date(timeIntervalSince1970: Double(index)))
    }

    XCTAssertEqual(store.items.count, 20)
    XCTAssertEqual(store.items.first?.text, "Item 24")
    XCTAssertEqual(store.items.last?.text, "Item 5")
  }

  func testClearPersists() throws {
    let store = TranscriptHistoryStore(directoryURL: directoryURL)
    try store.add(text: "Delete me")
    try store.clear()

    XCTAssertTrue(TranscriptHistoryStore(directoryURL: directoryURL).items.isEmpty)
  }
}
