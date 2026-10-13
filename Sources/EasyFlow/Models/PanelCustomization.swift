import CoreGraphics

enum PanelSizePreset: String, CaseIterable, Identifiable, Sendable {
  case compact
  case classic
  case spacious
  case custom

  var id: String { rawValue }

  var label: String {
    switch self {
    case .compact: "Compact"
    case .classic: "Classic"
    case .spacious: "Spacious"
    case .custom: "Custom"
    }
  }

  var symbol: String {
    switch self {
    case .compact: "rectangle.compress.vertical"
    case .classic: "rectangle"
    case .spacious: "rectangle.expand.vertical"
    case .custom: "slider.horizontal.3"
    }
  }
}

struct PanelCustomization: Equatable, Sendable {
  var preset: PanelSizePreset = .classic
  var customWidth: CGFloat = 480
  var customHeight: CGFloat = 720

  static let widthRange: ClosedRange<CGFloat> = 280...680
  static let heightRange: ClosedRange<CGFloat> = 420...3000

  static func clampedWidth(_ value: CGFloat) -> CGFloat {
    guard value.isFinite else { return 480 }
    return min(max(value, widthRange.lowerBound), widthRange.upperBound)
  }

  static func clampedHeight(_ value: CGFloat) -> CGFloat {
    guard value.isFinite else { return 720 }
    return min(max(value, heightRange.lowerBound), heightRange.upperBound)
  }

  mutating func select(_ preset: PanelSizePreset) {
    self.preset = preset
  }

  mutating func setWidth(_ width: CGFloat, preserving height: CGFloat) {
    if preset != .custom { customHeight = Self.clampedHeight(height) }
    customWidth = Self.clampedWidth(width)
    preset = .custom
  }

  mutating func setHeight(_ height: CGFloat, preserving width: CGFloat) {
    if preset != .custom { customWidth = Self.clampedWidth(width) }
    customHeight = Self.clampedHeight(height)
    preset = .custom
  }
}
