import AppKit
import SwiftUI

enum PanelRulerGeometry {
  static let dotCount = 19
  static let dotDiameter: CGFloat = 2

  static func positions(in track: CGRect, count: Int = dotCount) -> [CGFloat] {
    guard track.width > 0, count > 1 else { return [] }
    return (0..<count).map { track.minX + CGFloat($0) * track.width / CGFloat(count - 1) }
  }

  static func quantized(_ value: Double, in range: ClosedRange<Double>, step: Double = 10) -> Double {
    guard step > 0 else { return min(max(value, range.lowerBound), range.upperBound) }
    let clamped = min(max(value, range.lowerBound), range.upperBound)
    let rounded = range.lowerBound + ((clamped - range.lowerBound) / step).rounded() * step
    return min(max(rounded, range.lowerBound), range.upperBound)
  }
}

struct PanelRulerSlider: NSViewRepresentable {
  @Binding var value: Double
  let range: ClosedRange<Double>
  let label: String

  func makeCoordinator() -> Coordinator { Coordinator(value: $value, range: range) }

  func makeNSView(context: Context) -> PanelRulerSliderView {
    let view = PanelRulerSliderView()
    view.slider.target = context.coordinator
    view.slider.action = #selector(Coordinator.valueChanged(_:))
    return view
  }

  func updateNSView(_ view: PanelRulerSliderView, context: Context) {
    context.coordinator.value = $value
    context.coordinator.range = range
    view.slider.minValue = range.lowerBound
    view.slider.maxValue = range.upperBound
    view.slider.numberOfTickMarks = 0
    view.slider.allowsTickMarkValuesOnly = false
    view.slider.altIncrementValue = 10
    view.slider.setAccessibilityLabel(label)
    if abs(view.slider.doubleValue - value) > 0.001 {
      view.slider.doubleValue = value
    }
    view.needsDisplay = true
  }

  @MainActor final class Coordinator: NSObject {
    var value: Binding<Double>
    var range: ClosedRange<Double>

    init(value: Binding<Double>, range: ClosedRange<Double>) {
      self.value = value
      self.range = range
    }

    @objc func valueChanged(_ sender: NSSlider) {
      let next = PanelRulerGeometry.quantized(sender.doubleValue, in: range)
      sender.doubleValue = next
      value.wrappedValue = next
    }
  }
}

@MainActor
final class PanelRulerSliderView: NSView {
  let slider = PanelSteppedNSSlider()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    slider.numberOfTickMarks = 0
    slider.allowsTickMarkValuesOnly = false
    slider.isContinuous = true
    slider.setAccessibilityElement(true)
    slider.setAccessibilityRole(.slider)
    addSubview(slider)
  }

  required init?(coder: NSCoder) { fatalError("Not implemented") }

  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: 36)
  }

  override func layout() {
    super.layout()
    slider.frame = NSRect(x: 0, y: 8, width: bounds.width, height: 28)
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let cell = slider.cell as? NSSliderCell else { return }
    let track = cell.barRect(flipped: slider.isFlipped).offsetBy(
      dx: slider.frame.minX, dy: slider.frame.minY
    )
    let dotY: CGFloat = 3
    NSColor.secondaryLabelColor.withAlphaComponent(0.35).setFill()
    for x in PanelRulerGeometry.positions(in: track) {
      NSBezierPath(ovalIn: NSRect(
        x: x - PanelRulerGeometry.dotDiameter / 2,
        y: dotY - PanelRulerGeometry.dotDiameter / 2,
        width: PanelRulerGeometry.dotDiameter,
        height: PanelRulerGeometry.dotDiameter
      )).fill()
    }
  }
}

@MainActor
final class PanelSteppedNSSlider: NSSlider {
  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 123, 125:
      adjust(by: -10)
    case 124, 126:
      adjust(by: 10)
    default:
      super.keyDown(with: event)
    }
  }

  override func accessibilityPerformIncrement() -> Bool {
    adjust(by: 10)
    return true
  }

  override func accessibilityPerformDecrement() -> Bool {
    adjust(by: -10)
    return true
  }

  private func adjust(by amount: Double) {
    doubleValue = min(max(doubleValue + amount, minValue), maxValue)
    if let action { sendAction(action, to: target) }
  }
}
