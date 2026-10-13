import AppKit
import Foundation
import SwiftUI
import Testing
import Vision

@testable import EasyFlow

@Suite("Reminder Settings presentation")
struct SettingsPresentationTests {
  @Test("Packaged public app renders Settings without development controls")
  @MainActor func publicBuildOmitsDevelopmentControls() throws {
    guard let fixturePath = ProcessInfo.processInfo.environment["EASYFLOW_PUBLIC_APP_FIXTURE"] else { return }
    let bundleURL = URL(fileURLWithPath: fixturePath, isDirectory: true)
    let bundle = try #require(Bundle(url: bundleURL))
    let identity = UpdateBuildIdentity(bundle: bundle)
    #expect(identity.channel == .publicRelease)
    #expect(identity.version == SemanticVersion("1.5.0"))
    #expect(identity.buildNumber == "9")
    #expect(identity.canInstallUpdates)

    let defaults = try #require(UserDefaults(suiteName: "EasyFlowPublicSettingsAudit-\(UUID())"))
    let updates = SoftwareUpdateService(build: identity, defaults: defaults)
    let model = AppShellViewModel(
      repository: WorkspaceRepository(database: try AppDatabase(inMemoryNamed: UUID().uuidString)),
      updates: updates,
      userDefaults: defaults
    )
    let host = NSHostingView(rootView: SettingsView(dismiss: {}, model: model))
    host.frame = CGRect(x: 0, y: 0, width: 480, height: 2000)
    NSApplication.shared.setActivationPolicy(.accessory)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFrontRegardless()
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))

    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let image = try #require(bitmap.representation(using: .png, properties: [:]))
    let recognition = VNRecognizeTextRequest()
    recognition.recognitionLevel = .accurate
    try VNImageRequestHandler(data: image).perform([recognition])
    let renderedText = (recognition.results ?? [])
      .compactMap { $0.topCandidates(1).first?.string }
      .joined(separator: "\n")
    #expect(renderedText.contains("Software Updates"))
    #expect(renderedText.contains("Check for Updates"))
    for forbidden in [
      "Fullscreen Diagnostics", "Record fullscreen panel diagnostics",
      "Preview Update UI", "Preview software update states",
      "Local development build", "Space transitions", "Download at 50%"
    ] {
      #expect(!renderedText.contains(forbidden))
    }
    window.orderOut(nil)
  }
  @Test("Minute controls use bounded five-minute adjustments")
  func minuteAdjustmentBounds() {
    #expect(ReminderMinuteRange.decrementing(60) == 55)
    #expect(ReminderMinuteRange.incrementing(60) == 65)
    #expect(ReminderMinuteRange.decrementing(ReminderMinuteRange.minimum) == 5)
    #expect(ReminderMinuteRange.incrementing(ReminderMinuteRange.maximum) == 720)
    #expect(ReminderMinuteRange.clamped(1) == 5)
    #expect(ReminderMinuteRange.clamped(10_000) == 720)
    #expect(ReminderFrequency.custom(60).interval == 5 * 60)
    #expect(ReminderFrequency.custom(24 * 60 * 60).interval == 12 * 60 * 60)
  }

  @Test("Disabled reminders collapse Settings to its compact height")
  func disabledHeightIsCompact() {
    let disabled = SettingsWindowMetrics.contentHeight(
      remindersEnabled: false,
      showsCustomFrequency: true,
      showsCustomPause: true,
      showsPausedStatus: true
    )
    let enabled = SettingsWindowMetrics.contentHeight(
      remindersEnabled: true,
      showsCustomFrequency: false,
      showsCustomPause: false,
      showsPausedStatus: false
    )

    #expect(disabled == 720)
    #expect(disabled < enabled)
  }

  @Test("Only visible custom rows add window height")
  func customRowsDriveHeight() {
    let base = SettingsWindowMetrics.contentHeight(
      remindersEnabled: true,
      showsCustomFrequency: false,
      showsCustomPause: false,
      showsPausedStatus: false
    )
    let frequency = SettingsWindowMetrics.contentHeight(
      remindersEnabled: true,
      showsCustomFrequency: true,
      showsCustomPause: false,
      showsPausedStatus: false
    )
    let both = SettingsWindowMetrics.contentHeight(
      remindersEnabled: true,
      showsCustomFrequency: true,
      showsCustomPause: true,
      showsPausedStatus: false
    )

    #expect(abs(frequency - base - 42) < 0.001)
    #expect(abs(both - base - 84) < 0.001)
  }
}
