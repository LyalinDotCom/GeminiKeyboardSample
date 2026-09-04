import Foundation

enum GeminiTranscriptionError: LocalizedError, Equatable {
  case missingAPIKey
  case audioTooLarge(bytes: Int)
  case imageTooLarge(bytes: Int)
  case invalidResponse
  case emptyTranscript
  case emptyTranslation
  case service(statusCode: Int, message: String)

  var errorDescription: String? {
    switch self {
    case .missingAPIKey:
      return "Add a Gemini API key in the Gemini Voice app."
    case .audioTooLarge:
      return "That recording is too large to transcribe inline. Try a shorter dictation."
    case .imageTooLarge:
      return "That image is too large to send. Try a smaller photo."
    case .invalidResponse:
      return "Gemini returned a response this app could not read."
    case .emptyTranscript:
      return "No speech was detected."
    case .emptyTranslation:
      return "Gemini returned an empty translation. Try the dictation again."
    case .service(_, let message):
      return message
    }
  }
}

struct GeminiInteractionResponse: Decodable {
  struct Step: Decodable {
    struct Content: Decodable {
      let type: String?
      let text: String?
    }

    let type: String?
    let content: [Content]?
  }

  let status: String?
  let steps: [Step]?
}

enum GeminiInteractionParser {
  static func text(
    from data: Data,
    emptyResultError: GeminiTranscriptionError = .emptyTranscript
  ) throws -> String {
    let root: [String: Any]
    do {
      guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw GeminiTranscriptionError.invalidResponse
      }
      root = object
    } catch let error as GeminiTranscriptionError {
      throw error
    } catch {
      throw GeminiTranscriptionError.invalidResponse
    }

    let status = root["status"] as? String
    if let status, status != "completed" {
      let serviceMessage =
        interactionErrorMessage(in: root)
        ?? "Gemini interaction ended with status \(status.replacingOccurrences(of: "_", with: " "))."
      throw GeminiTranscriptionError.service(statusCode: 200, message: serviceMessage)
    }
    if let serviceMessage = interactionErrorMessage(in: root) {
      throw GeminiTranscriptionError.service(statusCode: 200, message: serviceMessage)
    }

    let response: GeminiInteractionResponse
    do {
      response = try JSONDecoder().decode(GeminiInteractionResponse.self, from: data)
    } catch {
      throw GeminiTranscriptionError.invalidResponse
    }

    var texts: [String] = []
    for step in response.steps ?? [] {
      guard step.type == nil || step.type == "model_output" else { continue }
      for content in step.content ?? [] {
        guard content.type == nil || content.type == "text",
          let text = content.text
        else { continue }
        texts.append(text)
      }
    }

    let transcript = TranscriptFormatter.cleaned(texts.joined())
    guard !transcript.isEmpty else {
      throw emptyResultError
    }
    return transcript
  }

  static func transcript(from data: Data) throws -> String {
    try text(from: data)
  }

  private static func interactionErrorMessage(in root: [String: Any]) -> String? {
    if let error = root["error"] as? [String: Any],
      let message = error["message"] as? String,
      !message.isEmpty
    {
      return message
    }
    if let errors = root["errors"] as? [[String: Any]] {
      let messages = errors.compactMap { error -> String? in
        guard let message = error["message"] as? String, !message.isEmpty else {
          return nil
        }
        return message
      }
      if !messages.isEmpty {
        return messages.joined(separator: "\n")
      }
    }
    return nil
  }
}
