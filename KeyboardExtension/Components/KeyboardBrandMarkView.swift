import UIKit

final class KeyboardBrandMarkView: UIView {
  private let gradientLayer = CAGradientLayer()
  private let iconView = UIImageView(
    image: UIImage(
      systemName: "waveform", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))
  )

  override init(frame: CGRect) {
    super.init(frame: frame)

    gradientLayer.colors = [
      UIColor.systemCyan.cgColor,
      UIColor.systemBlue.cgColor,
      UIColor.systemPurple.cgColor,
    ]
    gradientLayer.startPoint = CGPoint(x: 0, y: 0)
    gradientLayer.endPoint = CGPoint(x: 1, y: 1)
    gradientLayer.borderWidth = 1.5
    gradientLayer.borderColor = UIColor.white.withAlphaComponent(0.28).cgColor
    layer.insertSublayer(gradientLayer, at: 0)

    iconView.tintColor = .white
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
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    return nil
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    gradientLayer.frame = bounds
    gradientLayer.cornerRadius = min(bounds.width, bounds.height) * 0.32
  }

  func setStatus(_ text: String, accentColor: UIColor) {
    accessibilityValue = text
    layer.shadowColor = accentColor.cgColor
    layer.shadowOpacity = 0.24
    layer.shadowRadius = 5
    layer.shadowOffset = .zero
  }
}
