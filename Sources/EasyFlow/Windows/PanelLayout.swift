import CoreGraphics

struct PanelSizing: Equatable, Sendable {
  var widthFraction: CGFloat = 0.20
  var minimumWidth: CGFloat = 360
  var maximumWidth: CGFloat = 520
  var hotZoneWidth: CGFloat = 3
  var outerMargin: CGFloat = 8
  var panelGap: CGFloat = 8
  var verticalInsetFraction: CGFloat = 0.08
  var minimumVerticalInset: CGFloat = 64
  var maximumVerticalInset: CGFloat = 96

  func width(for displayWidth: CGFloat) -> CGFloat {
    min(max(displayWidth * widthFraction, minimumWidth), maximumWidth)
  }

  func verticalInset(for displayHeight: CGFloat) -> CGFloat {
    min(
      max(displayHeight * verticalInsetFraction, minimumVerticalInset),
      maximumVerticalInset
    )
  }

  func maximumPairedWidth(for displayWidth: CGFloat) -> CGFloat {
    max(1, (displayWidth - (outerMargin * 2) - panelGap) / 2)
  }

  func maximumCustomHeight(for displayHeight: CGFloat) -> CGFloat {
    max(1, displayHeight - 64)
  }

  func dimensions(for screenFrame: CGRect, customization: PanelCustomization) -> CGSize {
    let classicHeight = max(1, screenFrame.height - (verticalInset(for: screenFrame.height) * 2))
    guard customization.preset != .classic else {
      return CGSize(width: width(for: screenFrame.width), height: classicHeight)
    }

    let requestedWidth: CGFloat
    let requestedHeight: CGFloat
    switch customization.preset {
    case .compact:
      requestedWidth = min(max(screenFrame.width * 0.17, 300), 440)
      requestedHeight = classicHeight - 120
    case .spacious:
      requestedWidth = min(max(screenFrame.width * 0.24, 420), 620)
      requestedHeight = classicHeight + 100
    case .custom:
      requestedWidth = customization.customWidth
      requestedHeight = customization.customHeight
    case .classic:
      preconditionFailure("Classic was handled above")
    }
    let maxWidth = maximumPairedWidth(for: screenFrame.width)
    let maxHeight = maximumCustomHeight(for: screenFrame.height)
    return CGSize(
      width: min(max(requestedWidth, min(280, maxWidth)), maxWidth),
      height: min(max(requestedHeight, min(420, maxHeight)), maxHeight)
    )
  }
}

struct PanelLayout: Equatable, Sendable {
  let display: DisplaySnapshot
  let side: PanelSide
  let activationFrame: CGRect
  let mainFrame: CGRect
  let secondaryFrame: CGRect
  let mainInteractionFrame: CGRect
  let combinedInteractionFrame: CGRect

  init(
    display: DisplaySnapshot,
    sizing: PanelSizing = PanelSizing(),
    side: PanelSide = .right,
    customization: PanelCustomization = PanelCustomization()
  ) {
    self.display = display
    self.side = side

    let screenFrame = display.frame
    let dimensions = sizing.dimensions(for: screenFrame, customization: customization)
    let width = dimensions.width
    let verticalInset = sizing.verticalInset(for: screenFrame.height)
    let height = dimensions.height
    let panelY = customization.preset == .classic
      ? screenFrame.minY + verticalInset
      : screenFrame.midY - height / 2
    let mainX = side == .right ? screenFrame.maxX - sizing.outerMargin - width : screenFrame.minX + sizing.outerMargin
    let secondaryX = mainX - side.outwardSign * (sizing.panelGap + width)

    activationFrame = CGRect(
      x: side == .right ? screenFrame.maxX - sizing.hotZoneWidth : screenFrame.minX,
      y: screenFrame.minY,
      width: sizing.hotZoneWidth,
      height: screenFrame.height
    )
    mainFrame = CGRect(x: mainX, y: panelY, width: width, height: height)
    secondaryFrame = CGRect(x: secondaryX, y: panelY, width: width, height: height)
    let edgeMargin = CGRect(x: side == .right ? mainFrame.maxX : screenFrame.minX,
      y: panelY, width: sizing.outerMargin, height: height)
    mainInteractionFrame = mainFrame.union(edgeMargin)
    combinedInteractionFrame = mainInteractionFrame.union(secondaryFrame)
  }

  var mainHiddenFrame: CGRect {
    mainFrame.offsetBy(dx: side.outwardSign * (mainFrame.width + 16), dy: 0)
  }

  var secondaryHiddenFrame: CGRect {
    // Retraction stays inward of Main. A superseded close must never leave
    // Secondary covering Main while AppKit finishes an old frame animation.
    let gap = side == .right
      ? mainFrame.minX - secondaryFrame.maxX
      : secondaryFrame.minX - mainFrame.maxX
    return secondaryFrame.offsetBy(dx: side.outwardSign * gap, dy: 0)
  }

  func pointerRegion(at point: CGPoint, secondaryIsVisible: Bool) -> PointerRegion {
    if activationFrame.contains(point) {
      return .activationEdge
    }
    if mainFrame.contains(point) {
      return .main
    }
    if secondaryIsVisible, secondaryFrame.contains(point) {
      return .secondary
    }

    let interactionFrame =
      secondaryIsVisible
      ? combinedInteractionFrame
      : mainInteractionFrame
    if interactionFrame.contains(point) {
      return .bridge
    }
    return .outside
  }
}

struct SecondaryPresentationIntent: Equatable, Sendable {
  let startFrame: CGRect
  let targetFrame: CGRect
  let startAlpha: CGFloat
  let targetAlpha: CGFloat

  init(layout: PanelLayout) {
    targetFrame = layout.secondaryFrame
    startFrame = layout.secondaryHiddenFrame
    startAlpha = 0.15
    targetAlpha = 1
  }
}

struct PanelWindowObservation: Equatable, Sendable {
  let isVisible: Bool
  let isOnActiveSpace: Bool
  let frame: CGRect
  let alpha: CGFloat
  let isClosing: Bool
}

struct CoordinatedPanelTarget: Equatable, Sendable {
  let presentation: PanelSpacePresentation
  let layout: PanelLayout

  var mainIsRequired: Bool { presentation != .hidden }
  var secondaryIsRequired: Bool {
    if case .mainAndSecondary = presentation { return true }
    return false
  }

  func mainNeedsRepair(_ window: PanelWindowObservation) -> Bool {
    mainIsRequired && (!window.isVisible || !window.isOnActiveSpace
      || window.isClosing || window.frame != layout.mainFrame || window.alpha != 1)
  }

  func secondaryNeedsRepair(_ window: PanelWindowObservation) -> Bool {
    secondaryIsRequired && (!window.isVisible || !window.isOnActiveSpace
      || window.isClosing || window.frame != layout.secondaryFrame || window.alpha != 1)
  }
}
