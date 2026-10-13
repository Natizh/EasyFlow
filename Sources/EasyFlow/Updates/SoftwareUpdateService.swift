import AppKit
import Combine
import Foundation

protocol UpdateReleaseClient: Sendable {
  func latestRelease() async throws -> Data
  func data(from url: URL) async throws -> Data
  func download(from url: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL
}

struct GitHubReleaseClient: UpdateReleaseClient {
  private let session: URLSession

  init(session: URLSession = .shared) { self.session = session }

  func latestRelease() async throws -> Data {
    try await data(from: GitHubUpdateFeed.latestURL)
  }

  func data(from url: URL) async throws -> Data {
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("EasyFlow-Updater", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await session.data(for: request)
    try Self.validate(response)
    guard data.count <= 1_000_000 else { throw UpdateFeedError.invalidResponse }
    return data
  }

  func download(from url: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
    request.setValue("EasyFlow-Updater", forHTTPHeaderField: "User-Agent")
    let delegate = UpdateDownloadDelegate(onProgress: onProgress)
    let downloadSession = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    defer { downloadSession.finishTasksAndInvalidate() }
    return try await withCheckedThrowingContinuation { continuation in
      delegate.continuation = continuation
      downloadSession.downloadTask(with: request).resume()
    }
  }

  fileprivate static func validate(_ response: URLResponse) throws {
    guard let response = response as? HTTPURLResponse else { throw UpdateFeedError.invalidResponse }
    let host = response.url?.host ?? ""
    guard response.url?.scheme == "https",
      host == "github.com" || host == "api.github.com"
        || host == "release-assets.githubusercontent.com"
        || host == "objects.githubusercontent.com"
    else { throw UpdateFeedError.invalidResponse }
    if response.statusCode == 429 || (response.statusCode == 403
      && (response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0"
        || response.value(forHTTPHeaderField: "Retry-After") != nil)) {
      throw UpdateFeedError.rateLimited
    }
    guard response.statusCode == 200 else { throw UpdateFeedError.serverUnavailable }
  }
}

private final class UpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  let onProgress: @Sendable (Double) -> Void
  private let lock = NSLock()
  private var pending: CheckedContinuation<URL, Error>?

  init(onProgress: @escaping @Sendable (Double) -> Void) {
    self.onProgress = onProgress
  }

  var continuation: CheckedContinuation<URL, Error>? {
    get { lock.withLock { pending } }
    set { lock.withLock { pending = newValue } }
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    if totalBytesExpectedToWrite > 0 {
      onProgress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL) {
    do {
      guard let response = downloadTask.response else { throw UpdateFeedError.invalidResponse }
      try GitHubReleaseClient.validate(response)
      let retained = FileManager.default.temporaryDirectory
        .appendingPathComponent("EasyFlow-download-\(UUID().uuidString)")
      try FileManager.default.moveItem(at: location, to: retained)
      onProgress(1)
      complete(.success(retained))
    } catch {
      complete(.failure(error))
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error { complete(.failure(error)) }
  }

  private func complete(_ result: Result<URL, Error>) {
    let continuation = lock.withLock { () -> CheckedContinuation<URL, Error>? in
      defer { pending = nil }
      return pending
    }
    continuation?.resume(with: result)
  }
}

enum SoftwareUpdatePhase: Equatable {
  case idle
  case checking
  case upToDate
  case available(UpdateCandidate)
  case downloading
  case verifying
  case installing
  case manualInstall(URL)
  case failed(String)
}

enum UpdatePreviewScenario {
  case available
  case downloading
  case failed
  case reset
}

@MainActor
final class SoftwareUpdateService: ObservableObject {
  @Published private(set) var phase: SoftwareUpdatePhase = .idle
  @Published private(set) var downloadProgress: Double = 0
  @Published private(set) var lastCheckedAt: Date?
  @Published private(set) var automaticChecksEnabled: Bool
  @Published private(set) var postponedVersion: String?

  let build: UpdateBuildIdentity
  private let client: any UpdateReleaseClient
  private let defaults: UserDefaults
  private var scheduleTask: Task<Void, Never>?
  private var checkIsRunning = false
  private var installIsRunning = false
  private var preparedDirectory: URL?

  static let automaticChecksKey = "automaticallyCheckForUpdates"
  static let lastAutomaticCheckKey = "lastAutomaticUpdateCheck"
  static let lastCheckKey = "lastSoftwareUpdateCheck"
  static let postponedVersionKey = "postponedUpdateVersion"

  init(
    build: UpdateBuildIdentity = UpdateBuildIdentity(),
    client: any UpdateReleaseClient = GitHubReleaseClient(),
    defaults: UserDefaults = .standard
  ) {
    self.build = build
    self.client = client
    self.defaults = defaults
    automaticChecksEnabled = defaults.object(forKey: Self.automaticChecksKey) as? Bool ?? true
    postponedVersion = defaults.string(forKey: Self.postponedVersionKey)
    lastCheckedAt = defaults.object(forKey: Self.lastCheckKey) as? Date
  }

  var isDevelopmentBuild: Bool { build.channel == .development }
  var hasNewBadge: Bool {
    if case .available(let candidate) = phase {
      return build.channel == .publicRelease && candidate.hasSignedAssets
        && postponedVersion != candidate.version.description
    }
    return false
  }

  func start() { scheduleAutomaticCheck() }

  func stop() {
    scheduleTask?.cancel()
    scheduleTask = nil
  }

  func setAutomaticChecksEnabled(_ enabled: Bool) {
    automaticChecksEnabled = enabled
    defaults.set(enabled, forKey: Self.automaticChecksKey)
    scheduleAutomaticCheck()
  }

  func postpone() {
    guard case .available(let candidate) = phase else { return }
    postponedVersion = candidate.version.description
    defaults.set(postponedVersion, forKey: Self.postponedVersionKey)
  }

  func check(manual: Bool = true) async {
    guard !checkIsRunning, !installIsRunning else { return }
    if !manual && (isDevelopmentBuild || !automaticChecksEnabled) { return }
    guard let installed = build.version else {
      phase = .failed("The installed version could not be read.")
      return
    }
    checkIsRunning = true
    phase = .checking
    let checkDate = Date()
    lastCheckedAt = checkDate
    defaults.set(checkDate, forKey: Self.lastCheckKey)
    if !manual { defaults.set(checkDate, forKey: Self.lastAutomaticCheckKey) }
    defer {
      checkIsRunning = false
      if !manual { scheduleAutomaticCheck() }
    }
    do {
      let data = try await client.latestRelease()
      switch try GitHubUpdateFeed.interpret(data, installed: installed) {
      case .upToDate: phase = .upToDate
      case .available(let candidate): phase = .available(candidate)
      }
    } catch UpdateFeedError.rateLimited {
      phase = .failed("GitHub's update check limit was reached. Try again later.")
    } catch {
      phase = .failed("Unable to check for updates. Check your connection and try again.")
    }
  }

  func install(_ candidate: UpdateCandidate) async {
    guard !installIsRunning, build.canInstallUpdates,
      candidate.hasSignedAssets,
      let archiveURL = candidate.archiveURL,
      let manifestURL = candidate.manifestURL,
      let signatureURL = candidate.signatureURL,
      let publicKey = build.publicKey
    else {
      phase = .failed("This build cannot install updates. Open the release page for manual installation.")
      return
    }
    installIsRunning = true
    defer { installIsRunning = false }
    do {
      phase = .downloading
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("EasyFlow-update-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      preparedDirectory = directory
      downloadProgress = 0
      let manifestData = try await client.data(from: manifestURL)
      let signatureData = try await client.data(from: signatureURL)
      let downloaded = try await client.download(from: archiveURL) { [weak self] fraction in
        Task { @MainActor in self?.downloadProgress = fraction }
      }
      let archive = directory.appendingPathComponent(GitHubUpdateFeed.archiveName)
      try FileManager.default.moveItem(at: downloaded, to: archive)
      phase = .verifying
      _ = try UpdateSecurity.verify(manifestData: manifestData, signatureData: signatureData,
        archiveURL: archive, publicKeyData: publicKey, expectedVersion: candidate.version)
      try manifestData.write(to: directory.appendingPathComponent(GitHubUpdateFeed.manifestName), options: .atomic)
      try signatureData.write(to: directory.appendingPathComponent(GitHubUpdateFeed.signatureName), options: .atomic)
      try UpdateInstaller.validateArchive(at: archive)

      let destination = Bundle.main.bundleURL.standardizedFileURL
      if !UpdateInstaller.canReplaceAutomatically(at: destination) {
        let extracted = try UpdateInstaller.extractVerifiedArchive(
          archive: archive, into: directory.appendingPathComponent("Manual"),
          version: candidate.version
        )
        phase = .manualInstall(extracted)
        return
      }
      let helper = directory.appendingPathComponent("Updater.app")
      try FileManager.default.copyItem(at: destination, to: helper)
      let request = UpdateInstallRequest(
        destinationPath: destination.path,
        archivePath: archive.path,
        manifestPath: directory.appendingPathComponent(GitHubUpdateFeed.manifestName).path,
        signaturePath: directory.appendingPathComponent(GitHubUpdateFeed.signatureName).path,
        version: candidate.version.description,
        runningPID: ProcessInfo.processInfo.processIdentifier
      )
      let requestURL = directory.appendingPathComponent("install-request.json")
      try JSONEncoder().encode(request).write(to: requestURL, options: .atomic)
      let process = Process()
      process.executableURL = helper.appendingPathComponent("Contents/MacOS/EasyFlow")
      process.arguments = ["--easyflow-install-update", requestURL.path]
      try process.run()
      phase = .installing
      NSApp.terminate(nil)
    } catch {
      if let preparedDirectory { try? FileManager.default.removeItem(at: preparedDirectory) }
      preparedDirectory = nil
      phase = .failed("The update could not be verified or prepared. Nothing was installed.")
    }
  }

  func revealManualInstall(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  func preview(_ scenario: UpdatePreviewScenario) {
    guard isDevelopmentBuild else { return }
    switch scenario {
    case .available:
      phase = .available(UpdateCandidate(
        version: SemanticVersion("9.9.9")!,
        notes: "Preview release notes for testing the Software Updates interface. No download or installation will occur.",
        releasePage: URL(string: "https://github.com/Natizh/easyflow/releases")!,
        archiveURL: URL(string: "https://github.com/Natizh/easyflow/releases/download/v9.9.9/EasyFlow.zip"),
        manifestURL: URL(string: "https://github.com/Natizh/easyflow/releases/download/v9.9.9/EasyFlow.update.json"),
        signatureURL: URL(string: "https://github.com/Natizh/easyflow/releases/download/v9.9.9/EasyFlow.update.sig")
      ))
    case .downloading:
      downloadProgress = 0.5
      phase = .downloading
    case .failed:
      phase = .failed("Preview: unable to check for updates.")
    case .reset:
      phase = .idle
    }
  }

  private func scheduleAutomaticCheck() {
    scheduleTask?.cancel()
    scheduleTask = nil
    guard automaticChecksEnabled, !isDevelopmentBuild else { return }
    let delay = UpdateSchedule.delay(
      lastCheck: defaults.object(forKey: Self.lastAutomaticCheckKey) as? Date,
      now: Date()
    )
    scheduleTask = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(delay)) } catch { return }
      await self?.check(manual: false)
    }
  }
}
