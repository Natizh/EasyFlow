import Foundation
import Testing

@testable import EasyFlow

@Suite("Local workspace view model")
@MainActor
struct WorkspaceViewModelTests {
  @Test("Quick Note explicit commit clears composer and persists once")
  func quickNoteCommit() async throws {
    let repository = WorkspaceRepository(
      database: try AppDatabase(inMemoryNamed: UUID().uuidString)
    )
    let model = AppShellViewModel(repository: repository)
    model.start()
    model.setQuickNoteDraft("Captured thought")
    model.commitQuickNoteIfNeeded()

    try await eventually {
      model.snapshot.quickNotes.count == 1 && model.snapshot.draft == nil
    }
    #expect(model.quickNoteDraft.isEmpty)
    #expect(model.snapshot.quickNotes.first?.body == "Captured thought")
    model.stop()
  }

  @Test("Quick Note Enter submit semantics create one note and keep capture ready")
  func quickNoteEnterSubmitSemantics() async throws {
    let repository = WorkspaceRepository(
      database: try AppDatabase(inMemoryNamed: UUID().uuidString)
    )
    let model = AppShellViewModel(repository: repository)
    model.start()
    model.setQuickNoteDraft("First capture")
    model.commitQuickNoteIfNeeded()
    model.commitQuickNoteIfNeeded()

    try await eventually {
      model.snapshot.quickNotes.count == 1 && model.quickNoteDraft.isEmpty
    }
    #expect(model.snapshot.quickNotes[0].body == "First capture")
    #expect(!model.snapshot.quickNotes[0].body.contains("\n"))
    #expect(model.focusRequestID == 1)

    model.setQuickNoteDraft("Second capture")
    model.commitQuickNoteIfNeeded()
    try await eventually {
      model.snapshot.quickNotes.map(\.body) == ["First capture", "Second capture"]
    }
    #expect(model.quickNoteDraft.isEmpty)
    #expect(model.focusRequestID == 2)
    model.stop()
  }

  @Test("Settings presentation emits dismiss-state changes")
  func settingsDismissState() async throws {
    let repository = WorkspaceRepository(
      database: try AppDatabase(inMemoryNamed: UUID().uuidString)
    )
    let model = AppShellViewModel(repository: repository)
    var states: [Bool] = []
    model.onSettingsPresentationChanged = { states.append($0) }

    model.isSettingsPresented = true
    model.isSettingsPresented = false
    #expect(states == [true, false])
  }

  @Test("New Task toggle remains presented until explicitly cancelled")
  func newTaskTogglePresentation() throws {
    let model = AppShellViewModel(
      repository: WorkspaceRepository(
        database: try AppDatabase(inMemoryNamed: UUID().uuidString)
      )
    )

    #expect(!model.isCreatingTask)
    model.toggleNewTaskCreation()
    #expect(model.isCreatingTask)
    #expect(model.newTaskTitleFocusRequestID == 1)
    model.cancelNewTaskCreation()
    #expect(!model.isCreatingTask)
  }

  @Test("Settings remains presented until explicitly dismissed")
  func settingsPresentationPersists() throws {
    let model = AppShellViewModel(
      repository: WorkspaceRepository(
        database: try AppDatabase(inMemoryNamed: UUID().uuidString)
      )
    )

    #expect(!model.isSettingsPresented)
    model.isSettingsPresented = true
    #expect(model.isSettingsPresented)
    model.isSettingsPresented = false
    #expect(!model.isSettingsPresented)
  }

  @Test("Routed Quick Note drag attaches the same note transactionally")
  func routedNoteAttachment() async throws {
    let repository = WorkspaceRepository(
      database: try AppDatabase(inMemoryNamed: UUID().uuidString)
    )
    let task = try await repository.createMainTask(title: "Target", effort: .one)
    let note = try #require(
      try await repository.commitDraft(body: "Move me", revision: UUID())
    )
    let model = AppShellViewModel(repository: repository)
    model.routedNoteDragCommitted(
      noteID: note.id,
      insertionIndex: nil,
      taskTargetID: task.id
    )
    try await eventually {
      let snapshot = try await repository.snapshot()
      return snapshot.quickNotes.isEmpty
        && snapshot.attachedNotesByTask[task.id]?.first?.id == note.id
    }
  }

  @Test("Routed Step drag commits one geometry-derived order")
  func routedStepReorder() async throws {
    let repository = WorkspaceRepository(
      database: try AppDatabase(inMemoryNamed: UUID().uuidString)
    )
    let task = try await repository.createMainTask(title: "Task", effort: .two)
    let first = try await repository.createStep(mainTaskID: task.id, title: "First")
    let second = try await repository.createStep(mainTaskID: task.id, title: "Second")
    let model = AppShellViewModel(repository: repository)
    model.start()
    try await eventually {
      model.snapshot.stepsByTask[task.id]?.count == 2
    }
    model.secondaryContext = .task(id: task.id)
    model.routedStepDragCommitted(stepID: first.id, insertionIndex: 2)
    try await eventually {
      try await repository.snapshot().stepsByTask[task.id]?.map(\.id)
        == [second.id, first.id]
    }
    model.stop()
  }

  @Test("Main Task composer visibly starts at Effort 1 and creates with one submit")
  func taskUsesDefaultEffort() async throws {
    let repository = WorkspaceRepository(
      database: try AppDatabase(inMemoryNamed: UUID().uuidString)
    )
    let model = AppShellViewModel(repository: repository)
    model.beginNewTaskCreation()
    model.newTaskTitle = "Default effort"
    #expect(model.newTaskEffort == .one)
    model.createMainTask()
    try await eventually {
      try await repository.snapshot().activeTasks.count == 1
    }
    #expect(try await repository.snapshot().activeTasks.first?.effort == .one)
  }

  @Test("New Task opens with title focus ready for immediate typing")
  func newTaskOpensWithTitleFocus() throws {
    let model = AppShellViewModel(
      repository: WorkspaceRepository(
        database: try AppDatabase(inMemoryNamed: UUID().uuidString)
      )
    )

    #expect(!model.isCreatingTask)
    #expect(model.newTaskTitleFocusRequestID == 0)
    model.beginNewTaskCreation()
    #expect(model.isCreatingTask)
    #expect(model.newTaskEffort == .one)
    #expect(model.newTaskTitleFocusRequestID == 1)
  }

  @Test("Empty or whitespace title never creates a default-effort task")
  func emptyTitleDoesNotCreateTask() async throws {
    let repository = WorkspaceRepository(database: try AppDatabase(inMemoryNamed: UUID().uuidString))
    let model = AppShellViewModel(repository: repository)
    model.beginNewTaskCreation()
    model.createMainTask()
    model.newTaskTitle = " \n  "
    model.createMainTask()
    try await Task.sleep(for: .milliseconds(30))
    #expect(try await repository.snapshot().activeTasks.isEmpty)
    #expect(model.isCreatingTask)
    #expect(model.newTaskEffort == .one)
  }

  @Test("Effort arrows override the default before creation")
  func newTaskArrowSelection() async throws {
    let repository = WorkspaceRepository(database: try AppDatabase(inMemoryNamed: UUID().uuidString))
    let model = AppShellViewModel(repository: repository)
    model.beginNewTaskCreation()
    model.newTaskTitle = "Keyboard task"
    #expect(model.newTaskEffort == .one)
    model.moveNewTaskEffortSelection(by: 1)
    #expect(model.newTaskEffort == .two)
    model.moveNewTaskEffortSelection(by: 1)
    #expect(model.newTaskEffort == .three)
    model.moveNewTaskEffortSelection(by: -1)
    #expect(model.newTaskEffort == .two)
    #expect(try await repository.snapshot().activeTasks.isEmpty)
    model.createMainTask()
    try await eventually {
      try await repository.snapshot().activeTasks.first?.effort == .two
    }
    model.beginNewTaskCreation()
    #expect(model.newTaskEffort == .one)
    model.cancelNewTaskCreation()
    #expect(model.newTaskEffort == nil)
  }

  @Test("Existing effort editor starts at saved value and cancellation cannot change it")
  func existingEffortSelectionDraft() {
    var selection = EffortSelection(saved: .three)
    #expect(selection.candidate == .three)
    selection.move(by: 1)
    #expect(selection.candidate == .four)
    selection.move(by: 1)
    #expect(selection.candidate == .four)
    selection.move(by: -1)
    #expect(selection.candidate == .three)
    #expect(selection.saved == .three)
    selection = EffortSelection(saved: .three)
    #expect(selection.candidate == .three)
  }

  @Test("New Task number key selects Effort and one Return creates once")
  func newTaskKeyboardEffortCreatesOnce() async throws {
    let repository = WorkspaceRepository(
      database: try AppDatabase(inMemoryNamed: UUID().uuidString)
    )
    let model = AppShellViewModel(repository: repository)
    model.start()
    model.beginNewTaskCreation()
    model.newTaskTitle = "Prepare presentation"
    #expect(model.selectNewTaskEffortFromKeyboard(2))
    #expect(model.newTaskEffort == .two)
    #expect(try await repository.snapshot().activeTasks.isEmpty)
    model.createMainTask()
    model.createMainTask()
    try await eventually {
      model.snapshot.activeTasks.count == 1 && !model.isCreatingTask
    }
    #expect(model.snapshot.activeTasks[0].title == "Prepare presentation")
    #expect(model.snapshot.activeTasks[0].effort == .two)
    #expect(model.newTaskTitle.isEmpty)
    #expect(model.newTaskEffort == nil)
    model.stop()
  }

  @Test("New Task number keys select only 1 through 4 while composer is open")
  func newTaskKeyboardEffortScope() async throws {
    let repository = WorkspaceRepository(
      database: try AppDatabase(inMemoryNamed: UUID().uuidString)
    )
    let model = AppShellViewModel(repository: repository)

    #expect(!model.selectNewTaskEffortFromKeyboard(1))

    model.beginNewTaskCreation()
    model.newTaskTitle = "Scoped shortcuts"
    #expect(!model.selectNewTaskEffortFromKeyboard(0))
    #expect(!model.selectNewTaskEffortFromKeyboard(5))
    #expect(model.newTaskEffort == .one)
    #expect(try await repository.snapshot().activeTasks.isEmpty)

    for value in 1...4 {
      let isolatedRepository = WorkspaceRepository(
        database: try AppDatabase(inMemoryNamed: UUID().uuidString)
      )
      let isolatedModel = AppShellViewModel(repository: isolatedRepository)
      isolatedModel.start()
      isolatedModel.beginNewTaskCreation()
      isolatedModel.newTaskTitle = "Effort \(value)"
      #expect(isolatedModel.selectNewTaskEffortFromKeyboard(value))
      #expect(isolatedModel.newTaskEffort?.rawValue == value)
      #expect(try await isolatedRepository.snapshot().activeTasks.isEmpty)
      isolatedModel.createMainTask()
      try await eventually {
        try await isolatedRepository.snapshot().activeTasks.first?.effort?.rawValue
          == value
      }
      isolatedModel.stop()
    }
  }

  @Test("New Task effort presentation treats only numbers as selectable")
  func newTaskEffortPresentationScope() {
    #expect(NewTaskEffortSelectionPresentation.label == "Effort")
    #expect(NewTaskEffortSelectionPresentation.selectableLabels == ["1", "2", "3", "4"])
    #expect(!NewTaskEffortSelectionPresentation.selectableLabels.contains("Effort"))
  }

  @Test("New Task mouse creation flow still works and resets")
  func newTaskMouseCreationStillWorks() async throws {
    let repository = WorkspaceRepository(
      database: try AppDatabase(inMemoryNamed: UUID().uuidString)
    )
    let model = AppShellViewModel(repository: repository)
    model.start()
    model.beginNewTaskCreation()
    model.newTaskTitle = "Mouse task"
    model.newTaskEffort = .four
    #expect(try await repository.snapshot().activeTasks.isEmpty)
    model.createMainTask()

    try await eventually {
      model.snapshot.activeTasks.count == 1 && !model.isCreatingTask
    }
    #expect(model.snapshot.activeTasks[0].title == "Mouse task")
    #expect(model.snapshot.activeTasks[0].effort == .four)
    #expect(model.newTaskTitle.isEmpty)
    #expect(model.newTaskEffort == nil)
    model.stop()
  }

  @Test("Task Detail effort picker uses numeric labels and updates effort")
  func taskDetailEffortPickerLabelsAndUpdate() async throws {
    let repository = WorkspaceRepository(
      database: try AppDatabase(inMemoryNamed: UUID().uuidString)
    )
    let task = try await repository.createMainTask(title: "Effort task", effort: .one)
    let model = AppShellViewModel(repository: repository)
    model.start()

    #expect(Effort.pickerLabels == ["1", "2", "3", "4"])
    #expect(!Effort.pickerLabels.contains { $0.contains("Effort") })
    model.updateMainTask(id: task.id, effort: .four)
    try await eventually {
      model.snapshot.activeTasks.first?.effort == .four
    }
    model.stop()
  }

  @Test("Main Task density setting persists")
  func mainTaskDensityPersists() throws {
    let suiteName = "EasyFlowTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let model = AppShellViewModel(
      repository: WorkspaceRepository(
        database: try AppDatabase(inMemoryNamed: UUID().uuidString)
      ),
      userDefaults: defaults
    )
    #expect(model.mainTaskDensity == .compact)
    model.mainTaskDensity = .comfortable

    let reloaded = AppShellViewModel(
      repository: WorkspaceRepository(
        database: try AppDatabase(inMemoryNamed: UUID().uuidString)
      ),
      userDefaults: defaults
    )
    #expect(reloaded.mainTaskDensity == .comfortable)
  }

  private func eventually(
    timeout: Duration = .seconds(1),
    condition: @escaping () async throws -> Bool
  ) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
      if try await condition() { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Condition did not become true before timeout")
  }
}
