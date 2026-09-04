import Foundation

// This project-local layout/state engine adapts concepts from KeyboardKit
// 9.9.1. That release is MIT licensed; see THIRD_PARTY_NOTICES.md. The sample
// does not link or download KeyboardKit.

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

enum KeyboardInputKind: Equatable {
  case standard
  case email
  case url
}

enum KeyboardKeyStyle: Equatable {
  case input
  case system
  case accent
}

enum KeyboardKeyAction: Equatable {
  case text(String)
  case shift
  case backspace
  case page
  case nextKeyboard
  case space
  case returnKey
}

struct KeyboardLayoutKey: Equatable {
  let action: KeyboardKeyAction
  let width: Double
  let style: KeyboardKeyStyle

  init(_ action: KeyboardKeyAction, width: Double = 1, style: KeyboardKeyStyle = .input) {
    self.action = action
    self.width = width
    self.style = style
  }
}

struct KeyboardLayoutRow: Equatable {
  let keys: [KeyboardLayoutKey]
  let leadingInset: Double
  let trailingInset: Double

  init(
    _ keys: [KeyboardLayoutKey],
    leadingInset: Double = 0,
    trailingInset: Double = 0
  ) {
    self.keys = keys
    self.leadingInset = leadingInset
    self.trailingInset = trailingInset
  }
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

  mutating func consumeText() {
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

  func layout(inputKind: KeyboardInputKind, needsInputModeSwitchKey: Bool) -> [KeyboardLayoutRow] {
    switch page {
    case .letters:
      return letterRows(inputKind: inputKind, needsInputModeSwitchKey: needsInputModeSwitchKey)
    case .numbers:
      return numberRows(inputKind: inputKind, needsInputModeSwitchKey: needsInputModeSwitchKey)
    case .symbols:
      return symbolRows(inputKind: inputKind, needsInputModeSwitchKey: needsInputModeSwitchKey)
    }
  }

  func alternateCharacters(for text: String) -> [String] {
    let values: [String]
    switch text.lowercased() {
    case "a": values = ["a", "à", "á", "â", "ä", "æ", "ã", "å", "ā"]
    case "c": values = ["c", "ç", "ć", "č"]
    case "e": values = ["e", "è", "é", "ê", "ë", "ē", "ė", "ę"]
    case "i": values = ["i", "ì", "í", "î", "ï", "ī", "į"]
    case "l": values = ["l", "ł"]
    case "n": values = ["n", "ñ", "ń"]
    case "o": values = ["o", "ò", "ó", "ô", "ö", "œ", "ø", "õ", "ō"]
    case "s": values = ["s", "ß", "ś", "š"]
    case "u": values = ["u", "ù", "ú", "û", "ü", "ū"]
    case "y": values = ["y", "ý", "ÿ"]
    case "z": values = ["z", "ž", "ź", "ż"]
    case ".": values = [".", ",", "?", "!"]
    case "-": values = ["-", "–", "—", "•"]
    case "'": values = ["'", "’", "‘", "`"]
    case "\"": values = ["\"", "”", "“", "„"]
    default: return []
    }
    return usesUppercaseLetters && text == text.uppercased()
      ? values.map { $0.uppercased() }
      : values
  }
}

private extension KeyboardInteractionState {
  func textKeys(_ text: String) -> [KeyboardLayoutKey] {
    text.map {
      let value = usesUppercaseLetters ? String($0).uppercased() : String($0)
      return KeyboardLayoutKey(.text(value))
    }
  }

  func literalKeys(_ values: [String]) -> [KeyboardLayoutKey] {
    values.map { KeyboardLayoutKey(.text($0)) }
  }

  func letterRows(
    inputKind: KeyboardInputKind,
    needsInputModeSwitchKey: Bool
  ) -> [KeyboardLayoutRow] {
    [
      KeyboardLayoutRow(textKeys("qwertyuiop")),
      KeyboardLayoutRow(textKeys("asdfghjkl"), leadingInset: 0.45, trailingInset: 0.45),
      KeyboardLayoutRow(
        [KeyboardLayoutKey(.shift, width: 1.35, style: .system)]
          + textKeys("zxcvbnm")
          + [KeyboardLayoutKey(.backspace, width: 1.35, style: .system)]
      ),
      bottomRow(inputKind: inputKind, needsInputModeSwitchKey: needsInputModeSwitchKey),
    ]
  }

  func numberRows(
    inputKind: KeyboardInputKind,
    needsInputModeSwitchKey: Bool
  ) -> [KeyboardLayoutRow] {
    [
      KeyboardLayoutRow(literalKeys(Array("1234567890").map(String.init))),
      KeyboardLayoutRow(
        literalKeys(["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""]),
        leadingInset: 0.22,
        trailingInset: 0.22
      ),
      KeyboardLayoutRow(
        [KeyboardLayoutKey(.shift, width: 1.35, style: .system)]
          + literalKeys([".", ",", "?", "!", "'", "+", "="])
          + [KeyboardLayoutKey(.backspace, width: 1.35, style: .system)]
      ),
      bottomRow(inputKind: inputKind, needsInputModeSwitchKey: needsInputModeSwitchKey),
    ]
  }

  func symbolRows(
    inputKind: KeyboardInputKind,
    needsInputModeSwitchKey: Bool
  ) -> [KeyboardLayoutRow] {
    [
      KeyboardLayoutRow(literalKeys(["[", "]", "{", "}", "#", "%", "^", "*", "+", "="])),
      KeyboardLayoutRow(
        literalKeys(["_", "\\", "|", "~", "<", ">", "€", "£", "¥"]),
        leadingInset: 0.45,
        trailingInset: 0.45
      ),
      KeyboardLayoutRow(
        [KeyboardLayoutKey(.shift, width: 1.35, style: .system)]
          + literalKeys([".", ",", "?", "!", "'", "\"", "`"])
          + [KeyboardLayoutKey(.backspace, width: 1.35, style: .system)]
      ),
      bottomRow(inputKind: inputKind, needsInputModeSwitchKey: needsInputModeSwitchKey),
    ]
  }

  func bottomRow(
    inputKind: KeyboardInputKind,
    needsInputModeSwitchKey: Bool
  ) -> KeyboardLayoutRow {
    var keys = [KeyboardLayoutKey(.page, width: 1.45, style: .system)]
    if needsInputModeSwitchKey {
      keys.append(KeyboardLayoutKey(.nextKeyboard, width: 1.1, style: .system))
    }

    switch inputKind {
    case .standard:
      keys += [
        KeyboardLayoutKey(.space, width: 4.8),
        KeyboardLayoutKey(.text("."), width: 1.05, style: .system),
      ]
    case .email:
      keys += [
        KeyboardLayoutKey(.text("@"), width: 1.05, style: .system),
        KeyboardLayoutKey(.space, width: 3.4),
        KeyboardLayoutKey(.text("."), width: 1.05, style: .system),
      ]
    case .url:
      keys += [
        KeyboardLayoutKey(.text("/"), width: 1.05, style: .system),
        KeyboardLayoutKey(.text("."), width: 1.05, style: .system),
        KeyboardLayoutKey(.text(".com"), width: 2.0),
      ]
    }
    keys.append(KeyboardLayoutKey(.returnKey, width: 1.8, style: .accent))
    return KeyboardLayoutRow(keys)
  }
}
