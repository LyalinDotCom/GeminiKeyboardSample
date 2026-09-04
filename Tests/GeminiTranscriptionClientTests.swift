import Foundation
import XCTest

@testable import GeminiVoice

private final class MockURLProtocol: URLProtocol {
  static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
  static var startLoadingCount = 0

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.startLoadingCount += 1
    guard let handler = Self.handler else {
      XCTFail("MockURLProtocol.handler was not installed")
      return
    }

    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

private func requestBodyData(_ request: URLRequest) -> Data? {
  if let body = request.httpBody {
    return body
  }
  guard let stream = request.httpBodyStream else { return nil }

  stream.open()
  defer { stream.close() }
  var result = Data()
  var buffer = [UInt8](repeating: 0, count: 4_096)
  while stream.hasBytesAvailable {
    let count = stream.read(&buffer, maxLength: buffer.count)
    guard count >= 0 else { return nil }
    if count == 0 { break }
    result.append(buffer, count: count)
  }
  return result
}

final class GeminiTranscriptionClientTests: XCTestCase {
  override func setUp() {
    super.setUp()
    MockURLProtocol.startLoadingCount = 0
  }

  override func tearDown() {
    MockURLProtocol.handler = nil
    MockURLProtocol.startLoadingCount = 0
    super.tearDown()
  }

  func testParserReadsCurrentInteractionSteps() throws {
    let data = Data(
      """
      {
        "steps": [
          {
            "type": "model_output",
            "content": [
              {"type": "text", "text": "A clear transcript."}
            ]
          }
        ]
      }
      """.utf8
    )

    XCTAssertEqual(
      try GeminiInteractionParser.transcript(from: data),
      "A clear transcript."
    )
  }

  func testParserRejectsFailedInteractionEvenWithHTTP200() throws {
    let data = Data(
      """
      {
        "status": "failed",
        "errors": [{"code": "generation_failed", "message": "The model could not finish."}],
        "steps": []
      }
      """.utf8
    )

    XCTAssertThrowsError(try GeminiInteractionParser.transcript(from: data)) { error in
      XCTAssertEqual(
        error as? GeminiTranscriptionError,
        .service(statusCode: 200, message: "The model could not finish.")
      )
    }
  }

  func testParserRejectsIncompleteInteractionInsteadOfUsingPartialText() throws {
    let data = Data(
      """
      {
        "status": "incomplete",
        "steps": [
          {"type": "model_output", "content": [{"type": "text", "text": "Partial"}]}
        ]
      }
      """.utf8
    )

    XCTAssertThrowsError(try GeminiInteractionParser.transcript(from: data)) { error in
      XCTAssertEqual(
        error as? GeminiTranscriptionError,
        .service(statusCode: 200, message: "Gemini interaction ended with status incomplete.")
      )
    }
  }

  func testClientUsesTranscribeModelWithSmartModeAndDisablesStorage() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let client = GeminiTranscriptionClient(session: session)

    MockURLProtocol.handler = { request in
      XCTAssertEqual(request.url?.path, "/v1beta/interactions")
      XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "test-key")

      let bodyData = try XCTUnwrap(requestBodyData(request))
      let body = try XCTUnwrap(
        JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
      )
      XCTAssertEqual(body["model"] as? String, "gemini-3.5-transcribe")
      XCTAssertEqual(body["store"] as? Bool, false)

      let input = try XCTUnwrap(body["input"] as? [[String: Any]])
      XCTAssertEqual(input.count, 1)
      XCTAssertEqual(input[0]["type"] as? String, "audio")
      XCTAssertEqual(input[0]["mime_type"] as? String, "audio/wav")

      let generationConfig = try XCTUnwrap(
        body["generation_config"] as? [String: Any]
      )
      let transcriptionConfig = try XCTUnwrap(
        generationConfig["transcription_config"] as? [String: Any]
      )
      XCTAssertEqual(transcriptionConfig["mode"] as? String, "smart")

      let response = try XCTUnwrap(
        HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: ["Content-Type": "application/json"]
        )
      )
      let data = Data(
        """
        {"steps":[{"type":"model_output","content":[{"type":"text","text":"Testing one two."}]}]}
        """.utf8
      )
      return (response, data)
    }

    let result = try await client.transcribe(
      audioData: Data([0, 1, 2, 3]),
      apiKey: "test-key",
      model: "gemini-3.5-transcribe"
    )
    XCTAssertEqual(result, "Testing one two.")
  }

  func testPreCancelledTranscriptionDoesNotStartNetworkLoading() async {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let client = GeminiTranscriptionClient(
      session: URLSession(configuration: configuration)
    )
    MockURLProtocol.handler = { _ in
      throw CancellationError()
    }

    let task = Task { () throws -> String in
      withUnsafeCurrentTask { currentTask in
        currentTask?.cancel()
      }
      return try await client.transcribe(
        audioData: Data([0, 1, 2, 3]),
        apiKey: "test-key",
        model: "gemini-3.5-transcribe"
      )
    }

    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch is CancellationError {
      // Expected: cancellation is observed before URLSession starts a request.
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    XCTAssertEqual(MockURLProtocol.startLoadingCount, 0)
  }

  func testRejectsOversizedAudioBeforeNetworking() async {
    let client = GeminiTranscriptionClient()
    let data = Data(repeating: 0, count: GeminiTranscriptionClient.maximumInlineAudioBytes + 1)

    do {
      _ = try await client.transcribe(
        audioData: data,
        apiKey: "test-key",
        model: "gemini-3.5-transcribe"
      )
      XCTFail("Expected an audioTooLarge error")
    } catch let error as GeminiTranscriptionError {
      guard case .audioTooLarge = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testImageOCRUsesImageInputAndParsesText() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let client = GeminiTranscriptionClient(
      session: URLSession(configuration: configuration)
    )

    MockURLProtocol.handler = { request in
      let bodyData = try XCTUnwrap(requestBodyData(request))
      let body = try XCTUnwrap(
        JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
      )
      XCTAssertEqual(body["model"] as? String, "gemini-3.7-flash")
      XCTAssertEqual(body["store"] as? Bool, false)

      let input = try XCTUnwrap(body["input"] as? [[String: Any]])
      XCTAssertEqual(input[1]["type"] as? String, "image")
      XCTAssertEqual(input[1]["mime_type"] as? String, "image/jpeg")

      let response = try XCTUnwrap(
        HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )
      )
      let data = Data(
        """
        {"steps":[{"type":"model_output","content":[{"type":"text","text":"Invoice 427"}]}]}
        """.utf8
      )
      return (response, data)
    }

    let result = try await client.extractText(
      imageData: Data([0xFF, 0xD8, 0xFF]),
      apiKey: "test-key",
      model: "gemini-3.7-flash"
    )
    XCTAssertEqual(result, "Invoice 427")
  }

  func testTranslationUsesGemini37TextInputAndLowThinking() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let client = GeminiTranscriptionClient(
      session: URLSession(configuration: configuration)
    )

    MockURLProtocol.handler = { request in
      let bodyData = try XCTUnwrap(requestBodyData(request))
      let body = try XCTUnwrap(
        JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
      )
      XCTAssertEqual(body["model"] as? String, "gemini-3.7-flash")
      XCTAssertEqual(body["store"] as? Bool, false)

      let input = try XCTUnwrap(body["input"] as? [[String: Any]])
      XCTAssertEqual(input.count, 1)
      XCTAssertEqual(input[0]["type"] as? String, "text")
      XCTAssertEqual(input[0]["text"] as? String, "Привет, как дела?")

      let systemInstruction = try XCTUnwrap(body["system_instruction"] as? String)
      XCTAssertTrue(systemInstruction.contains("English (en)"))
      XCTAssertTrue(systemInstruction.contains("Return only the translated plain text"))
      XCTAssertTrue(systemInstruction.contains("Never wrap the translation in JSON"))

      let responseFormat = try XCTUnwrap(body["response_format"] as? [String: Any])
      XCTAssertEqual(responseFormat["type"] as? String, "text")

      let generationConfig = try XCTUnwrap(
        body["generation_config"] as? [String: Any]
      )
      XCTAssertEqual(generationConfig["thinking_level"] as? String, "low")

      let response = try XCTUnwrap(
        HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )
      )
      let data = Data(
        """
        {"steps":[{"type":"model_output","content":[{"type":"text","text":"{\\"source_Text\\":\\"Hello, how are you?\\"}"}]}]}
        """.utf8
      )
      return (response, data)
    }

    let result = try await client.translate(
      text: "Привет, как дела?",
      targetLanguage: .defaultLanguage,
      apiKey: "test-key",
      model: "gemini-3.7-flash"
    )
    XCTAssertEqual(result, "Hello, how are you?")
  }
}
