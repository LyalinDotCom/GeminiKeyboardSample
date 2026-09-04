import UIKit

final class LiveWaveformView: UIView {
  private let bars: [UIView]
  private let multipliers: [CGFloat] = [0.38, 0.58, 0.82, 0.66, 1, 0.72, 0.88, 0.54, 0.34]
  private var heightConstraints: [NSLayoutConstraint] = []

  override init(frame: CGRect) {
    bars = multipliers.map { _ in UIView() }
    super.init(frame: frame)

    let stack = UIStackView(arrangedSubviews: bars)
    stack.axis = .horizontal
    stack.alignment = .center
    stack.distribution = .equalSpacing
    stack.spacing = 7
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)

    for bar in bars {
      bar.backgroundColor = .systemCyan
      bar.layer.cornerRadius = 3.5
      bar.translatesAutoresizingMaskIntoConstraints = false
      bar.widthAnchor.constraint(equalToConstant: 7).isActive = true
      let height = bar.heightAnchor.constraint(equalToConstant: 12)
      height.isActive = true
      heightConstraints.append(height)
    }

    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
      stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    return nil
  }

  func setLevel(_ level: CGFloat, active: Bool) {
    let clamped = min(max(level, 0), 1)
    for (index, constraint) in heightConstraints.enumerated() {
      let idleMotion = active ? CGFloat((index % 3) + 1) * 2 : 0
      constraint.constant = 12 + idleMotion + (62 * clamped * multipliers[index])
      bars[index].backgroundColor = active ? .systemCyan : .systemGray3
    }
    UIView.animate(
      withDuration: 0.14,
      delay: 0,
      options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]
    ) {
      self.layoutIfNeeded()
    }
  }
}
