import Foundation

enum KeyboardPage: Equatable {
  case letters
  case numbers
  case symbols
}

enum KeyboardCapitalization: Equatable {
  case lowercase
  case shifted
  case capsLock
}

struct KeyboardInteractionState: Equatable {
  private static let doubleTapInterval: TimeInterval = 0.32

  private(set) var page: KeyboardPage = .letters
  private(set) var capitalization: KeyboardCapitalization = .lowercase
  private var lastShiftTapTimestamp: TimeInterval?

  var usesUppercaseLetters: Bool {
    capitalization != .lowercase
  }

  var isCapsLocked: Bool {
    capitalization == .capsLock
  }

  var titles: [String] {
    switch page {
    case .letters:
      return Array("qwertyuiopasdfghjklzxcvbnm").map(String.init)
    case .numbers:
      return Array("1234567890-/:;()$&@.,?!'[]").map(String.init)
    case .symbols:
      return [
        "[", "]", "{", "}", "#", "%", "^", "*", "+", "=",
        "_", "\\", "|", "~", "<", ">", "€", "£", "¥",
        ".", ",", "?", "!", "'", "\"", "`",
      ]
    }
  }

  mutating func tapShift(at timestamp: TimeInterval) {
    switch page {
    case .letters:
      if capitalization == .capsLock {
        capitalization = .lowercase
        lastShiftTapTimestamp = nil
        return
      }

      let isDoubleTap =
        capitalization == .shifted
        && lastShiftTapTimestamp.map {
          timestamp >= $0 && timestamp - $0 < Self.doubleTapInterval
        } ?? false

      if isDoubleTap {
        capitalization = .capsLock
        lastShiftTapTimestamp = nil
      } else {
        capitalization = capitalization == .lowercase ? .shifted : .lowercase
        lastShiftTapTimestamp = timestamp
      }
    case .numbers:
      page = .symbols
    case .symbols:
      page = .numbers
    }
  }

  mutating func tapPage() {
    page = page == .letters ? .numbers : .letters
    capitalization = .lowercase
    lastShiftTapTimestamp = nil
  }

  mutating func consumeCharacter() {
    guard page == .letters, capitalization == .shifted else { return }
    capitalization = .lowercase
    lastShiftTapTimestamp = nil
  }

  mutating func applyAutomaticCapitalization(_ requested: KeyboardCapitalization) {
    guard page == .letters, capitalization != .capsLock else { return }
    capitalization = requested
    if requested != .shifted {
      lastShiftTapTimestamp = nil
    }
  }
}
