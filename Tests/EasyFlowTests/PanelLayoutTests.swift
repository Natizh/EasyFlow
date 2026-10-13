import CoreGraphics
import Testing

@testable import EasyFlow

@Suite("Responsive panel layout")
struct PanelLayoutTests {
  @Test(
    "Width follows one fifth with stable minimum and maximum",
    arguments: [
      (CGFloat(1_440), CGFloat(360)),
      (CGFloat(2_560), CGFloat(512)),
      (CGFloat(4_000), CGFloat(520)),
    ]
  )
  func responsiveWidth(displayWidth: CGFloat, expected: CGFloat) {
    let sizing = PanelSizing()
    #expect(sizing.width(for: displayWidth) == expected)
  }

  @Test(
    "Vertical inset exposes a substantial responsive band",
    arguments: [
      (CGFloat(700), CGFloat(64)),
      (CGFloat(956), CGFloat(76.48)),
      (CGFloat(1_440), CGFloat(96)),
    ]
  )
  func responsiveVerticalInset(displayHeight: CGFloat, expected: CGFloat) {
    #expect(abs(PanelSizing().verticalInset(for: displayHeight) - expected) < 0.001)
  }

  @Test("Main anchors to the right and Secondary sits immediately to its left")
  func panelFrames() {
    let display = DisplaySnapshot(
      id: 1,
      frame: CGRect(x: 100, y: -50, width: 2_560, height: 1_440)
    )
    let layout = PanelLayout(display: display)

    #expect(layout.mainFrame.width == 512)
    #expect(layout.mainFrame.maxX == display.frame.maxX - 8)
    #expect(layout.secondaryFrame.maxX == layout.mainFrame.minX - 8)
    #expect(layout.mainFrame.minY == display.frame.minY + 96)
    #expect(layout.mainFrame.height == display.frame.height - 192)
    #expect(layout.secondaryFrame.minY == layout.mainFrame.minY)
    #expect(layout.secondaryFrame.height == layout.mainFrame.height)
    #expect(layout.activationFrame.width == 3)
    #expect(layout.activationFrame.maxX == display.frame.maxX)
  }

  @Test("Secondary presentation target is visible left of Main with full alpha")
  func secondaryPresentationIntent() {
    let display = DisplaySnapshot(
      id: 1,
      frame: CGRect(x: 0, y: 0, width: 1_470, height: 956)
    )
    let layout = PanelLayout(display: display)
    let intent = SecondaryPresentationIntent(layout: layout)

    #expect(intent.targetFrame == layout.secondaryFrame)
    #expect(intent.targetFrame.maxX < layout.mainFrame.minX)
    #expect(display.frame.contains(intent.targetFrame))
    #expect(intent.startFrame.minX > intent.targetFrame.minX)
    #expect(intent.startAlpha > 0)
    #expect(intent.targetAlpha == 1)
  }

  @Test("Pointer classification bridges panel gaps without widening hidden hit areas")
  func pointerRegions() {
    let display = DisplaySnapshot(
      id: 1,
      frame: CGRect(x: 0, y: 0, width: 2_560, height: 1_440)
    )
    let layout = PanelLayout(display: display)

    #expect(
      layout.pointerRegion(
        at: CGPoint(x: display.frame.maxX - 1, y: display.frame.midY),
        secondaryIsVisible: false
      ) == .activationEdge
    )
    #expect(
      layout.pointerRegion(
        at: CGPoint(x: layout.mainFrame.minX - 4, y: layout.mainFrame.midY),
        secondaryIsVisible: true
      ) == .bridge
    )
    #expect(
      layout.pointerRegion(
        at: CGPoint(x: layout.mainFrame.midX, y: layout.mainFrame.midY),
        secondaryIsVisible: false
      ) == .main
    )
    #expect(
      layout.pointerRegion(
        at: CGPoint(x: layout.secondaryFrame.midX, y: layout.secondaryFrame.midY),
        secondaryIsVisible: false
      ) == .outside
    )
    #expect(
      layout.pointerRegion(
        at: CGPoint(x: layout.secondaryFrame.midX, y: layout.secondaryFrame.midY),
        secondaryIsVisible: true
      ) == .secondary
    )
  }

  @Test("Both panel targets remain distinct on Left and Right displays")
  func pairedTargetsMirrorWithoutOverlap() {
    for side in PanelSide.allCases {
      let layout = PanelLayout(
        display: DisplaySnapshot(id: 2, frame: CGRect(x: -1728, y: -120, width: 1728, height: 1117)),
        side: side
      )
      let target = CoordinatedPanelTarget(presentation: .mainAndSecondary(.quickNotes), layout: layout)
      #expect(target.mainIsRequired)
      #expect(target.secondaryIsRequired)
      #expect(!layout.mainFrame.intersects(layout.secondaryFrame))
      #expect(!layout.mainFrame.intersects(layout.secondaryHiddenFrame))
      #expect(layout.mainFrame == PanelLayout(display: layout.display, side: side).mainFrame)
    }
  }

  @Test("A hidden, off-Space, closing, or misplaced Main requires repair")
  func mainRepairObservations() {
    let layout = PanelLayout(display: DisplaySnapshot(id: 1,
      frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)))
    let target = CoordinatedPanelTarget(presentation: .mainAndSecondary(.quickNotes), layout: layout)
    let healthy = PanelWindowObservation(isVisible: true, isOnActiveSpace: true,
      frame: layout.mainFrame, alpha: 1, isClosing: false)
    #expect(!target.mainNeedsRepair(healthy))
    #expect(target.mainNeedsRepair(.init(isVisible: false, isOnActiveSpace: true,
      frame: layout.mainFrame, alpha: 1, isClosing: false)))
    #expect(target.mainNeedsRepair(.init(isVisible: true, isOnActiveSpace: false,
      frame: layout.mainFrame, alpha: 1, isClosing: false)))
    #expect(target.mainNeedsRepair(.init(isVisible: true, isOnActiveSpace: true,
      frame: layout.mainHiddenFrame, alpha: 0, isClosing: false)))
    #expect(target.mainNeedsRepair(.init(isVisible: true, isOnActiveSpace: true,
      frame: layout.mainFrame, alpha: 1, isClosing: true)))
  }

  @Test("Reconciliation target is stable across repeated calls and display changes")
  func repeatedTargetReconciliation() {
    let display = DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 2560, height: 1440))
    let original = CoordinatedPanelTarget(presentation: .mainAndSecondary(.quickNotes),
      layout: PanelLayout(display: display))
    #expect(original == CoordinatedPanelTarget(presentation: original.presentation, layout: original.layout))
    let secondary = PanelWindowObservation(isVisible: true, isOnActiveSpace: true,
      frame: original.layout.mainFrame, alpha: 1, isClosing: false)
    #expect(original.secondaryNeedsRepair(secondary))
    let changed = CoordinatedPanelTarget(presentation: original.presentation,
      layout: PanelLayout(display: DisplaySnapshot(id: 3,
        frame: CGRect(x: 2560, y: -80, width: 1512, height: 982))))
    #expect(changed.layout.secondaryFrame != original.layout.secondaryFrame)
    #expect(changed.secondaryNeedsRepair(.init(isVisible: true, isOnActiveSpace: true,
      frame: original.layout.secondaryFrame, alpha: 1, isClosing: false)))
  }
}
