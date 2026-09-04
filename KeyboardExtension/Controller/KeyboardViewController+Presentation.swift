import CryptoKit
import Darwin
import UIKit

extension KeyboardViewController {
  func configureMicrophone(title: String, image: String, color: UIColor) {
    var configuration = microphoneButton.configuration
    configuration?.title = nil
    configuration?.image = UIImage(systemName: image)
    configuration?.baseBackgroundColor = color
    microphoneButton.configuration = configuration
    switch title {
    case "Finish":
      microphoneButton.accessibilityLabel = "Finish dictation and insert text"
      microphoneButton.accessibilityHint = "Ends this recording and sends it for transcription"
    case "Transcribing":
      microphoneButton.accessibilityLabel = "Transcribing with Gemini"
      microphoneButton.accessibilityHint = nil
    case "Try again":
      microphoneButton.accessibilityLabel = "Start Gemini dictation again"
      microphoneButton.accessibilityHint = nil
    case "Open & dictate":
      microphoneButton.accessibilityLabel = "Open Gemini Voice and start dictation"
      microphoneButton.accessibilityHint = nil
    case "Opening…":
      microphoneButton.accessibilityLabel = "Opening Gemini Voice"
      microphoneButton.accessibilityHint = nil
    case "Starting…":
      microphoneButton.accessibilityLabel = "Starting Gemini dictation"
      microphoneButton.accessibilityHint = nil
    default:
      microphoneButton.accessibilityLabel = "Start Gemini dictation"
      microphoneButton.accessibilityHint = nil
    }
  }

  var keyboardTranslationEnabled: Bool {
    true
  }

  var keyboardTranslationTarget: TranslationLanguage {
    let code =
      sharedPreferences.string(forKey: TranslationPreferenceKey.targetCode)
      ?? TranslationLanguage.defaultLanguage.code
    return TranslationLanguage.language(for: code)
  }

  func configureTranslationButton(
    title: String? = nil,
    image: String = "character.bubble.fill",
    color: UIColor = .systemIndigo
  ) {
    let target = keyboardTranslationTarget
    var configuration = translateButton.configuration
    configuration?.title = nil
    configuration?.image = UIImage(systemName: image)
    configuration?.baseBackgroundColor = color
    translateButton.configuration = configuration
    switch title {
    case "Finish":
      translateButton.accessibilityLabel = "Finish translation and insert text"
      translateButton.accessibilityHint =
        "Ends this recording and sends it for translation to \(target.name)"
    case "…":
      translateButton.accessibilityLabel = "Translating with Gemini"
      translateButton.accessibilityHint = nil
    default:
      translateButton.accessibilityLabel = "Start dictation and translate to \(target.name)"
      translateButton.accessibilityHint = nil
    }
    translateButton.accessibilityValue = target.name
  }

  func updateActionVisibility() {
    microphoneButton.isHidden = false
    translateButton.isHidden = false
    cancelButton.isHidden = false
  }

  func updateCancelAccessibility() {
    switch mode {
    case .openingHost:
      cancelButton.accessibilityLabel = "Cancel opening Gemini Voice"
      cancelButton.accessibilityHint = "Cancels this dictation request before recording starts"
    case .recording:
      if activeDictationAction == .translate {
        cancelButton.accessibilityLabel = "Cancel translation"
      } else {
        cancelButton.accessibilityLabel = "Cancel dictation"
      }
      cancelButton.accessibilityHint = "Stops and discards this recording without inserting text"
    case .cancelling:
      cancelButton.accessibilityLabel = "Cancelling"
      cancelButton.accessibilityHint = nil
    case .idle, .transcribing, .resultWaiting:
      cancelButton.accessibilityLabel = "Cancel"
      cancelButton.accessibilityHint = nil
    }
  }

  func updateRecordingPresentation(with snapshot: RelaySnapshot) {
    let isRecording = mode == .recording
    recordingPanel.isHidden = !isRecording
    typingStack.isHidden = isRecording

    guard isRecording else {
      waveformView.setLevel(0, active: false)
      return
    }

    let levelIsFresh =
      snapshot.audioLevelUpdatedAt.map {
        Date().timeIntervalSince($0) >= 0 && Date().timeIntervalSince($0) < 0.8
      } ?? false
    waveformView.setLevel(
      levelIsFresh ? CGFloat(snapshot.audioLevel) : 0,
      active: true
    )
    recordingTitleLabel.text =
      activeDictationAction == .translate
      ? "Listening to translate"
      : "Listening"
  }

  func updateProcessingPresentation(with snapshot: RelaySnapshot) {
    if mode == .transcribing {
      let label =
        activeDictationAction == .translate
        ? "Translating…"
        : "Transcribing…"
      processingLabel.text = label
      processingLabel.textColor = Self.keyForegroundColor
      processingStatusStack.accessibilityLabel = label
      processingStatusStack.isHidden = false
      processingIndicator.color = .systemCyan
      processingIndicator.startAnimating()
      return
    }

    if snapshot.status == .error {
      processingIndicator.stopAnimating()
      processingLabel.text = snapshot.message
      processingLabel.textColor = .systemOrange
      processingStatusStack.accessibilityLabel = snapshot.message
      processingStatusStack.isHidden = false
      return
    }

    processingIndicator.stopAnimating()
    processingLabel.textColor = Self.keyForegroundColor
    processingStatusStack.isHidden = true
    processingStatusStack.accessibilityLabel = nil
  }

  func setStatus(_ text: String, color: UIColor) {
    brandMarkView.setStatus(text, accentColor: color)
  }
}
