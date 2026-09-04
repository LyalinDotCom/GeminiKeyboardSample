import CryptoKit
import Darwin
import UIKit

extension KeyboardViewController {
  func originatingApplicationBundleIdentifierForHandoff(
    capturedHostProcessIdentifier: Int32?,
    persistUnknown: Bool
  ) -> String? {
    #if GEMINI_PERSONAL_DEVICE
      if let hostBundleIdentifier = hostBundleIdentifierFromViewServices() {
        NSLog(
          "GV_HANDOFF_HOST_LOOKUP resolved-via-view-services bundle=%@",
          hostBundleIdentifier
        )
        return recordPersonalResolvedHost(
          hostBundleIdentifier,
          route: "view-services"
        )
      }

      if let signingIdentifier = hostSigningIdentifierFromAuditToken(),
        signingIdentifier != Bundle.main.bundleIdentifier
      {
        NSLog(
          "GV_HANDOFF_HOST_LOOKUP resolved-via-audit-token bundle=%@",
          signingIdentifier
        )
        return recordPersonalResolvedHost(
          signingIdentifier,
          route: "audit-token"
        )
      }

      guard let hostProcessIdentifier = capturedHostProcessIdentifier else {
        return personalHostLookupUnavailable(
          reason: "host-process-unavailable",
          persist: persistUnknown
        )
      }

      if let springBoardHost = hostBundleIdentifierFromSpringBoard(
        processIdentifier: hostProcessIdentifier
      ) {
        NSLog(
          "GV_HANDOFF_HOST_LOOKUP resolved-via-%@ bundle=%@",
          springBoardHost.route,
          springBoardHost.bundleIdentifier
        )
        return recordPersonalResolvedHost(
          springBoardHost.bundleIdentifier,
          route: springBoardHost.route
        )
      }

      guard let processHandle = dlopen(nil, RTLD_LAZY) else {
        NSLog("GV_HANDOFF_HOST_LOOKUP process-handle-unavailable")
        return personalHostLookupUnavailable(
          reason: "process-handle-unavailable",
          persist: persistUnknown
        )
      }
      defer { dlclose(processHandle) }

      if let processName = hostProcessName(
        for: hostProcessIdentifier,
        processHandle: processHandle
      ),
        let messagesBundleIdentifier = PersonalDeviceHostFallback.destination(
          resolvedBundleIdentifier: nil,
          hostProcessName: processName
        )
      {
        NSLog(
          "GV_HANDOFF_HOST_LOOKUP resolved-via-process-name-messages bundle=%@",
          messagesBundleIdentifier
        )
        return recordPersonalResolvedHost(
          messagesBundleIdentifier,
          route: "process-name-messages"
        )
      }

      let processPathSymbol = ["proc", "pidpath"].joined(separator: "_")
      guard let symbol = dlsym(processHandle, processPathSymbol) else {
        NSLog("GV_HANDOFF_HOST_LOOKUP process-path-unavailable")
        return personalHostLookupUnavailable(
          reason: "process-path-unavailable",
          persist: persistUnknown
        )
      }
      typealias ProcessPath =
        @convention(c) (
          Int32,
          UnsafeMutableRawPointer,
          UInt32
        ) -> Int32
      let processPath = unsafeBitCast(symbol, to: ProcessPath.self)
      var pathBuffer = [CChar](repeating: 0, count: 4_096)
      let pathLength = pathBuffer.withUnsafeMutableBytes { bytes in
        guard let baseAddress = bytes.baseAddress else { return Int32(0) }
        return processPath(
          hostProcessIdentifier,
          baseAddress,
          UInt32(bytes.count)
        )
      }
      guard pathLength > 0,
        let executablePath = pathBuffer.withUnsafeBufferPointer({ buffer in
          buffer.baseAddress.flatMap(String.init(validatingUTF8:))
        })
      else {
        NSLog(
          "GV_HANDOFF_HOST_LOOKUP process-path-failed pid=%d",
          hostProcessIdentifier
        )
        return personalHostLookupUnavailable(
          reason: "process-path-failed",
          persist: persistUnknown
        )
      }

      var candidateURL = URL(fileURLWithPath: executablePath).deletingLastPathComponent()
      while candidateURL.path != "/" {
        if candidateURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
          let bundleIdentifier = Bundle(url: candidateURL)?.bundleIdentifier,
          bundleIdentifier != Bundle.main.bundleIdentifier
        {
          NSLog(
            "GV_HANDOFF_HOST_LOOKUP resolved pid=%d bundle=%@",
            hostProcessIdentifier,
            bundleIdentifier
          )
          return recordPersonalResolvedHost(
            bundleIdentifier,
            route: "process-path"
          )
        }
        candidateURL.deleteLastPathComponent()
      }
      NSLog(
        "GV_HANDOFF_HOST_LOOKUP bundle-unavailable pid=%d",
        hostProcessIdentifier
      )
      return personalHostLookupUnavailable(
        reason: "bundle-unavailable",
        persist: persistUnknown
      )
    #else
      return nil
    #endif
  }
}
