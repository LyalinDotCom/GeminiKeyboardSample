import UIKit

// Adapted for this sample from KeyboardKit 9.9.1 callout concepts.
// Copyright (c) 2016-2025 Daniel Saidi. MIT license; see THIRD_PARTY_NOTICES.md.

final class KeyboardInputCalloutView: UIView {
  private let label = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    backgroundColor = .secondarySystemBackground
    layer.cornerRadius = 10
    layer.cornerCurve = .continuous
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.28
    layer.shadowRadius = 4
    layer.shadowOffset = CGSize(width: 0, height: 2)

    label.font = .systemFont(ofSize: 30)
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
    nil
  }

  func show(text: String, above key: UIView, in container: UIView) {
    label.text = text
    let keyFrame = key.convert(key.bounds, to: container)
    let width = max(52, keyFrame.width + 16)
    let centerX = min(max(keyFrame.midX, width / 2 + 3), container.bounds.width - width / 2 - 3)
    frame = CGRect(
      x: centerX - width / 2,
      y: max(2, keyFrame.minY - 63),
      width: width,
      height: 58
    )
    if superview !== container {
      removeFromSuperview()
      container.addSubview(self)
    }
    container.bringSubviewToFront(self)
    alpha = 1
  }

  func hide() {
    removeFromSuperview()
  }
}

final class KeyboardAlternateCalloutView: UIView {
  private let stack = UIStackView()
  private var labels: [UILabel] = []
  private(set) var selectedText: String?

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .secondarySystemBackground
    layer.cornerRadius = 10
    layer.cornerCurve = .continuous
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.3
    layer.shadowRadius = 6
    layer.shadowOffset = CGSize(width: 0, height: 2)

    stack.axis = .horizontal
    stack.distribution = .fillEqually
    stack.spacing = 2
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 5),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func show(
    options: [String],
    above key: UIView,
    in container: UIView,
    anchoredToTrailingEdge: Bool
  ) {
    stack.arrangedSubviews.forEach {
      stack.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    labels = options.map { option in
      let label = UILabel()
      label.text = option
      label.textAlignment = .center
      label.textColor = .label
      label.font = .systemFont(ofSize: 22)
      label.layer.cornerRadius = 7
      label.layer.cornerCurve = .continuous
      label.clipsToBounds = true
      stack.addArrangedSubview(label)
      return label
    }
    let keyFrame = key.convert(key.bounds, to: container)
    let width = min(container.bounds.width - 8, max(58, CGFloat(options.count) * 36 + 10))
    let idealX = anchoredToTrailingEdge ? keyFrame.maxX - width : keyFrame.minX
    let x = min(max(idealX, 4), container.bounds.width - width - 4)
    frame = CGRect(
      x: x,
      y: max(2, keyFrame.minY - 57),
      width: width,
      height: 52
    )
    if superview !== container {
      removeFromSuperview()
      container.addSubview(self)
    }
    container.bringSubviewToFront(self)
    select(index: anchoredToTrailingEdge ? options.count - 1 : 0, options: options)
  }

  func updateSelection(at point: CGPoint, options: [String]) {
    guard !options.isEmpty, bounds.width > 0 else { return }
    let localPoint = convert(point, from: superview)
    let itemWidth = bounds.width / CGFloat(options.count)
    let index = min(options.count - 1, max(0, Int(localPoint.x / itemWidth)))
    select(index: index, options: options)
  }

  func hide() {
    selectedText = nil
    removeFromSuperview()
  }

  private func select(index: Int, options: [String]) {
    guard options.indices.contains(index) else { return }
    selectedText = options[index]
    for (labelIndex, label) in labels.enumerated() {
      label.backgroundColor = labelIndex == index ? .systemBlue : .clear
      label.textColor = labelIndex == index ? .white : .label
    }
  }
}
