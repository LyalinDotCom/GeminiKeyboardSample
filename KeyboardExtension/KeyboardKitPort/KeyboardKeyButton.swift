import UIKit

// Adapted for this sample from KeyboardKit 9.9.1 interaction and styling
// concepts. Copyright (c) 2016-2025 Daniel Saidi. MIT license; see
// THIRD_PARTY_NOTICES.md.

final class KeyboardKeyButton: UIButton {
  let key: KeyboardLayoutKey

  init(key: KeyboardLayoutKey) {
    self.key = key
    super.init(frame: .zero)
    isExclusiveTouch = true
    accessibilityTraits.insert(.keyboardKey)
    layer.cornerCurve = .continuous
    layer.cornerRadius = 6
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowRadius = 0
    layer.shadowOffset = CGSize(width: 0, height: 1)
    setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    setContentHuggingPriority(.defaultLow, for: .horizontal)
    updateAppearance(animated: false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override var isHighlighted: Bool {
    didSet { updateAppearance(animated: true) }
  }

  override var isEnabled: Bool {
    didSet { updateAppearance(animated: false) }
  }

  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    bounds.insetBy(dx: -2, dy: -3).contains(point)
  }

  func configure(title: String?, systemImage: String?, accessibilityLabel: String) {
    var configuration = UIButton.Configuration.filled()
    configuration.title = title
    configuration.image = systemImage.flatMap(UIImage.init(systemName:))
    configuration.imagePlacement = .leading
    configuration.imagePadding = 3
    configuration.cornerStyle = .fixed
    configuration.background.cornerRadius = 6
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 2,
      leading: 2,
      bottom: 2,
      trailing: 2
    )
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      attributes in
      var transformed = attributes
      transformed[AttributeScopes.UIKitAttributes.FontAttribute.self] = .systemFont(
        ofSize: self.key.style == .input ? 21 : 14,
        weight: self.key.style == .accent ? .semibold : .regular
      )
      return transformed
    }
    self.configuration = configuration
    self.accessibilityLabel = accessibilityLabel
    updateAppearance(animated: false)
  }

  private func updateAppearance(animated: Bool) {
    let changes = {
      self.configuration?.baseForegroundColor = Self.foregroundColor
      self.configuration?.baseBackgroundColor = Self.backgroundColor(for: self.key.style)
      self.alpha = self.isEnabled ? (self.isHighlighted ? 0.72 : 1) : 0.38
      self.transform = self.isHighlighted
        ? CGAffineTransform(scaleX: 0.96, y: 0.96)
        : .identity
      self.layer.shadowOpacity = self.isHighlighted ? 0.04 : 0.22
      self.layer.shadowOffset = self.isHighlighted ? .zero : CGSize(width: 0, height: 1)
    }
    if animated {
      UIView.animate(
        withDuration: isHighlighted ? 0.035 : 0.08,
        delay: 0,
        options: [.allowUserInteraction, .beginFromCurrentState],
        animations: changes
      )
    } else {
      changes()
    }
  }

  private static let foregroundColor = UIColor { traits in
    traits.userInterfaceStyle == .dark ? .white : .black
  }

  private static func backgroundColor(for style: KeyboardKeyStyle) -> UIColor {
    switch style {
    case .input:
      return UIColor { traits in
        traits.userInterfaceStyle == .dark
          ? UIColor(red: 0.39, green: 0.40, blue: 0.43, alpha: 1)
          : .white
      }
    case .system:
      return UIColor { traits in
        traits.userInterfaceStyle == .dark
          ? UIColor(red: 0.24, green: 0.25, blue: 0.28, alpha: 1)
          : UIColor(red: 0.67, green: 0.70, blue: 0.74, alpha: 1)
      }
    case .accent:
      return .systemBlue
    }
  }
}
