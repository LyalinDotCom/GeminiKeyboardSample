import Foundation

enum GeminiLiveSpeechError: LocalizedError {
  case missingCredential
  case invalidEndpoint
  case invalidMessage
  case alreadyConnected
  case connectionClosed(String)
  case service(String)
  case emptyResult

  var errorDescription: String? {
    switch self {
    case .missingCredential:
      return "Add a Gemini credential in the Gemini Voice app."
    case .invalidEndpoint:
      return "Gemini Live could not create a secure streaming connection."
    case .invalidMessage:
      return "Gemini Live returned a response this app could not read."
    case .alreadyConnected:
      return "That Gemini Live session has already started."
    case .connectionClosed(let reason):
      return reason.isEmpty
        ? "The Gemini Live connection closed before transcription finished."
        : "The Gemini Live connection closed: \(reason)"
    case .service(let message):
      return message
    case .emptyResult:
      return "No speech was detected."
    }
  }
}

enum GeminiLiveCredential: Equatable, Sendable {
  case apiKey(String)
  case ephemeralToken(String)

  /// Where the credential travels on the WebSocket handshake. The API key is
  /// sent as the `x-goog-api-key` request header, matching the batch client,
  /// so it never appears in a URL that URLSession, proxies, or crash reports
  /// may log. The Live endpoint accepts that header directly. Ephemeral
  /// tokens keep the `access_token` query form that the constrained endpoint
  /// documents.
  enum Transport: Equatable, Sendable {
    case header(field: String, value: String)
    case query(URLQueryItem)
  }

  var transport: Transport? {
    guard let value = validatedValue else { return nil }
    switch self {
    case .apiKey:
      return .header(field: "x-goog-api-key", value: value)
    case .ephemeralToken:
      return .query(URLQueryItem(name: "access_token", value: value))
    }
  }

  var websocketMethod: String {
    switch self {
    case .apiKey:
      return "BidiGenerateContent"
    case .ephemeralToken:
      return "BidiGenerateContentConstrained"
    }
  }

  private var validatedValue: String? {
    let rawValue: String
    switch self {
    case .apiKey(let value), .ephemeralToken(let value):
      rawValue = value
    }
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty,
      value != "YOUR_GEMINI_API_KEY",
      value != "__GEMINI_API_KEY__"
    else { return nil }
    return value
  }
}

/// A resolved Live connection target. Credentials that belong in headers are
/// kept out of `url` so the URL is safe to log.
struct GeminiLiveEndpoint: Equatable, Sendable {
  let url: URL
  let headers: [String: String]
}

protocol GeminiLiveSocket: Sendable {
  func start() async
  func send(text: String) async throws
  func receive() async throws -> Data
  func close(code: URLSessionWebSocketTask.CloseCode) async
}

final class URLSessionGeminiLiveSocket: GeminiLiveSocket, @unchecked Sendable {
  private let task: URLSessionWebSocketTask

  init(endpoint: GeminiLiveEndpoint, session: URLSession = .shared) {
    var request = URLRequest(url: endpoint.url)
    // This also governs WebSocket inactivity on current URLSession
    // implementations. Keep it above the 45-second dictation ceiling;
    // setup and individual sends have their own shorter bounded waits.
    request.timeoutInterval = 90
    for (field, value) in endpoint.headers {
      request.setValue(value, forHTTPHeaderField: field)
    }
    task = session.webSocketTask(with: request)
  }

  func start() async {
    task.resume()
  }

  func send(text: String) async throws {
    try await task.send(.string(text))
  }

  func receive() async throws -> Data {
    let message = try await task.receive()
    switch message {
    case .string(let text):
      return Data(text.utf8)
    case .data(let data):
      return data
    @unknown default:
      throw GeminiLiveSpeechError.invalidMessage
    }
  }

  func close(code: URLSessionWebSocketTask.CloseCode) async {
    task.cancel(with: code, reason: nil)
  }
}

/// Streams microphone audio owned by the containing app to Gemini Live. Custom
/// keyboard extensions cannot access microphone input, even with Full Access.
