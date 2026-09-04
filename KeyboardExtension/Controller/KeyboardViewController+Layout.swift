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
    let topLetters = makeLetterRow("qwertyuiop")
    let middleLetters = makeLetterRow("asdfghjkl", inset: 17)
    let lowerLetters = makeThirdLetterRow()
    let bottom = makeBottomRow()

    typingStack.axis = .vertical
    typingStack.distribution = .fillEqually
    typingStack.spacing = 6
    [topLetters, middleLetters, lowerLetters, bottom]
      .forEach(typingStack.addArrangedSubview)

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

  func makeLetterRow(_ letters: String, inset: CGFloat = 0) -> UIView {
    let container = UIView()
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.distribution = .fillEqually
    stack.spacing = 6
    stack.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(stack)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
      stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
      stack.topAnchor.constraint(equalTo: container.topAnchor),
      stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])

    for letter in letters {
      let button = makeKey(String(letter), action: #selector(letterTapped(_:)))
      button.accessibilityLabel = String(letter)
      letterButtons.append(button)
      stack.addArrangedSubview(button)
    }
    return container
  }

  func makeThirdLetterRow() -> UIView {
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.spacing = 6

    configureSystemKey(
      shiftButton,
      systemName: "shift",
      action: #selector(shiftTapped)
    )
    shiftButton.accessibilityLabel = "Shift"
    shiftButton.widthAnchor.constraint(equalToConstant: 48).isActive = true
    stack.addArrangedSubview(shiftButton)

    let letters = UIStackView()
    letters.axis = .horizontal
    letters.distribution = .fillEqually
    letters.spacing = 6
    for letter in "zxcvbnm" {
      let button = makeKey(String(letter), action: #selector(letterTapped(_:)))
      button.accessibilityLabel = String(letter)
      letterButtons.append(button)
      letters.addArrangedSubview(button)
    }
    stack.addArrangedSubview(letters)

    configureSystemKey(deleteButton, systemName: "delete.left", action: nil)
    deleteButton.accessibilityLabel = "Delete"
    deleteButton.addTarget(self, action: #selector(deleteTouchDown), for: .touchDown)
    deleteButton.addTarget(
      self,
      action: #selector(deleteTouchEnded),
      for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit]
    )
    deleteButton.widthAnchor.constraint(equalToConstant: 48).isActive = true
    stack.addArrangedSubview(deleteButton)
    return stack
  }

  func makeBottomRow() -> UIView {
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.spacing = 6

    configureTextSystemKey(pageButton, title: "123", action: #selector(pageTapped))
    pageButton.accessibilityLabel = "Numbers and symbols"
    pageButton.widthAnchor.constraint(equalToConstant: 52).isActive = true
    stack.addArrangedSubview(pageButton)

    configureSystemKey(globeButton, systemName: "globe", action: nil)
    globeButton.addTarget(
      self,
      action: #selector(handleInputModeList(from:with:)),
      for: .allTouchEvents
    )
    globeButton.addTarget(self, action: #selector(globeTouchDown), for: .touchDown)
    globeButton.accessibilityLabel = "Next keyboard"
    let globeWidth = globeButton.widthAnchor.constraint(equalToConstant: 46)
    globeWidth.priority = .defaultHigh
    globeWidth.isActive = true
    stack.addArrangedSubview(globeButton)

    let space = makeKey("space", action: #selector(spaceTapped), darker: false)
    space.accessibilityLabel = "Space"
    stack.addArrangedSubview(space)

    let period = makeKey(".", action: #selector(symbolTapped(_:)), darker: true)
    period.accessibilityLabel = "Period"
    period.widthAnchor.constraint(equalToConstant: 42).isActive = true
    stack.addArrangedSubview(period)

    let returnButton = makeSystemKey(systemName: "return", action: #selector(returnTapped))
    returnButton.accessibilityLabel = "Return"
    returnButton.widthAnchor.constraint(equalToConstant: 66).isActive = true
    stack.addArrangedSubview(returnButton)
    return stack
  }

  func makeKey(_ title: String, action: Selector, darker: Bool = false) -> KeyboardButton {
    let button = KeyboardButton(type: .system)
    configureTextKey(button, title: title, darker: darker, action: action)
    if title != "space" {
      addCharacterPreviewEvents(to: button)
    }
    return button
  }

  func configureTextKey(
    _ button: KeyboardButton,
    title: String,
    darker: Bool,
    action: Selector?
  ) {
    var configuration = UIButton.Configuration.filled()
    configuration.title = title
    configuration.cornerStyle = .fixed
    configuration.background.cornerRadius = 6
    configuration.baseForegroundColor = Self.keyForegroundColor
    configuration.baseBackgroundColor =
      darker
      ? Self.systemKeyBackgroundColor
      : Self.letterKeyBackgroundColor
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 4, leading: 3, bottom: 4, trailing: 3)
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      attributes in
      var transformed = attributes
      transformed[AttributeScopes.UIKitAttributes.FontAttribute.self] = .systemFont(
        ofSize: title == "space" ? 15 : 20,
        weight: .regular
      )
      return transformed
    }
    button.configuration = configuration
    prepareKeyButton(button)
    if let action {
      button.addTarget(self, action: action, for: .touchUpInside)
    }
  }

  func makeSystemKey(systemName: String, action: Selector) -> KeyboardButton {
    let button = KeyboardButton(type: .system)
    configureSystemKey(button, systemName: systemName, action: action)
    return button
  }

  func configureSystemKey(
    _ button: KeyboardButton,
    systemName: String,
    action: Selector?
  ) {
    var configuration = UIButton.Configuration.filled()
    configuration.image = UIImage(systemName: systemName)
    configuration.cornerStyle = .fixed
    configuration.background.cornerRadius = 6
    configuration.baseForegroundColor = Self.keyForegroundColor
    configuration.baseBackgroundColor = Self.systemKeyBackgroundColor
    button.configuration = configuration
    prepareKeyButton(button)
    if let action {
      button.addTarget(self, action: action, for: .touchUpInside)
    }
  }

  func configureTextSystemKey(
    _ button: KeyboardButton,
    title: String,
    action: Selector
  ) {
    configureTextKey(button, title: title, darker: true, action: action)
    button.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer
    { attributes in
      var transformed = attributes
      transformed[AttributeScopes.UIKitAttributes.FontAttribute.self] = .systemFont(
        ofSize: 14,
        weight: .medium
      )
      return transformed
    }
  }

  func prepareKeyButton(_ button: KeyboardButton) {
    button.layer.shadowColor = UIColor.black.cgColor
    button.layer.shadowOpacity = 0.22
    button.layer.shadowRadius = 0
    button.layer.shadowOffset = CGSize(width: 0, height: 1)
    button.layer.cornerCurve = .continuous
    button.accessibilityTraits.insert(.keyboardKey)
    button.isExclusiveTouch = true
  }

  func addCharacterPreviewEvents(to button: KeyboardButton) {
    button.addTarget(
      self, action: #selector(characterTouchBegan(_:)), for: [.touchDown, .touchDragEnter])
    button.addTarget(
      self,
      action: #selector(characterTouchEnded),
      for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit]
    )
  }
}
