import Darwin
import Foundation

enum VoiceAppGroup {
  static var identifier: String {
    let configured =
      Bundle.main.object(
        forInfoDictionaryKey: "GeminiVoiceAppGroupIdentifier"
      ) as? String
    return configured?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
      ?? "group.com.example.GeminiVoiceSample"
  }

  static var containerURL: URL? {
    FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: identifier
    )
  }
}

extension String {
  fileprivate var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}

enum RelayStatus: String, Codable {
  case offline
  case idle
  case recording
  case transcribing
  case error

  var isBusy: Bool {
    self == .recording || self == .transcribing
  }
}

enum RelayCommand: String, Codable {
  case start
  case stop
  case cancel
  case cancelRecordingFromLiveActivity
  case shutdownRelayFromLiveActivity

  var discardsRecording: Bool {
    self == .cancel || self == .cancelRecordingFromLiveActivity
  }
}

enum RelayDictationAction: String, Codable {
  case transcribe
  case translate
}

struct RelayLaunchRequest: Equatable {
  static let defaultMaximumAge: TimeInterval = 30

  let requestID: String
  let dictationAction: RelayDictationAction
  let createdAt: Date
  let originatingApplicationBundleIdentifier: String?

  init(
    requestID: String,
    dictationAction: RelayDictationAction,
    createdAt: Date,
    originatingApplicationBundleIdentifier: String? = nil
  ) {
    self.requestID = requestID
    self.dictationAction = dictationAction
    self.createdAt = createdAt
    self.originatingApplicationBundleIdentifier = originatingApplicationBundleIdentifier
  }

  func makeURL() -> URL? {
    guard Self.isValidRequestID(requestID),
      createdAt.timeIntervalSince1970.isFinite
    else {
      return nil
    }

    var components = URLComponents()
    components.scheme = "geminivoice"
    components.host = "dictate"
    var queryItems = [
      URLQueryItem(name: "requestID", value: requestID),
      URLQueryItem(name: "action", value: dictationAction.rawValue),
      URLQueryItem(name: "createdAt", value: String(createdAt.timeIntervalSince1970)),
    ]
    if let originatingApplicationBundleIdentifier {
      guard Self.isValidBundleIdentifier(originatingApplicationBundleIdentifier) else {
        return nil
      }
      queryItems.append(
        URLQueryItem(
          name: "originBundleID",
          value: originatingApplicationBundleIdentifier
        )
      )
    }
    components.queryItems = queryItems
    return components.url
  }

  static func parse(
    _ url: URL,
    now: Date = Date(),
    maximumAge: TimeInterval = RelayLaunchRequest.defaultMaximumAge
  ) -> RelayLaunchRequest? {
    guard maximumAge.isFinite, maximumAge >= 0,
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.scheme?.lowercased() == "geminivoice",
      components.host?.lowercased() == "dictate",
      components.path.isEmpty,
      components.user == nil,
      components.password == nil,
      components.port == nil,
      components.fragment == nil,
      let queryItems = components.queryItems,
      queryItems.count == 3 || queryItems.count == 4,
      Set(queryItems.map(\.name)).count == queryItems.count,
      Set(queryItems.map(\.name)).isSubset(
        of: ["requestID", "action", "createdAt", "originBundleID"]
      ),
      Set(queryItems.map(\.name)).isSuperset(
        of: ["requestID", "action", "createdAt"]
      )
    else {
      return nil
    }

    let values = Dictionary(
      uniqueKeysWithValues: queryItems.compactMap { item in
        item.value.map { (item.name, $0) }
      })
    guard values.count == queryItems.count,
      let requestID = values["requestID"],
      isValidRequestID(requestID),
      let rawAction = values["action"],
      let dictationAction = RelayDictationAction(rawValue: rawAction),
      let rawCreatedAt = values["createdAt"],
      let timestamp = TimeInterval(rawCreatedAt),
      timestamp.isFinite,
      values["originBundleID"].map(Self.isValidBundleIdentifier) ?? true
    else {
      return nil
    }

    let createdAt = Date(timeIntervalSince1970: timestamp)
    let age = now.timeIntervalSince(createdAt)
    guard age.isFinite, age >= 0, age <= maximumAge else {
      return nil
    }

    return RelayLaunchRequest(
      requestID: requestID,
      dictationAction: dictationAction,
      createdAt: createdAt,
      originatingApplicationBundleIdentifier: values["originBundleID"]
    )
  }

  var hasValidStoredFields: Bool {
    Self.isValidRequestID(requestID)
      && createdAt.timeIntervalSince1970.isFinite
      && (originatingApplicationBundleIdentifier.map(Self.isValidBundleIdentifier) ?? true)
  }

  func exactlyMatches(_ other: RelayLaunchRequest) -> Bool {
    requestID.caseInsensitiveCompare(other.requestID) == .orderedSame
      && dictationAction == other.dictationAction
      && createdAt.timeIntervalSince1970 == other.createdAt.timeIntervalSince1970
      && originatingApplicationBundleIdentifier
        == other.originatingApplicationBundleIdentifier
  }

  fileprivate static func isValidRequestID(_ requestID: String) -> Bool {
    guard let uuid = UUID(uuidString: requestID) else { return false }
    return uuid.uuidString.caseInsensitiveCompare(requestID) == .orderedSame
  }

  static func isValidBundleIdentifier(_ identifier: String) -> Bool {
    guard (3...255).contains(identifier.utf8.count),
      identifier.contains("."),
      identifier.first != ".",
      identifier.last != "."
    else {
      return false
    }
    return identifier.unicodeScalars.allSatisfy {
      CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-"
    }
  }
}

enum RelayHostReturnDecision: Equatable {
  case automatic(bundleIdentifier: String)
  case manual
}

enum RelayHostReturnPolicy {
  /// A missing or untrusted origin can only produce a manual return. This
  /// policy intentionally has no default application destination.
  static func decision(
    originatingApplicationBundleIdentifier: String?,
    containingApplicationBundleIdentifier: String?
  ) -> RelayHostReturnDecision {
    guard let originatingApplicationBundleIdentifier,
      RelayLaunchRequest.isValidBundleIdentifier(
        originatingApplicationBundleIdentifier
      ),
      let containingApplicationBundleIdentifier,
      originatingApplicationBundleIdentifier
        != containingApplicationBundleIdentifier
    else {
      return .manual
    }
    return .automatic(
      bundleIdentifier: originatingApplicationBundleIdentifier
    )
  }
}

#if GEMINI_PERSONAL_DEVICE
  /// Personal-device Debug builds may use the Messages destination only after a
  /// strict host-process match. An unknown host remains unknown and must use the
  /// manual swipe-back path.
  enum PersonalDeviceHostFallback {
    static let messagesBundleIdentifier = ["com", "apple", "MobileSMS"]
      .joined(separator: ".")
    static let messagesProcessName = ["Mobile", "SMS"].joined()

    static func destination(
      resolvedBundleIdentifier: String?,
      hostProcessName: String?
    ) -> String? {
      if let resolvedBundleIdentifier,
        RelayLaunchRequest.isValidBundleIdentifier(
          resolvedBundleIdentifier
        )
      {
        return resolvedBundleIdentifier
      }

      guard hostProcessName == messagesProcessName else { return nil }
      return messagesBundleIdentifier
    }

    /// Accept a keyboard-arbiter source only when it belongs to the exact host
    /// PID captured before the containing app is opened. Stale state from a
    /// different client can never become an automatic-return destination.
    static func exactArbiterDestination(
      capturedHostProcessIdentifier: Int32,
      observedProcessIdentifier: Int32,
      sourceBundleIdentifier: String?
    ) -> String? {
      guard capturedHostProcessIdentifier > 1,
        observedProcessIdentifier == capturedHostProcessIdentifier,
        let sourceBundleIdentifier,
        RelayLaunchRequest.isValidBundleIdentifier(
          sourceBundleIdentifier
        )
      else {
        return nil
      }
      return sourceBundleIdentifier
    }
  }
#endif
