/// A keyboard selection is a draft until Return; pointer choices commit immediately.
struct EffortSelection: Equatable, Sendable {
  let saved: Effort?
  private(set) var candidate: Effort?

  init(saved: Effort?) {
    self.saved = saved
    candidate = saved
  }

  mutating func move(by offset: Int) {
    guard offset == -1 || offset == 1 else { return }
    let current = candidate?.rawValue ?? (offset > 0 ? 0 : 5)
    candidate = Effort(rawValue: min(4, max(1, current + offset)))
  }
}
