import AppKit
import SwiftUI

enum SettingsWindowMetrics {
  static let contentWidth: CGFloat = 480

  static func contentHeight(
    remindersEnabled: Bool,
    showsCustomFrequency: Bool,
    showsCustomPause: Bool,
    showsPausedStatus: Bool
  ) -> CGFloat {
    guard remindersEnabled else { return 720 }
    let revealedRows =
      (showsCustomFrequency ? 1 : 0)
      + (showsCustomPause ? 1 : 0)
      + (showsPausedStatus ? 1 : 0)
    return 820 + CGFloat(revealedRows * 42)
  }
}

struct SettingsView: View {
  let dismiss: () -> Void
  @ObservedObject var model: AppShellViewModel
  @ObservedObject private var updates: SoftwareUpdateService
  let preferredHeightChanged: (CGFloat) -> Void

  @State private var customPauseMinutes = 60
  @State private var showsCustomPause = false
  @State private var showsRemovalConfirmation = false
  @AppStorage(FullscreenDiagnostics.preferenceKey) private var recordsFullscreenDiagnostics = false
  @FocusState private var reminderFocus: ReminderFocus?
  private enum ReminderFocus: Hashable { case enabled, frequency, customPause }

  init(
    dismiss: @escaping () -> Void,
    model: AppShellViewModel,
    preferredHeightChanged: @escaping (CGFloat) -> Void = { _ in }
  ) {
    self.dismiss = dismiss
    self.model = model
    self.updates = model.updates
    self.preferredHeightChanged = preferredHeightChanged
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Settings").font(.title2.weight(.semibold))
        Spacer()
        Button("Done") { dismiss() }
          .keyboardShortcut(.defaultAction)
          .accessibilityLabel("Close Settings")
      }
      .padding()
      Divider()
      Form {
        Section("EasyFlow") {
          LabeledContent("Storage", value: "Stored on this Mac")
          LabeledContent("Activation", value: "\(model.panelSide == .right ? "Far-right" : "Far-left") edge · 300 ms")
          LabeledContent("Panels", value: "\(model.panelCustomization.preset.label) · \(Int(panelWidth)) × \(Int(panelHeight)) pt")
          Picker("Panel Side", selection: $model.panelSide) {
            ForEach(PanelSide.allCases) { side in Text(side.label).tag(side) }
          }
          .pickerStyle(.segmented)
          Picker("Appearance", selection: $model.appearanceMode) {
            ForEach(AppearanceMode.available) { mode in
              Text(mode.label).tag(mode)
            }
          }
          Picker("Main Task Rows", selection: $model.mainTaskDensity) {
            ForEach(MainTaskDensity.allCases) { density in
              Text(density.label).tag(density)
            }
          }
          .pickerStyle(.segmented)
          Toggle(
            "Launch at Login",
            isOn: Binding(
              get: { model.launchAtLoginStatus == .enabled },
              set: { model.setLaunchAtLogin($0) }
            )
          )
          if model.launchAtLoginStatus == .requiresApproval {
            Text("Approve EasyFlow in System Settings > General > Login Items.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          HStack {
            Text("Reminders")
            Spacer()
            Text(remindersStatusLabel).foregroundStyle(.secondary)
            if model.remindersStatus != .connected {
              Button("Retry") { model.retryRemindersSync() }
            }
            if model.remindersStatus == .denied {
              Button("Privacy Settings") { model.openRemindersPrivacySettings() }
            }
          }
        }
        Section("Panel Size") {
          LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(PanelSizePreset.allCases) { preset in
              Button { model.selectPanelSize(preset) } label: {
                VStack(spacing: 8) {
                  Image(systemName: preset.symbol).font(.system(size: 21, weight: .medium))
                  Text(preset.label).font(.callout.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 66)
                .foregroundStyle(model.panelCustomization.preset == preset ? Color.accentColor : Color.primary)
                .background(
                  model.panelCustomization.preset == preset
                    ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05),
                  in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                  RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(model.panelCustomization.preset == preset ? Color.accentColor : .clear, lineWidth: 1.5)
                }
              }
              .buttonStyle(.plain)
              .accessibilityLabel("\(preset.label) panel size")
              .accessibilityValue(model.panelCustomization.preset == preset ? "Selected" : "Not selected")
            }
          }
          PanelDimensionSlider(
            label: "Width",
            value: Binding(
              get: { Double(panelWidth) },
              set: { model.setPanelWidth(CGFloat($0), preserving: panelHeight) }
            ),
            range: widthSliderRange
          )
          PanelDimensionSlider(
            label: "Height",
            value: Binding(
              get: { Double(panelHeight) },
              set: { model.setPanelHeight(CGFloat($0), preserving: panelWidth) }
            ),
            range: heightSliderRange
          )
          Text("Both panels use this height. Longer content scrolls inside them.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Section("Panel Surface") {
          Toggle(isOn: Binding(
            get: { model.usesTranslucentBackground },
            set: { model.setTranslucentBackground($0) }
          )) {
            VStack(alignment: .leading, spacing: 2) {
              Text("Translucent background")
              Text("Use a macOS material behind the workspace. Reduce Transparency always uses a solid surface.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          .accessibilityLabel("Translucent background")
        }
        if updates.isDevelopmentBuild {
          Section("Fullscreen Diagnostics") {
            Toggle("Record fullscreen panel diagnostics", isOn: $recordsFullscreenDiagnostics)
            Text("Records Space transitions, edge activation, window frames, active-Space membership, and on-screen ordering. No task or note text is recorded.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Section("Software Updates") {
          LabeledContent("Current version", value: "EasyFlow \(AppVersion.label())")
          if updates.hasNewBadge {
            Label("New version available", systemImage: "circle.fill")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.tint)
          }
          Toggle("Automatically check for updates", isOn: Binding(
            get: { updates.automaticChecksEnabled },
            set: { updates.setAutomaticChecksEnabled($0) }
          ))
          Text("EasyFlow checks public GitHub releases about once a day. Installation always needs your approval.")
            .font(.caption)
            .foregroundStyle(.secondary)
          if updates.isDevelopmentBuild {
            Text("Local development build: automatic checks and update installation are disabled.")
              .font(.caption)
              .foregroundStyle(.secondary)
            Menu("Preview Update UI") {
              Button("Update available") { updates.preview(.available) }
              Button("Download at 50%") { updates.preview(.downloading) }
              Button("Error") { updates.preview(.failed) }
              Button("Reset") { updates.preview(.reset) }
            }
            .accessibilityLabel("Preview software update states")
          }
          HStack {
            Button("Check for Updates") {
              Task { await updates.check() }
            }
            .disabled(updates.phase == .checking || updates.phase == .downloading || updates.phase == .verifying)
            Spacer()
            updateStatus
          }
          if let lastCheckedAt = updates.lastCheckedAt {
            Text("Last checked \(lastCheckedAt.formatted(date: .abbreviated, time: .shortened))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          if updates.phase == .downloading {
            ProgressView(value: updates.downloadProgress)
              .accessibilityLabel("Downloading EasyFlow update")
              .accessibilityValue("\(Int((updates.downloadProgress * 100).rounded())) percent")
          }
          if case .available(let candidate) = updates.phase {
            VStack(alignment: .leading, spacing: 6) {
              Text("Update available: \(candidate.version.description)")
                .font(.callout.weight(.semibold))
              Text("Installed: \(updates.build.version?.description ?? "Unknown")")
                .font(.caption).foregroundStyle(.secondary)
              if !candidate.notes.isEmpty {
                Text(candidate.notes).font(.caption).lineLimit(5)
              }
              if !candidate.hasSignedAssets {
                Text("This release has no signed update assets and cannot be installed in-app.")
                  .font(.caption).foregroundStyle(.secondary)
              }
              HStack {
                if updates.build.canInstallUpdates && candidate.hasSignedAssets {
                  Button("Install Update") {
                    Task { await updates.install(candidate) }
                  }
                  .buttonStyle(.borderedProminent)
                }
                Button("Later") { updates.postpone() }
                Button("View Release") { NSWorkspace.shared.open(candidate.releasePage) }
              }
            }
            .padding(.vertical, 4)
          }
          if case .manualInstall(let appURL) = updates.phase {
            VStack(alignment: .leading, spacing: 5) {
              Text("This installation needs manual replacement. The verified app is ready in Finder.")
                .font(.caption)
              Button("Reveal Verified App") { updates.revealManualInstall(appURL) }
            }
          }
        }
        Section("EasyFlow Reminders") {
          Toggle(
            "Show reminder banners",
            isOn: Binding(
              get: { model.reminderSettings.isEnabled },
              set: { enabled in
                withAnimation(.easeInOut(duration: 0.18)) {
                  if !enabled { showsCustomPause = false }
                  model.setRemindersEnabled(enabled)
                }
              }
            )
          )

          .focused($reminderFocus, equals: .enabled)

          if model.reminderSettings.isEnabled {
            Group {
              Picker(
                "Frequency",
                selection: Binding(
                  get: { frequencySelection },
                  set: { selection in
                    withAnimation(.easeInOut(duration: 0.18)) {
                      model.setReminderFrequency(
                        selection.frequency(
                          customInterval: model.reminderSettings.customInterval
                        )
                      )
                    }
                  }
                )
              ) {
                ForEach(ReminderFrequencySelection.allCases) { option in
                  Text(option.label).tag(option)
                }
              }

              .focused($reminderFocus, equals: .frequency)

              if frequencySelection == .custom {
                HStack {
                  Text("Custom")
                  Spacer()
                  MinuteAdjuster(
                    purpose: "Reminder frequency",
                    minutes: customMinutes,
                    decrement: {
                      model.setReminderCustomInterval(
                        minutes: ReminderMinuteRange.decrementing(customMinutes)
                      )
                    },
                    increment: {
                      model.setReminderCustomInterval(
                        minutes: ReminderMinuteRange.incrementing(customMinutes)
                      )
                    }
                  )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
              }

              if let pausedUntil = model.reminderSettings.pausedUntil,
                pausedUntil > Date()
              {
                HStack {
                  Text("Paused until \(pausedUntil.formatted(date: .abbreviated, time: .shortened))")
                  Spacer()
                  Button("Resume") {
                    reminderFocus = .customPause
                    model.resumeReminders()
                  }
                }
              }

              HStack(spacing: 8) {
                Text("Pause")
                Spacer()
                Button("1 hour") { pause(.oneHour) }
                  .accessibilityLabel("Pause reminders for 1 hour")
                Button("3 hours") { pause(.threeHours) }
                  .accessibilityLabel("Pause reminders for 3 hours")
                Button("Until Tomorrow") { pause(.untilTomorrow) }
                  .accessibilityLabel("Pause reminders until tomorrow")
                Button("Custom…") {
                  withAnimation(.easeInOut(duration: 0.18)) {
                    showsCustomPause.toggle()
                  }
                }
                .focused($reminderFocus, equals: .customPause)
                .accessibilityLabel("Custom reminder pause")
                .accessibilityValue(showsCustomPause ? "Expanded" : "Collapsed")
              }
              .controlSize(.small)

              if showsCustomPause {
                HStack {
                  Text("Pause for")
                  Spacer()
                  MinuteAdjuster(
                    purpose: "Reminder pause",
                    minutes: customPauseMinutes,
                    decrement: {
                      customPauseMinutes = ReminderMinuteRange.decrementing(customPauseMinutes)
                    },
                    increment: {
                      customPauseMinutes = ReminderMinuteRange.incrementing(customPauseMinutes)
                    }
                  )
                  Button("Pause") {
                    reminderFocus = .customPause
                    model.pauseReminders(minutes: customPauseMinutes)
                    withAnimation(.easeInOut(duration: 0.18)) {
                      showsCustomPause = false
                    }
                  }
                  .buttonStyle(.borderedProminent)
                  .controlSize(.small)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
              }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
          }
        }
      }
      .formStyle(.grouped)
      HStack {
        Button("Quit EasyFlow") { NSApp.terminate(nil) }
        Spacer()
        Button("Uninstall EasyFlow…") { showsRemovalConfirmation = true }
      }
      .padding(.horizontal, 20)
      .padding(.top, 8)
      Text(AppVersion.label())
        .font(.caption).foregroundStyle(.secondary).padding(.bottom, 16)
    }
    .frame(width: SettingsWindowMetrics.contentWidth)
    .animation(.easeInOut(duration: 0.18), value: model.reminderSettings.isEnabled)
    .onExitCommand { dismiss() }
    .onAppear {
      model.refreshLaunchAtLoginStatus()
      reportPreferredHeight()
    }
    .onChange(of: model.reminderSettings.isEnabled) { _, enabled in
      if !enabled { reminderFocus = .enabled }
      reportPreferredHeight()
    }
    .onChange(of: frequencySelection) { _, _ in reportPreferredHeight() }
    .onChange(of: model.reminderSettings.pausedUntil) { _, _ in reportPreferredHeight() }
    .onChange(of: showsCustomPause) { _, _ in reportPreferredHeight() }
    .alert("Remove EasyFlow from this Mac", isPresented: $showsRemovalConfirmation) {
      Button("Reveal App and Quit") { revealAppForManualRemoval() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("EasyFlow will turn off Launch at Login, show its app in Finder, and quit after saving pending edits. Move the app to Trash yourself. Your local database, attachments, preferences, and Apple Reminders will remain in place.")
    }
    .background {
      Button("") { dismiss() }
        .keyboardShortcut("w", modifiers: .command)
        .hidden()
        .accessibilityHidden(true)
    }
  }

  private var remindersStatusLabel: String {
    switch model.remindersStatus {
    case .connected: "Connected"
    case .needsAccess: "Needs Access"
    case .requesting: "Requesting…"
    case .synchronizing: "Synchronizing…"
    case .denied: "Access Denied"
    case .ambiguousList: "Multiple EasyFlow Lists"
    case .error: "Error"
    }
  }

  @ViewBuilder private var updateStatus: some View {
    switch updates.phase {
    case .idle: EmptyView()
    case .checking: Text("Checking…")
    case .upToDate: Text("You're up to date.")
    case .available: Text("Update available")
    case .downloading: Text("Downloading…")
    case .verifying: Text("Verifying…")
    case .installing: Text("Installing…")
    case .manualInstall: Text("Manual installation")
    case .failed(let message): Text(message)
    }
  }

  private var customMinutes: Int {
    ReminderMinuteRange.clamped(Int(model.reminderSettings.customInterval / 60))
  }

  private var selectedDisplay: DisplaySnapshot? {
    DisplayGeometry.rightmostScreen(side: model.panelSide)
  }

  private var panelPreviewLayout: PanelLayout? {
    guard let selectedDisplay else { return nil }
    return PanelLayout(
      display: selectedDisplay,
      side: model.panelSide,
      customization: model.panelCustomization
    )
  }

  private var panelWidth: CGFloat {
    panelPreviewLayout?.mainFrame.width ?? model.panelCustomization.customWidth
  }

  private var panelHeight: CGFloat {
    panelPreviewLayout?.mainFrame.height ?? model.panelCustomization.customHeight
  }

  private var widthSliderRange: ClosedRange<Double> {
    let fit = PanelSizing().maximumPairedWidth(for: selectedDisplay?.frame.width ?? 1470)
    let lower = min(PanelCustomization.widthRange.lowerBound, fit)
    let upper = max(panelWidth, min(PanelCustomization.widthRange.upperBound, fit))
    return Double(lower)...Double(max(lower + 1, upper))
  }

  private var heightSliderRange: ClosedRange<Double> {
    let fit = PanelSizing().maximumCustomHeight(for: selectedDisplay?.frame.height ?? 956)
    let lower = min(PanelCustomization.heightRange.lowerBound, fit)
    let upper = max(panelHeight, min(PanelCustomization.heightRange.upperBound, fit))
    return Double(lower)...Double(max(lower + 1, upper))
  }

  private var frequencySelection: ReminderFrequencySelection {
    switch model.reminderSettings.frequency {
    case .minutes15: .minutes15
    case .minutes30: .minutes30
    case .hour1: .hour1
    case .hours2: .hours2
    case .hours3: .hours3
    case .custom: .custom
    }
  }

  private func pause(_ preset: ReminderPausePreset) {
    showsCustomPause = false
    model.pauseReminders(preset)
  }

  private func revealAppForManualRemoval() {
    let appURL = Bundle.main.bundleURL.standardizedFileURL
    guard appURL.pathExtension == "app", Bundle.main.bundleIdentifier == "io.github.natizh.easyflow" else {
      model.errorMessage = "EasyFlow could not identify its installed app. No changes were made."
      return
    }
    guard model.prepareForManualRemoval() else { return }
    NSWorkspace.shared.activateFileViewerSelecting([appURL])
    NSApp.terminate(nil)
  }

  private func reportPreferredHeight() {
    preferredHeightChanged(
      SettingsWindowMetrics.contentHeight(
        remindersEnabled: model.reminderSettings.isEnabled,
        showsCustomFrequency: frequencySelection == .custom,
        showsCustomPause: showsCustomPause,
        showsPausedStatus: model.reminderSettings.isPaused(at: Date())
      )
    )
  }
}

private struct PanelDimensionSlider: View {
  let label: String
  @Binding var value: Double
  let range: ClosedRange<Double>

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      Text(label)
        .frame(minWidth: 44, alignment: .leading)
      PanelRulerSlider(value: $value, range: range, label: "Panel \(label.lowercased())")
        .frame(maxWidth: .infinity)
      Text("\(Int(value.rounded()))")
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(minWidth: 38, alignment: .trailing)
        .accessibilityHidden(true)
    }
    .padding(.vertical, 2)
  }
}

private struct MinuteAdjuster: View {
  let purpose: String
  let minutes: Int
  let decrement: () -> Void
  let increment: () -> Void

  var body: some View {
    HStack(spacing: 7) {
      adjustmentButton(
        systemName: "minus",
        accessibilityLabel: AccessibilityNames.minuteAdjustment(purpose: purpose, increasing: false),
        disabled: minutes <= ReminderMinuteRange.minimum,
        action: decrement
      )
      Text("\(minutes) min")
        .monospacedDigit()
        .frame(minWidth: 62)
        .accessibilityLabel(purpose)
        .accessibilityValue("\(minutes) minutes")
      adjustmentButton(
        systemName: "plus",
        accessibilityLabel: AccessibilityNames.minuteAdjustment(purpose: purpose, increasing: true),
        disabled: minutes >= ReminderMinuteRange.maximum,
        action: increment
      )
    }
  }

  private func adjustmentButton(
    systemName: String,
    accessibilityLabel: String,
    disabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 12, weight: .semibold))
        .frame(width: 28, height: 22)
        .contentShape(Rectangle())
    }
    .buttonStyle(.bordered)
    .disabled(disabled)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityValue("\(minutes) minutes")
  }
}

private enum ReminderFrequencySelection: String, CaseIterable, Identifiable {
  case minutes15
  case minutes30
  case hour1
  case hours2
  case hours3
  case custom

  var id: Self { self }

  var label: String {
    switch self {
    case .minutes15: "15 minutes"
    case .minutes30: "30 minutes"
    case .hour1: "1 hour"
    case .hours2: "2 hours"
    case .hours3: "3 hours"
    case .custom: "Custom…"
    }
  }

  func frequency(customInterval: TimeInterval) -> ReminderFrequency {
    switch self {
    case .minutes15: .minutes15
    case .minutes30: .minutes30
    case .hour1: .hour1
    case .hours2: .hours2
    case .hours3: .hours3
    case .custom: .custom(customInterval)
    }
  }
}
