import SwiftUI

struct OCRButtonStyle: ButtonStyle {
  let color: Color

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.subheadline.weight(.semibold))
      .padding(.vertical, 12)
      .padding(.horizontal, 10)
      .background(color.opacity(configuration.isPressed ? 0.55 : 0.82))
      .foregroundStyle(.white)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}
