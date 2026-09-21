import UIKit

final class KeyboardBrandMarkView: UIView {
  private let iconView = UIImageView(
    image: UIImage(
      systemName: "waveform", withConfiguration: UIImage.SymbolConfiguration(weight: .semibold))
  )

  /// Invoked on a tap. The keyboard uses it to open the containing app.
  var tapHandler: (() -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)

    isUserInteractionEnabled = true
    let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
    addGestureRecognizer(tap)

    backgroundColor = .tertiarySystemFill
    layer.cornerRadius = 12
    layer.cornerCurve = .continuous
    iconView.tintColor = .systemBlue
    iconView.contentMode = .scaleAspectFit
    iconView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(iconView)
    NSLayoutConstraint.activate([
      iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
      iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
      iconView.widthAnchor.constraint(equalToConstant: 22),
      iconView.heightAnchor.constraint(equalToConstant: 22),
    ])

    isAccessibilityElement = true
    accessibilityLabel = "Gemini Voice"
    accessibilityTraits = .button
    accessibilityHint = "Opens the Gemini Voice app"
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    return nil
  }

  @objc private func handleTap() {
    tapHandler?()
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesBegan(touches, with: event)
    setPressed(true)
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesEnded(touches, with: event)
    setPressed(false)
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesCancelled(touches, with: event)
    setPressed(false)
  }

  private func setPressed(_ pressed: Bool) {
    UIView.animate(withDuration: pressed ? 0.05 : 0.15) {
      self.alpha = pressed ? 0.6 : 1
      self.transform = pressed && !UIAccessibility.isReduceMotionEnabled ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
    }
  }

  override func accessibilityActivate() -> Bool {
    tapHandler?()
    return true
  }

  func setStatus(_ text: String, accentColor: UIColor) {
    accessibilityValue = text
    iconView.tintColor = accentColor
  }
}
