import UIKit

final class KeyboardButton: UIButton {
  var expandsHitTarget = true

  override var isHighlighted: Bool {
    didSet { updateInteractionAppearance(animated: true) }
  }

  override var isEnabled: Bool {
    didSet { updateInteractionAppearance(animated: false) }
  }

  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    guard expandsHitTarget else { return super.point(inside: point, with: event) }
    return bounds.insetBy(dx: -3, dy: -3).contains(point)
  }

  private func updateInteractionAppearance(animated: Bool) {
    let changes = {
      self.alpha = self.isEnabled ? (self.isHighlighted ? 0.72 : 1) : 0.38
      self.transform =
        self.isHighlighted
        ? CGAffineTransform(scaleX: 0.94, y: 0.94)
        : .identity
      self.layer.shadowOpacity = self.isHighlighted ? 0.08 : 0.22
      self.layer.shadowOffset =
        self.isHighlighted
        ? CGSize(width: 0, height: 0)
        : CGSize(width: 0, height: 1)
    }

    if animated {
      UIView.animate(
        withDuration: isHighlighted ? 0.045 : 0.09,
        delay: 0,
        options: [.allowUserInteraction, .beginFromCurrentState],
        animations: changes
      )
    } else {
      changes()
    }
  }
}
