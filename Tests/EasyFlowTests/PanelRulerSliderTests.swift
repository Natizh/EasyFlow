import AppKit
import Testing

@testable import EasyFlow

@Suite("Panel dimension slider")
@MainActor
struct PanelRulerSliderTests {
  @Test("One ruler has identical spacing and spans the native track rectangle")
  func rulerGeometry() {
    for width: CGFloat in [180, 320, 540] {
      let track = CGRect(x: 11, y: 12, width: width, height: 4)
      let positions = PanelRulerGeometry.positions(in: track)
      #expect(positions.count == 19)
      #expect(positions.first == track.minX)
      #expect(positions.last == track.maxX)
      let gaps = zip(positions, positions.dropFirst()).map { $1 - $0 }
      #expect(gaps.allSatisfy { abs($0 - gaps[0]) < 0.0001 })
    }
  }

  @Test("Mouse and keyboard values stay bounded on ten-point steps")
  func quantization() {
    let range = 280.0...680.0
    #expect(PanelRulerGeometry.quantized(284, in: range) == 280)
    #expect(PanelRulerGeometry.quantized(286, in: range) == 290)
    #expect(PanelRulerGeometry.quantized(999, in: range) == 680)
    #expect(PanelRulerGeometry.quantized(-50, in: range) == 280)
  }

  @Test("The native slider exposes accessibility and has no native tick marks")
  func nativeControl() {
    _ = NSApplication.shared
    let view = PanelRulerSliderView(frame: CGRect(x: 0, y: 0, width: 360, height: 36))
    view.layout()
    view.slider.minValue = 280
    view.slider.maxValue = 680
    view.slider.doubleValue = 480
    view.slider.setAccessibilityLabel("Panel width")
    #expect(view.slider.numberOfTickMarks == 0)
    #expect(!view.slider.allowsTickMarkValuesOnly)
    #expect(view.slider.isContinuous)
    #expect(view.slider.accessibilityRole() == .slider)
    #expect(view.slider.accessibilityLabel() == "Panel width")
    let trackBefore = (view.slider.cell as? NSSliderCell)?.barRect(flipped: view.slider.isFlipped)
    view.slider.doubleValue = 600
    let trackAfter = (view.slider.cell as? NSSliderCell)?.barRect(flipped: view.slider.isFlipped)
    #expect(trackBefore == trackAfter)

    let right = NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
      windowNumber: 0, context: nil, characters: "→", charactersIgnoringModifiers: "→",
      isARepeat: false, keyCode: 124
    )!
    view.slider.keyDown(with: right)
    #expect(view.slider.doubleValue == 610)
    #expect(view.slider.accessibilityPerformIncrement())
    #expect(view.slider.doubleValue == 620)
    #expect(view.slider.accessibilityPerformDecrement())
    #expect(view.slider.doubleValue == 610)

    if let path = ProcessInfo.processInfo.environment["EASYFLOW_SLIDER_SNAPSHOT"],
      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
      view.cacheDisplay(in: view.bounds, to: bitmap)
      try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
  }
}
