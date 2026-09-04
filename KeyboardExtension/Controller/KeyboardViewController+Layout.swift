import CryptoKit
import Darwin
import UIKit

extension KeyboardViewController {
  func buildInterface() {
    view.backgroundColor = Self.keyboardBackgroundColor

    let height = view.heightAnchor.constraint(
      equalToConstant: preferredKeyboardHeight
    )
    height.priority = .defaultHigh
    height.isActive = true
    keyboardHeightConstraint = height

    rootStack.axis = .vertical
    rootStack.spacing = 7
    rootStack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(rootStack)

    NSLayoutConstraint.activate([
      rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
      rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
      rootStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 5),
      rootStack.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -5),
    ])

    let toolbar = makeToolbar()
    makeRecordingPanel()

    typingStack.axis = .vertical
    typingStack.translatesAutoresizingMaskIntoConstraints = false
    keyboardSurface.translatesAutoresizingMaskIntoConstraints = false
    typingStack.addArrangedSubview(keyboardSurface)

    rootStack.addArrangedSubview(toolbar)
    rootStack.addArrangedSubview(insertLatestButton)
    rootStack.addArrangedSubview(recordingPanel)
    rootStack.addArrangedSubview(typingStack)

    toolbar.heightAnchor.constraint(equalToConstant: 44).isActive = true
    insertLatestButton.heightAnchor.constraint(equalToConstant: 42).isActive = true
    insertLatestButton.isHidden = true
    recordingPanel.isHidden = true
  }

  var preferredKeyboardHeight: CGFloat {
    let contentHeight: CGFloat = traitCollection.verticalSizeClass == .compact ? 272 : 292
    let resultBannerHeight: CGFloat = insertLatestButton.isHidden ? 0 : 49
    return contentHeight + resultBannerHeight + view.safeAreaInsets.bottom
  }

  func updateKeyboardHeight() {
    let height = preferredKeyboardHeight
    guard keyboardHeightConstraint?.constant != height else { return }
    keyboardHeightConstraint?.constant = height
  }

  func makeToolbar() -> UIView {
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 7

    brandMarkView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      brandMarkView.widthAnchor.constraint(equalToConstant: 38),
      brandMarkView.heightAnchor.constraint(equalToConstant: 38),
    ])
    brandMarkView.tapHandler = { [weak self] in
      self?.openContainingAppFromBrandMark()
    }

    let spacer = UIView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    timerLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    timerLabel.textColor = .systemRed
    timerLabel.textAlignment = .right
    timerLabel.isHidden = true
    let timerWidth = timerLabel.widthAnchor.constraint(equalToConstant: 44)
    timerWidth.priority = .defaultHigh
    timerWidth.isActive = true

    processingStatusStack.axis = .horizontal
    processingStatusStack.alignment = .center
    processingStatusStack.spacing = 6
    processingStatusStack.isHidden = true
    processingStatusStack.isAccessibilityElement = true
    processingStatusStack.accessibilityIdentifier = "keyboard-processing-status"
    processingStatusStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
    processingStatusStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    processingIndicator.color = .systemCyan
    processingIndicator.hidesWhenStopped = true

    processingLabel.font = .systemFont(ofSize: 14, weight: .semibold)
    processingLabel.textColor = Self.keyForegroundColor
    processingLabel.lineBreakMode = .byTruncatingTail
    processingLabel.adjustsFontSizeToFitWidth = true
    processingLabel.minimumScaleFactor = 0.78
    processingLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    processingStatusStack.addArrangedSubview(processingIndicator)
    processingStatusStack.addArrangedSubview(processingLabel)

    stack.addArrangedSubview(brandMarkView)
    stack.addArrangedSubview(processingStatusStack)
    stack.addArrangedSubview(spacer)
    stack.addArrangedSubview(timerLabel)
    stack.addArrangedSubview(makeDictationRow())
    return stack
  }

  func makeDictationRow() -> UIStackView {
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 6

    var micConfiguration = UIButton.Configuration.filled()
    micConfiguration.cornerStyle = .capsule
    micConfiguration.baseBackgroundColor = .systemBlue
    micConfiguration.baseForegroundColor = .white
    micConfiguration.image = UIImage(systemName: "mic.fill")
    micConfiguration.contentInsets = .zero
    microphoneButton.configuration = micConfiguration
    microphoneButton.accessibilityLabel = "Start Gemini dictation"
    microphoneButton.accessibilityIdentifier = "keyboard-dictate-button"
    microphoneButton.addTarget(self, action: #selector(microphoneTapped), for: .touchUpInside)
    microphoneButton.translatesAutoresizingMaskIntoConstraints = false
    prepareActionButton(microphoneButton)

    var cancelConfiguration = UIButton.Configuration.tinted()
    cancelConfiguration.cornerStyle = .capsule
    cancelConfiguration.baseBackgroundColor = .systemRed
    cancelConfiguration.baseForegroundColor = .systemRed
    cancelConfiguration.image = UIImage(systemName: "xmark")
    cancelConfiguration.contentInsets = .zero
    cancelButton.configuration = cancelConfiguration
    cancelButton.accessibilityLabel = "Stop voice or translation and discard the result"
    cancelButton.accessibilityHint =
      "Stops an active Live stream or discards a pending recording without inserting text"
    cancelButton.accessibilityIdentifier = "keyboard-cancel-button"
    cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
    cancelButton.isEnabled = false
    prepareActionButton(cancelButton)

    var translateConfiguration = UIButton.Configuration.filled()
    translateConfiguration.cornerStyle = .capsule
    translateConfiguration.baseBackgroundColor = .systemIndigo
    translateConfiguration.baseForegroundColor = .white
    translateConfiguration.image = UIImage(systemName: "character.bubble.fill")
    translateConfiguration.contentInsets = .zero
    translateButton.configuration = translateConfiguration
    translateButton.accessibilityIdentifier = "keyboard-translate-button"
    translateButton.addTarget(self, action: #selector(translateTapped), for: .touchUpInside)
    prepareActionButton(translateButton)
    configureTranslationButton()

    var insertConfiguration = UIButton.Configuration.tinted()
    insertConfiguration.cornerStyle = .capsule
    insertConfiguration.baseBackgroundColor = .systemCyan
    insertConfiguration.baseForegroundColor = .systemCyan
    insertConfiguration.image = UIImage(systemName: "arrow.down.doc.fill")
    insertConfiguration.imagePadding = 7
    insertConfiguration.title = "Insert latest"
    insertLatestButton.configuration = insertConfiguration
    insertLatestButton.accessibilityLabel = "Insert the latest transcript"
    insertLatestButton.accessibilityIdentifier = "keyboard-insert-latest-button"
    insertLatestButton.addTarget(self, action: #selector(insertLatestTapped), for: .touchUpInside)
    insertLatestButton.translatesAutoresizingMaskIntoConstraints = false
    insertLatestButton.isHidden = true
    prepareActionButton(insertLatestButton)

    stack.addArrangedSubview(microphoneButton)
    stack.addArrangedSubview(translateButton)
    stack.addArrangedSubview(cancelButton)
    for button in [microphoneButton, translateButton, cancelButton] {
      NSLayoutConstraint.activate([
        button.widthAnchor.constraint(equalToConstant: 44),
        button.heightAnchor.constraint(equalToConstant: 44),
      ])
    }
    return stack
  }

  func makeRecordingPanel() {
    recordingPanel.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.58)
    recordingPanel.layer.cornerRadius = 20
    recordingPanel.layer.cornerCurve = .continuous
    recordingPanel.accessibilityIdentifier = "keyboard-recording-panel"

    waveformView.translatesAutoresizingMaskIntoConstraints = false
    recordingPanel.addSubview(waveformView)

    recordingTitleLabel.text = "Listening"
    recordingTitleLabel.font = .systemFont(ofSize: 18, weight: .bold)
    recordingTitleLabel.textAlignment = .center
    recordingTitleLabel.textColor = Self.keyForegroundColor
    recordingTitleLabel.translatesAutoresizingMaskIntoConstraints = false
    recordingPanel.addSubview(recordingTitleLabel)

    NSLayoutConstraint.activate([
      waveformView.leadingAnchor.constraint(equalTo: recordingPanel.leadingAnchor, constant: 18),
      waveformView.trailingAnchor.constraint(equalTo: recordingPanel.trailingAnchor, constant: -18),
      waveformView.topAnchor.constraint(equalTo: recordingPanel.topAnchor, constant: 12),
      waveformView.heightAnchor.constraint(greaterThanOrEqualToConstant: 84),
      recordingTitleLabel.topAnchor.constraint(equalTo: waveformView.bottomAnchor, constant: 4),
      recordingTitleLabel.leadingAnchor.constraint(
        equalTo: recordingPanel.leadingAnchor, constant: 16),
      recordingTitleLabel.trailingAnchor.constraint(
        equalTo: recordingPanel.trailingAnchor, constant: -16),
      recordingTitleLabel.bottomAnchor.constraint(
        lessThanOrEqualTo: recordingPanel.bottomAnchor, constant: -14),
    ])
  }

  func prepareActionButton(_ button: KeyboardButton) {
    button.isExclusiveTouch = true
    button.accessibilityTraits.insert(.button)
    button.layer.cornerCurve = .continuous
  }
}
