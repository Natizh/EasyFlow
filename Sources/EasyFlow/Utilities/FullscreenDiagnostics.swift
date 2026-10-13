import AppKit
import CoreGraphics
import OSLog

/// Event-only development diagnostics. Public macOS APIs do not expose a
/// stable numeric Space ID, so the epoch counts observed Space transitions.
@MainActor
enum FullscreenDiagnostics {
  static let preferenceKey = "recordFullscreenDiagnostics"
  private static let logger = Logger(
    subsystem: "io.github.natizh.easyflow", category: "fullscreen"
  )
  private static var spaceEpoch: UInt64 = 0

  static var isEnabled: Bool {
    UpdateBuildIdentity().channel == .development
      && UserDefaults.standard.bool(forKey: preferenceKey)
  }

  static func spaceChanged() {
    spaceEpoch &+= 1
    recordEvent("active-space-notification")
  }

  static func recordEvent(_ event: String) {
    guard isEnabled else { return }
    let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
    let screen = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
    logger.debug("epoch=\(spaceEpoch) event=\(event, privacy: .public) frontmost=\(frontmost, privacy: .public) mainScreen=\(String(describing: screen), privacy: .public)")
  }

  static func recordWindows(
    _ stage: String,
    activation: NSWindow,
    main: NSWindow,
    secondary: NSWindow
  ) {
    guard isEnabled else { return }
    let windows = CGWindowListCopyWindowInfo(
      [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
    ) as? [[String: Any]] ?? []
    let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let frontRank = windows.firstIndex {
      ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == frontPID
    }
    func describe(_ name: String, _ window: NSWindow) -> String {
      let rank = windows.firstIndex {
        ($0[kCGWindowNumber as String] as? NSNumber)?.intValue == window.windowNumber
      }
      return "\(name){visible=\(window.isVisible),onActive=\(window.isOnActiveSpace),alpha=\(window.alphaValue),frame=\(NSStringFromRect(window.frame)),level=\(window.level.rawValue),behavior=\(window.collectionBehavior.rawValue),window=\(window.windowNumber),onScreenRank=\(rank.map(String.init) ?? "absent")}"
    }
    let message = "epoch=\(spaceEpoch) stage=\(stage) frontRank=\(frontRank.map(String.init) ?? "absent") \(describe("edge", activation)) \(describe("main", main)) \(describe("secondary", secondary))"
    logger.debug("\(message, privacy: .public)")
  }
}
