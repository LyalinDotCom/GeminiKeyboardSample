import UIKit

final class KeyPreviewView: UIView {
  private let label = UILabel()
  private var animationGeneration = 0

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    backgroundColor = .secondarySystemBackground
    layer.cornerRadius = 10
    layer.cornerCurve = .continuous
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.3
    layer.shadowRadius = 4
    layer.shadowOffset = CGSize(width: 0, height: 2)

    label.font = .systemFont(ofSize: 30, weight: .regular)
    label.textAlignment = .center
    label.textColor = .label
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
      label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
      label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    return nil
  }

  func show(text: String, above button: UIView, in container: UIView) {
    animationGeneration += 1
    layer.removeAllAnimations()
    label.text = text
    let keyFrame = button.convert(button.bounds, to: container)
    let width = max(52, keyFrame.width + 16)
    let height: CGFloat = 58
    let centerX = min(
      max(keyFrame.midX, width / 2 + 3),
      container.bounds.width - width / 2 - 3
    )
    frame = CGRect(
      x: centerX - width / 2,
      y: max(2, keyFrame.minY - height - 5),
      width: width,
      height: height
    )
    alpha = 0
    transform = CGAffineTransform(scaleX: 0.82, y: 0.82)
    if superview !== container {
      removeFromSuperview()
      container.addSubview(self)
    }
    container.bringSubviewToFront(self)
    UIView.animate(
      withDuration: 0.065,
      delay: 0,
      options: [.allowUserInteraction, .beginFromCurrentState]
    ) {
      self.alpha = 1
      self.transform = .identity
    }
  }

  func hide() {
    animationGeneration += 1
    let generation = animationGeneration
    UIView.animate(
      withDuration: 0.055,
      delay: 0,
      options: [.allowUserInteraction, .beginFromCurrentState]
    ) {
      self.alpha = 0
      self.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
    } completion: { _ in
      guard self.animationGeneration == generation else { return }
      self.removeFromSuperview()
    }
  }
}
