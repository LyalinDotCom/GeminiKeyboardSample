import AVFoundation
import Combine
import Foundation
import UIKit

extension RelayController {
  func startOCRCapture(
    preferCamera: Bool,
    requestID: String = UUID().uuidString
  ) {
    guard configuration.hasUsableAPIKey else {
      ocrMessage = GeminiTranscriptionError.missingAPIKey.localizedDescription
      return
    }

    pendingOCRRequestID = requestID
    imagePickerSource =
      preferCamera && UIImagePickerController.isSourceTypeAvailable(.camera)
      ? .camera
      : .photoLibrary
    isImagePickerPresented = true
    ocrMessage =
      imagePickerSource == .camera
      ? "Take a clear photo of the text"
      : "Choose an image containing text"
  }

  func handleDeepLink(_ url: URL) {
    if let request = RelayLaunchRequest.parse(url) {
      guard store.pendingLaunchRequest() == request else {
        if !isRelayRunning {
          setLocalStatus(
            .error,
            message: "That dictation handoff was not authorized. Try again from the keyboard.")
        }
        return
      }
      pendingLaunchRequest = request
      isKeyboardHandoffActive = true
      requiresManualKeyboardReturn = manualReturnRequired(for: request)
      let applicationState = UIApplication.shared.applicationState
      #if GEMINI_PERSONAL_DEVICE
        if applicationState == .active {
          Task { await applicationDidBecomeActive() }
        } else if applicationState == .inactive,
          AVAudioApplication.shared.recordPermission == .granted
        {
          // A keyboard URL arrives while the scene's opening animation is
          // foreground-inactive. Starting here lets capture and the return
          // request finish before Gemini needs to draw its regular UI.
          Task { await startRelay() }
        }
      #else
        if applicationState == .active {
          Task { await applicationDidBecomeActive() }
        }
      #endif
      return
    }

    guard url.scheme?.lowercased() == "geminivoice" else { return }
    guard url.host?.lowercased() == "camera" else {
      if !isRelayRunning {
        setLocalStatus(.error, message: "That keyboard dictation request expired. Try again.")
      }
      return
    }

    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let requestID =
      components?.queryItems?
      .first(where: { $0.name == "requestID" })?
      .value ?? UUID().uuidString
    startOCRCapture(preferCamera: true, requestID: requestID)
  }

  func imagePickerDidCancel() {
    isImagePickerPresented = false
    pendingOCRRequestID = nil
    ocrMessage = "OCR capture cancelled"
  }

  func imagePickerDidSelect(_ image: UIImage) {
    isImagePickerPresented = false
    guard let requestID = pendingOCRRequestID else {
      ocrMessage = "The OCR request expired. Try again."
      return
    }
    pendingOCRRequestID = nil

    guard let imageData = preparedJPEGData(from: image) else {
      ocrMessage = "That image could not be prepared for OCR."
      return
    }

    isProcessingImage = true
    ocrMessage = "Gemini is reading the image…"
    beginOCRBackgroundTaskIfNeeded()

    let apiKey = configuration.apiKey
    let model = configuration.ocrModel
    Task {
      defer {
        isProcessingImage = false
        endOCRBackgroundTaskIfNeeded()
      }

      do {
        let text = try await client.extractText(
          imageData: imageData,
          apiKey: apiKey,
          model: model
        )
        // OCR has no audio to protect, so a history failure must not block
        // the keyboard result. Go through the store so the entry survives a
        // relaunch and is not dropped when the next dictation reloads history.
        do {
          try addToHistory(text)
        } catch {
          NSLog("OCR_HISTORY_SAVE_FAILED error=%@", error.localizedDescription)
        }
        store.publishTranscript(text, requestID: requestID, kind: .ocr)
        ocrMessage = "OCR ready — return to the keyboard and tap Insert OCR"
      } catch {
        ocrMessage = error.localizedDescription
      }
    }
  }

  func requestMicrophonePermission() async -> Bool {
    await withCheckedContinuation { continuation in
      AVAudioApplication.requestRecordPermission { granted in
        continuation.resume(returning: granted)
      }
    }
  }

  func preparedJPEGData(from image: UIImage) -> Data? {
    let maximumDimension: CGFloat = 2_400
    let sourceSize = image.size
    let scale = min(1, maximumDimension / max(sourceSize.width, sourceSize.height))
    let targetSize = CGSize(
      width: max(1, sourceSize.width * scale),
      height: max(1, sourceSize.height * scale)
    )

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
    let normalized = renderer.image { _ in
      UIColor.white.setFill()
      UIRectFill(CGRect(origin: .zero, size: targetSize))
      image.draw(in: CGRect(origin: .zero, size: targetSize))
    }

    for quality in [0.9, 0.75, 0.6, 0.45] {
      if let data = normalized.jpegData(compressionQuality: quality),
        data.count <= GeminiTranscriptionClient.maximumInlineImageBytes
      {
        return data
      }
    }
    return nil
  }
}
