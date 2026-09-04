import Foundation

struct TranscriptHistoryItem: Codable, Identifiable, Equatable {
  let id: UUID
  let text: String
  let createdAt: Date

  init(id: UUID = UUID(), text: String, createdAt: Date) {
    self.id = id
    self.text = text
    self.createdAt = createdAt
  }
}

/// Keeps completed text durable before its only audio copy is removed.
final class TranscriptHistoryStore {
  private static let fileName = "transcript-history.json"
  private static let maximumItems = 20

  private let fileManager: FileManager
  private let directoryURL: URL?
  private let fileURL: URL?
  private(set) var items: [TranscriptHistoryItem] = []

  init(
    directoryURL: URL? = VoiceAppGroup.containerURL?.appendingPathComponent(
      "AppData",
      isDirectory: true
    ),
    fileManager: FileManager = .default
  ) {
    self.fileManager = fileManager
    self.directoryURL = directoryURL
    fileURL = directoryURL?.appendingPathComponent(Self.fileName)
    load()
  }

  @discardableResult
  func add(text: String, createdAt: Date = Date()) throws -> TranscriptHistoryItem {
    let item = TranscriptHistoryItem(text: text, createdAt: createdAt)
    let oldItems = items
    items.insert(item, at: 0)
    if items.count > Self.maximumItems {
      items.removeLast(items.count - Self.maximumItems)
    }
    do {
      try persist()
      return item
    } catch {
      items = oldItems
      throw error
    }
  }

  func clear() throws {
    let oldItems = items
    items.removeAll()
    do {
      try persist()
    } catch {
      items = oldItems
      throw error
    }
  }

  private func load() {
    guard let fileURL,
      let data = try? Data(contentsOf: fileURL),
      let decoded = try? JSONDecoder().decode([TranscriptHistoryItem].self, from: data)
    else {
      return
    }
    items = Array(decoded.sorted { $0.createdAt > $1.createdAt }.prefix(Self.maximumItems))
  }

  private func persist() throws {
    guard let directoryURL, let fileURL else {
      throw TranscriptHistoryStoreError.sharedContainerUnavailable
    }
    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try AudioCaptureEngine.protectRecordingItem(at: directoryURL, fileManager: fileManager)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(items).write(to: fileURL, options: .atomic)
    try AudioCaptureEngine.protectRecordingItem(at: fileURL, fileManager: fileManager)
  }
}

enum TranscriptHistoryStoreError: LocalizedError {
  case sharedContainerUnavailable

  var errorDescription: String? {
    "The completed transcript could not be saved securely. The recording was kept for retry."
  }
}
