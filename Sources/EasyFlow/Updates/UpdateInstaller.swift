import AppKit
import Foundation

struct UpdateInstallRequest: Codable, Sendable {
  let destinationPath: String
  let archivePath: String
  let manifestPath: String
  let signaturePath: String
  let version: String
  let runningPID: Int32
}

enum UpdateInstallationError: Error {
  case unsafeDestination
  case appStillRunning
  case invalidRequest
}

enum UpdateInstaller {
  static func canReplaceAutomatically(at destination: URL) -> Bool {
    let url = destination.standardizedFileURL
    guard url.isFileURL, url.lastPathComponent == "EasyFlow.app",
      !url.path.contains("/AppTranslocation/"),
      !url.path.hasPrefix("/Volumes/"),
      FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path),
      (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
      let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
      info["CFBundleIdentifier"] as? String == UpdateSecurity.bundleIdentifier
    else { return false }
    return true
  }

  static func validateArchive(at archive: URL) throws {
    let listing = try unzipListing(archive: archive, flags: ["-Z1"])
    let names = listing.split(separator: "\n").map(String.init)
    try UpdateSecurity.validateArchiveEntries(names)
    let details = try unzipListing(archive: archive, flags: ["-Z", "-l"])
    let rows = details.split(separator: "\n").filter { line in
      guard let first = line.first else { return false }
      return first == "-" || first == "d" || first == "l"
    }
    guard rows.count == names.count else { throw UpdateSecurityError.invalidArchive }
    var uncompressedBytes: Int64 = 0
    for row in rows {
      guard row.first == "-" || row.first == "d" else { throw UpdateSecurityError.invalidArchive }
      let fields = row.split(whereSeparator: \.isWhitespace)
      guard fields.count >= 4, let size = Int64(fields[3]), size >= 0,
        size <= UpdateSecurity.maximumArchiveBytes
      else { throw UpdateSecurityError.invalidArchive }
      uncompressedBytes += size
      guard uncompressedBytes <= 4 * UpdateSecurity.maximumArchiveBytes else {
        throw UpdateSecurityError.invalidArchive
      }
    }
  }

  private static func unzipListing(archive: URL, flags: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = flags + [archive.path]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0, data.count < 2_000_000,
      let listing = String(data: data, encoding: .utf8)
    else { throw UpdateSecurityError.invalidArchive }
    return listing
  }

  static func extractVerifiedArchive(
    archive: URL,
    into directory: URL,
    version: SemanticVersion
  ) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    try UpdateSecurity.runFixedTool("/usr/bin/ditto", arguments: ["-x", "-k", archive.path, directory.path])
    let app = directory.appendingPathComponent("EasyFlow.app", isDirectory: true)
    let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    guard contents == ["EasyFlow.app"] else { throw UpdateSecurityError.invalidArchive }
    try UpdateSecurity.validateApp(at: app, expectedVersion: version)
    return app
  }

  /// The only destructive operation moves the old app to a retained rollback
  /// path. A failed post-move validation restores it before returning.
  static func replace(
    source: URL,
    destination: URL,
    validate: (URL) throws -> Void
  ) throws -> URL {
    let fileManager = FileManager.default
    let parent = destination.deletingLastPathComponent()
    let stageDirectory = parent.appendingPathComponent(".easyflow-update-\(UUID().uuidString)")
    let staged = stageDirectory.appendingPathComponent("EasyFlow.app", isDirectory: true)
    let backup = parent.appendingPathComponent("EasyFlow.app.rollback-\(UUID().uuidString)")
    try fileManager.createDirectory(at: stageDirectory, withIntermediateDirectories: false)
    defer { try? fileManager.removeItem(at: stageDirectory) }
    try UpdateSecurity.runFixedTool("/usr/bin/ditto", arguments: [source.path, staged.path])
    try validate(staged)
    try fileManager.moveItem(at: destination, to: backup)
    do {
      try fileManager.moveItem(at: staged, to: destination)
      try validate(destination)
      return backup
    } catch {
      if fileManager.fileExists(atPath: destination.path) {
        try? fileManager.moveItem(at: destination,
          to: stageDirectory.appendingPathComponent("Failed.app"))
      }
      try fileManager.moveItem(at: backup, to: destination)
      throw error
    }
  }

  @MainActor
  static func runHelper(requestURL: URL, build: UpdateBuildIdentity = UpdateBuildIdentity()) -> Int32 {
    var validatedDestination: URL?
    do {
      guard build.canInstallUpdates, let publicKey = build.publicKey,
        requestURL.isFileURL,
        let requestData = try? Data(contentsOf: requestURL), requestData.count < 16_384,
        let request = try? JSONDecoder().decode(UpdateInstallRequest.self, from: requestData),
        let version = SemanticVersion(request.version),
        request.runningPID > 0
      else { throw UpdateInstallationError.invalidRequest }
      let destination = URL(fileURLWithPath: request.destinationPath).standardizedFileURL
      guard canReplaceAutomatically(at: destination),
        let info = NSDictionary(contentsOf: destination.appendingPathComponent("Contents/Info.plist")),
        info["EasyFlowBuildChannel"] as? String == UpdateBuildChannel.publicRelease.rawValue,
        let currentVersion = SemanticVersion(info["CFBundleShortVersionString"] as? String ?? ""),
        version > currentVersion
      else { throw UpdateInstallationError.unsafeDestination }
      validatedDestination = destination
      let archive = URL(fileURLWithPath: request.archivePath).standardizedFileURL
      let manifest = try Data(contentsOf: URL(fileURLWithPath: request.manifestPath))
      let signature = try Data(contentsOf: URL(fileURLWithPath: request.signaturePath))
      _ = try UpdateSecurity.verify(manifestData: manifest, signatureData: signature,
        archiveURL: archive, publicKeyData: publicKey, expectedVersion: version)
      try validateArchive(at: archive)
      for _ in 0..<600 {
        let running = NSRunningApplication.runningApplications(
          withBundleIdentifier: UpdateSecurity.bundleIdentifier
        ).contains { $0.processIdentifier == request.runningPID && !$0.isTerminated }
        if !running { break }
        Thread.sleep(forTimeInterval: 0.1)
      }
      let stillRunning = NSRunningApplication.runningApplications(
        withBundleIdentifier: UpdateSecurity.bundleIdentifier
      ).contains { $0.bundleURL?.standardizedFileURL == destination }
      guard !stillRunning else { throw UpdateInstallationError.appStillRunning }
      let extracted = try extractVerifiedArchive(
        archive: archive,
        into: requestURL.deletingLastPathComponent().appendingPathComponent("Extracted"),
        version: version
      )
      let backup = try replace(source: extracted, destination: destination) {
        try UpdateSecurity.validateApp(at: $0, expectedVersion: version)
      }
      do {
        try UpdateSecurity.runFixedTool("/usr/bin/open", arguments: ["-n", destination.path])
      } catch {
        showFailure(
          title: "EasyFlow was updated but could not open automatically.",
          detail: "Open the installed app in Finder. macOS may require a first-launch confirmation. The previous app is retained at \(backup.path)."
        )
        return 1
      }
      return 0
    } catch {
      if let validatedDestination,
        FileManager.default.fileExists(atPath: validatedDestination.path) {
        try? UpdateSecurity.runFixedTool("/usr/bin/open", arguments: ["-n", validatedDestination.path])
      }
      showFailure(
        title: "EasyFlow could not install the update.",
        detail: "The previous app was left in place or restored. Download the release manually from GitHub if this continues."
      )
      return 1
    }
  }

  @MainActor private static func showFailure(title: String, detail: String) {
    NSApplication.shared.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = detail
    alert.runModal()
  }
}
