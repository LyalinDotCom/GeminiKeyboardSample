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

  func testHistoryHasNoItemCountLimit() throws {
    let store = TranscriptHistoryStore(directoryURL: directoryURL)
    for index in 0..<25 {
      try store.add(text: "Item \(index)", createdAt: Date(timeIntervalSince1970: Double(index)))
    }

    XCTAssertEqual(store.items.count, 25)
    XCTAssertEqual(store.items.first?.text, "Item 24")
    XCTAssertEqual(store.items.last?.text, "Item 0")
    XCTAssertEqual(TranscriptHistoryStore(directoryURL: directoryURL).items.count, 25)
  }

  func testRetentionRemovesOnlyExpiredTextAndPersists() throws {
    let store = TranscriptHistoryStore(directoryURL: directoryURL)
    let now = Date(timeIntervalSince1970: 5_000_000)
    try store.add(text: "Expired", createdAt: now.addingTimeInterval(-31 * 86_400))
    try store.add(text: "At boundary", createdAt: now.addingTimeInterval(-30 * 86_400))
    try store.add(text: "Recent", createdAt: now.addingTimeInterval(-2 * 86_400))
    try store.removeExpired(retentionDays: 30, now: now)
    XCTAssertEqual(store.items.map(\.text), ["Recent", "At boundary"])
    XCTAssertEqual(TranscriptHistoryStore(directoryURL: directoryURL).items, store.items)

    try store.removeExpired(retentionDays: 7, now: now)
    XCTAssertEqual(store.items.map(\.text), ["Recent"])
  }

  func testDeletingOneNoteKeepsTheOthers() throws {
    let store = TranscriptHistoryStore(directoryURL: directoryURL)
    let first = try store.add(text: "Keep me")
    let second = try store.add(text: "Delete me")
    try store.remove(id: second.id)
    XCTAssertEqual(TranscriptHistoryStore(directoryURL: directoryURL).items, [first])
  }

  func testClearPersists() throws {
    let store = TranscriptHistoryStore(directoryURL: directoryURL)
    try store.add(text: "Delete me")
    try store.clear()

    XCTAssertTrue(TranscriptHistoryStore(directoryURL: directoryURL).items.isEmpty)
  }
}
