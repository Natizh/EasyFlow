import AppKit
import Testing

@testable import EasyFlow

@Suite("Panel customization")
struct PanelCustomizationTests {
  @Test("Classic is the default and exactly matches the original panel geometry")
  func classicGeometry() {
    let sizing = PanelSizing()
    for width: CGFloat in [1_440, 2_560, 4_000] {
      let display = DisplaySnapshot(id: 1, frame: CGRect(x: -800, y: -100, width: width, height: 1_440))
      for side in PanelSide.allCases {
        let layout = PanelLayout(display: display, sizing: sizing, side: side,
          customization: PanelCustomization())
        #expect(layout.mainFrame.width == sizing.width(for: width))
        #expect(layout.mainFrame.height == display.frame.height - 2 * sizing.verticalInset(for: display.frame.height))
        #expect(layout.mainFrame.minY == display.frame.minY + sizing.verticalInset(for: display.frame.height))
        #expect(layout == PanelLayout(display: display, sizing: sizing, side: side))
      }
    }
  }

  @Test("Compact and Spacious remain ordered and both panels fit the selected screen")
  func presetGeometry() {
    let display = DisplaySnapshot(id: 2, frame: CGRect(x: -1_470, y: -80, width: 1_470, height: 956))
    let classic = PanelLayout(display: display)
    for side in PanelSide.allCases {
      var customization = PanelCustomization()
      customization.select(.compact)
      let compact = PanelLayout(display: display, side: side, customization: customization)
      customization.select(.spacious)
      let spacious = PanelLayout(display: display, side: side, customization: customization)
      #expect(compact.mainFrame.width < classic.mainFrame.width)
      #expect(compact.mainFrame.height < classic.mainFrame.height)
      #expect(spacious.mainFrame.width > classic.mainFrame.width)
      #expect(spacious.mainFrame.height > classic.mainFrame.height)
      for layout in [compact, spacious] {
        #expect(display.frame.contains(layout.mainFrame))
        #expect(display.frame.contains(layout.secondaryFrame))
        #expect(!layout.mainFrame.intersects(layout.secondaryFrame))
        #expect(layout.mainFrame.width == layout.secondaryFrame.width)
        #expect(layout.mainFrame.height == layout.secondaryFrame.height)
      }
    }
  }

  @Test("Custom dimensions map to both panel frames and clamp on a smaller display")
  func customGeometryAndDisplayChange() {
    var customization = PanelCustomization()
    customization.setWidth(540, preserving: 680)
    customization.setHeight(680, preserving: 540)
    let large = DisplaySnapshot(id: 3, frame: CGRect(x: 0, y: 0, width: 2_560, height: 1_440))
    let wideLayout = PanelLayout(display: large, customization: customization)
    #expect(wideLayout.mainFrame.size == CGSize(width: 540, height: 680))
    #expect(wideLayout.secondaryFrame.size == wideLayout.mainFrame.size)

    let small = DisplaySnapshot(id: 4, frame: CGRect(x: 2_560, y: -50, width: 800, height: 600))
    for side in PanelSide.allCases {
      let layout = PanelLayout(display: small, side: side, customization: customization)
      #expect(layout.mainFrame.width <= PanelSizing().maximumPairedWidth(for: small.frame.width))
      #expect(layout.mainFrame.height <= PanelSizing().maximumCustomHeight(for: small.frame.height))
      #expect(small.frame.contains(layout.mainFrame))
      #expect(small.frame.contains(layout.secondaryFrame))
    }
    #expect(customization.customWidth == 540)
    #expect(customization.customHeight == 680)
  }

  @Test("Preset switches retain the prior custom width and height")
  func customValuesSurvivePresets() {
    var customization = PanelCustomization()
    customization.setWidth(530, preserving: 760)
    customization.setHeight(690, preserving: 530)
    customization.select(.compact)
    customization.select(.classic)
    customization.select(.spacious)
    customization.select(.custom)
    #expect(customization.customWidth == 530)
    #expect(customization.customHeight == 690)
  }

  @Test("Size and translucency preferences restore and dimension changes emit live layout intent")
  @MainActor func preferencePersistenceAndLiveChanges() throws {
    let suite = "EasyFlowPanelCustomization.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let repository = WorkspaceRepository(database: try AppDatabase(inMemoryNamed: UUID().uuidString))
    let model = AppShellViewModel(repository: repository, userDefaults: defaults)
    #expect(model.panelCustomization.preset == .classic)
    #expect(!model.usesTranslucentBackground)
    var observed: [PanelCustomization] = []
    model.onPanelCustomizationChanged = { observed.append($0) }
    model.setPanelWidth(550, preserving: 720)
    model.setPanelHeight(750, preserving: 550)
    #expect(observed.count == 2)
    #expect(observed.last?.preset == .custom)
    #expect(PanelLayout(display: DisplaySnapshot(id: 5,
      frame: CGRect(x: 0, y: 0, width: 2_560, height: 1_440)),
      customization: observed.last!).mainFrame.size == CGSize(width: 550, height: 750))
    model.setTranslucentBackground(true)
    model.selectPanelSize(.compact)

    let restored = AppShellViewModel(repository: repository, userDefaults: defaults)
    #expect(restored.panelCustomization.preset == .compact)
    #expect(restored.panelCustomization.customWidth == 550)
    #expect(restored.panelCustomization.customHeight == 750)
    #expect(restored.usesTranslucentBackground)
    restored.selectPanelSize(.classic)
    restored.selectPanelSize(.custom)
    #expect(restored.panelCustomization.customWidth == 550)
    #expect(restored.panelCustomization.customHeight == 750)
  }

  @Test("Default translucency follows appearance until the user chooses a preference")
  @MainActor func appearanceIntegration() throws {
    let suite = "EasyFlowPanelSurface.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let repository = WorkspaceRepository(database: try AppDatabase(inMemoryNamed: UUID().uuidString))
    let model = AppShellViewModel(repository: repository, userDefaults: defaults)
    #expect(!model.usesTranslucentBackground)
    model.appearanceMode = .frosted
    #expect(model.usesTranslucentBackground)
    model.setTranslucentBackground(false)
    #expect(!model.usesTranslucentBackground)
    #expect(!AppShellViewModel(repository: repository, userDefaults: defaults).usesTranslucentBackground)
  }
}
