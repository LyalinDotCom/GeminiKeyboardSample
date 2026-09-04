import UIKit

extension KeyboardViewController: KeyboardSurfaceViewDelegate {
  func keyboardSurface(_ surface: KeyboardSurfaceView, insertText text: String) {
    textDocumentProxy.insertText(text)
  }

  func keyboardSurfaceDeleteBackward(_ surface: KeyboardSurfaceView) {
    textDocumentProxy.deleteBackward()
  }

  func keyboardSurface(_ surface: KeyboardSurfaceView, adjustTextPositionBy offset: Int) {
    textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
  }

  func keyboardSurfacePlayInputClick(_ surface: KeyboardSurfaceView) {
    UIDevice.current.playInputClick()
  }

  func keyboardSurface(
    _ surface: KeyboardSurfaceView,
    showInputModeListFrom button: UIButton,
    event: UIEvent
  ) {
    handleInputModeList(from: button, with: event)
  }
}
