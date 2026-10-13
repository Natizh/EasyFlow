import AppKit
import CryptoKit
import Testing

@testable import EasyFlow

private actor FixtureUpdateClient: UpdateReleaseClient {
  var releaseData: Data
  var failure: Error?
  var checks = 0

  init(releaseData: Data, failure: Error? = nil) {
    self.releaseData = releaseData
    self.failure = failure
  }

  func latestRelease() async throws -> Data {
    checks += 1
    if let failure { throw failure }
    return releaseData
  }

  func data(from url: URL) async throws -> Data { throw UpdateFeedError.serverUnavailable }
  func download(from url: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
    throw UpdateFeedError.serverUnavailable
  }
  func count() -> Int { checks }
}

@Suite("Signed GitHub software updates")
struct SoftwareUpdateTests {
  @Test("Versions compare numerically and reject ambiguous tags")
  func semanticVersions() {
    #expect(SemanticVersion("1.4.2")! > SemanticVersion("1.4.1")!)
    #expect(SemanticVersion("1.5.0")! > SemanticVersion("1.4.9")!)
    #expect(SemanticVersion("1.10.0")! > SemanticVersion("1.9.0")!)
    #expect(SemanticVersion("v2.0.0") == SemanticVersion("2.0.0"))
    #expect(SemanticVersion("1.4.2-beta") == nil)
    #expect(SemanticVersion("1.4") == nil)
  }

  @Test("Only a newer published stable release is offered")
  func stableReleasePolicy() throws {
    let installed = SemanticVersion("1.4.1")!
    #expect(try GitHubUpdateFeed.interpret(releaseJSON("1.4.0"), installed: installed) == .upToDate)
    #expect(try GitHubUpdateFeed.interpret(releaseJSON("1.4.1"), installed: installed) == .upToDate)
    #expect(try GitHubUpdateFeed.interpret(releaseJSON("1.4.2", draft: true), installed: installed) == .upToDate)
    #expect(try GitHubUpdateFeed.interpret(releaseJSON("1.4.2", prerelease: true), installed: installed) == .upToDate)
    #expect(try GitHubUpdateFeed.interpret(releaseJSON("1.5.0-beta", prerelease: true), installed: installed) == .upToDate)
    if case .available(let candidate) = try GitHubUpdateFeed.interpret(releaseJSON("1.4.2"), installed: installed) {
      #expect(candidate.version == SemanticVersion("1.4.2"))
      #expect(candidate.hasSignedAssets)
    } else { Issue.record("Expected a newer stable release") }
  }

  @Test("Malformed feed and missing or untrusted assets fail closed")
  func feedValidation() throws {
    #expect(throws: UpdateFeedError.self) {
      try GitHubUpdateFeed.interpret(Data("{}".utf8), installed: SemanticVersion("1.4.1")!)
    }
    if case .available(let candidate) = try GitHubUpdateFeed.interpret(
      releaseJSON("1.4.2", signedAssets: false), installed: SemanticVersion("1.4.1")!
    ) {
      #expect(!candidate.hasSignedAssets)
    } else { Issue.record("Expected unsigned release to remain visible") }
    #expect(throws: UpdateFeedError.self) {
      try GitHubUpdateFeed.interpret(releaseJSON("1.4.2", foreignURL: true),
        installed: SemanticVersion("1.4.1")!)
    }
  }

  @Test("Automatic schedule waits ten seconds after launch and no more than daily")
  func schedule() {
    let now = Date(timeIntervalSince1970: 100_000)
    #expect(UpdateSchedule.delay(lastCheck: nil, now: now) == 10)
    #expect(UpdateSchedule.delay(lastCheck: now.addingTimeInterval(-3600), now: now) == 23 * 3600)
    #expect(UpdateSchedule.delay(lastCheck: now.addingTimeInterval(-2 * 86_400), now: now) == 10)
    #expect(UpdateSchedule.delay(lastCheck: now.addingTimeInterval(86_400), now: now) == 10)
  }

  @Test("Development builds never auto-check or install, while manual checks use the feed")
  @MainActor func developmentSafeguard() async throws {
    let client = FixtureUpdateClient(releaseData: releaseJSON("1.4.2"))
    let service = SoftwareUpdateService(
      build: UpdateBuildIdentity(channel: .development, version: SemanticVersion("1.4.1")),
      client: client,
      defaults: isolatedDefaults()
    )
    service.start()
    #expect(await client.count() == 0)
    await service.check(manual: false)
    #expect(await client.count() == 0)
    await service.check()
    #expect(await client.count() == 1)
    service.preview(.downloading)
    #expect(service.phase == .downloading)
    #expect(service.downloadProgress == 0.5)
    service.preview(.available)
    #expect(service.phase != .downloading)
    service.preview(.reset)
    #expect(service.phase == .idle)
    await service.check()
    if case .available(let candidate) = service.phase {
      await service.install(candidate)
      #expect(service.phase == .failed("This build cannot install updates. Open the release page for manual installation."))
    } else { Issue.record("Expected mock update") }
    service.stop()
  }

  @Test("Network and rate-limit failures are explicit; Later suppresses the same badge")
  @MainActor func errorsAndPostponement() async throws {
    let defaults = isolatedDefaults()
    let client = FixtureUpdateClient(releaseData: releaseJSON("1.4.2"))
    let service = SoftwareUpdateService(
      build: UpdateBuildIdentity(channel: .publicRelease, version: SemanticVersion("1.4.1"), publicKey: Data(repeating: 1, count: 32)),
      client: client, defaults: defaults
    )
    await service.check()
    #expect(service.hasNewBadge)
    service.postpone()
    #expect(!service.hasNewBadge)
    await service.check()
    #expect(!service.hasNewBadge)
    #expect(await client.count() == 2)
    let restored = SoftwareUpdateService(build: service.build, client: client, defaults: defaults)
    #expect(restored.postponedVersion == "1.4.2")
    restored.setAutomaticChecksEnabled(false)
    #expect(!SoftwareUpdateService(build: service.build, client: client, defaults: defaults).automaticChecksEnabled)

    let rateLimited = SoftwareUpdateService(build: service.build,
      client: FixtureUpdateClient(releaseData: Data(), failure: UpdateFeedError.rateLimited),
      defaults: isolatedDefaults())
    await rateLimited.check()
    #expect(rateLimited.phase == .failed("GitHub's update check limit was reached. Try again later."))
    let failed = SoftwareUpdateService(build: service.build,
      client: FixtureUpdateClient(releaseData: Data(), failure: UpdateFeedError.serverUnavailable),
      defaults: isolatedDefaults())
    await failed.check()
    #expect(failed.phase == .failed("Unable to check for updates. Check your connection and try again."))
  }

  @Test("Ed25519 signature authenticates the manifest and SHA-256 detects changed archives")
  func signedArtifactVerification() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let archive = directory.appendingPathComponent("EasyFlow.zip")
    try Data("fixture archive".utf8).write(to: archive)
    let privateKey = Curve25519.Signing.PrivateKey()
    let manifest = SignedUpdateManifest(
      repository: GitHubUpdateFeed.repository, version: "1.4.2",
      bundleIdentifier: UpdateSecurity.bundleIdentifier, archiveName: GitHubUpdateFeed.archiveName,
      archiveSHA256: try UpdateSecurity.sha256(archive), archiveBytes: 15
    )
    let data = try JSONEncoder().encode(manifest)
    let signature = Data(try privateKey.signature(for: data).base64EncodedString().utf8)
    #expect(try UpdateSecurity.verify(manifestData: data, signatureData: signature,
      archiveURL: archive, publicKeyData: privateKey.publicKey.rawRepresentation,
      expectedVersion: SemanticVersion("1.4.2")!) == manifest)
    #expect(throws: UpdateSecurityError.self) {
      try UpdateSecurity.verify(manifestData: Data("tampered".utf8), signatureData: signature,
        archiveURL: archive, publicKeyData: privateKey.publicKey.rawRepresentation,
        expectedVersion: SemanticVersion("1.4.2")!)
    }
    try Data("tampered archive".utf8).write(to: archive)
    #expect(throws: UpdateSecurityError.self) {
      try UpdateSecurity.verify(manifestData: data, signatureData: signature,
        archiveURL: archive, publicKeyData: privateKey.publicKey.rawRepresentation,
        expectedVersion: SemanticVersion("1.4.2")!)
    }
  }

  @Test("Wrong signed bundle identity and version cannot pass verification")
  func signedMetadataIdentity() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let archive = directory.appendingPathComponent("EasyFlow.zip")
    try Data("payload".utf8).write(to: archive)
    let key = Curve25519.Signing.PrivateKey()
    for manifest in [
      SignedUpdateManifest(repository: GitHubUpdateFeed.repository, version: "1.4.2",
        bundleIdentifier: "example.invalid", archiveName: GitHubUpdateFeed.archiveName,
        archiveSHA256: try UpdateSecurity.sha256(archive), archiveBytes: 7),
      SignedUpdateManifest(repository: GitHubUpdateFeed.repository, version: "1.4.3",
        bundleIdentifier: UpdateSecurity.bundleIdentifier, archiveName: GitHubUpdateFeed.archiveName,
        archiveSHA256: try UpdateSecurity.sha256(archive), archiveBytes: 7),
    ] {
      let data = try JSONEncoder().encode(manifest)
      let signature = Data(try key.signature(for: data).base64EncodedString().utf8)
      #expect(throws: UpdateSecurityError.self) {
        try UpdateSecurity.verify(manifestData: data, signatureData: signature,
          archiveURL: archive, publicKeyData: key.publicKey.rawRepresentation,
          expectedVersion: SemanticVersion("1.4.2")!)
      }
    }
  }

  @Test("Extracted app with wrong bundle ID or version is rejected before replacement")
  func extractedAppIdentity() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let app = directory.appendingPathComponent("EasyFlow.app")
    let binary = app.appendingPathComponent("Contents/MacOS/EasyFlow")
    try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try Data("binary".utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
    let info = app.appendingPathComponent("Contents/Info.plist")
    func writeInfo(bundleID: String, version: String) {
      let values: NSDictionary = [
        "CFBundleIdentifier": bundleID,
        "CFBundleShortVersionString": version,
        "CFBundleExecutable": "EasyFlow",
        "EasyFlowBuildChannel": "public",
      ]
      _ = values.write(to: info, atomically: true)
    }
    writeInfo(bundleID: "invalid.bundle", version: "1.4.2")
    #expect(throws: UpdateSecurityError.self) {
      try UpdateSecurity.validateApp(at: app, expectedVersion: SemanticVersion("1.4.2")!)
    }
    writeInfo(bundleID: UpdateSecurity.bundleIdentifier, version: "1.4.1")
    #expect(throws: UpdateSecurityError.self) {
      try UpdateSecurity.validateApp(at: app, expectedVersion: SemanticVersion("1.4.2")!)
    }
  }

  @Test("Interrupted download leaves the app untouched and reports a failure")
  @MainActor func interruptedDownload() async throws {
    let client = FixtureUpdateClient(releaseData: releaseJSON("1.4.2"))
    let service = SoftwareUpdateService(
      build: UpdateBuildIdentity(channel: .publicRelease,
        version: SemanticVersion("1.4.1"), publicKey: Data(repeating: 1, count: 32)),
      client: client, defaults: isolatedDefaults()
    )
    await service.check()
    guard case .available(let candidate) = service.phase else {
      Issue.record("Expected fixture update")
      return
    }
    await service.install(candidate)
    #expect(service.phase == .failed("The update could not be verified or prepared. Nothing was installed."))
  }

  @Test("Archive entries reject path traversal and unexpected roots")
  func archiveEntrySafety() throws {
    try UpdateSecurity.validateArchiveEntries(["EasyFlow.app/", "EasyFlow.app/Contents/MacOS/EasyFlow"])
    for names in [
      ["../outside", "EasyFlow.app/Contents/MacOS/EasyFlow"],
      ["EasyFlow.app/../outside", "EasyFlow.app/Contents/MacOS/EasyFlow"],
      ["Other.app/Contents/MacOS/EasyFlow"],
    ] {
      #expect(throws: UpdateSecurityError.self) { try UpdateSecurity.validateArchiveEntries(names) }
    }
  }

  @Test("ZIP inspection accepts an app-only archive and rejects symlink entries")
  func zipStructureSafety() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let app = directory.appendingPathComponent("EasyFlow.app")
    let executable = app.appendingPathComponent("Contents/MacOS/EasyFlow")
    try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try Data("test".utf8).write(to: executable)
    let safeArchive = directory.appendingPathComponent("safe.zip")
    try UpdateSecurity.runFixedTool("/usr/bin/ditto",
      arguments: ["-c", "-k", "--keepParent", app.path, safeArchive.path])
    try UpdateInstaller.validateArchive(at: safeArchive)
    try FileManager.default.createSymbolicLink(
      at: app.appendingPathComponent("Contents/link"), withDestinationURL: directory
    )
    let linkedArchive = directory.appendingPathComponent("linked.zip")
    try UpdateSecurity.runFixedTool("/usr/bin/ditto",
      arguments: ["-c", "-k", "--keepParent", app.path, linkedArchive.path])
    #expect(throws: UpdateSecurityError.self) {
      try UpdateInstaller.validateArchive(at: linkedArchive)
    }
  }

  @Test("Optional signed package verifies and replaces an isolated older app")
  func signedPackageSmoke() throws {
    guard let base = ProcessInfo.processInfo.environment["EASYFLOW_SIGNED_PACKAGE_FIXTURE"] else {
      return
    }
    let directory = URL(fileURLWithPath: base)
    let assets = FileManager.default.fileExists(atPath: directory.appendingPathComponent("EasyFlow.zip").path)
      ? directory : directory.appendingPathComponent("dist")
    let archive = assets.appendingPathComponent("EasyFlow.zip")
    let manifest = try Data(contentsOf: assets.appendingPathComponent("EasyFlow.update.json"))
    let metadata = try JSONDecoder().decode(SignedUpdateManifest.self, from: manifest)
    let signature = try Data(contentsOf: assets.appendingPathComponent("EasyFlow.update.sig"))
    let keyURL = ProcessInfo.processInfo.environment["EASYFLOW_PUBLIC_KEY_FIXTURE"]
      .map { URL(fileURLWithPath: $0) }
      ?? directory.appendingPathComponent("keys/update-public-key.txt")
    let keyText = try String(contentsOf: keyURL, encoding: .utf8)
    let key = try #require(Data(base64Encoded: keyText.trimmingCharacters(in: .whitespacesAndNewlines)))
    let version = try #require(SemanticVersion(metadata.version))
    _ = try UpdateSecurity.verify(manifestData: manifest, signatureData: signature,
      archiveURL: archive, publicKeyData: key, expectedVersion: version)
    try UpdateInstaller.validateArchive(at: archive)
    let extraction = FileManager.default.temporaryDirectory
      .appendingPathComponent("EasyFlow-signed-smoke-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: extraction) }
    let app = try UpdateInstaller.extractVerifiedArchive(archive: archive,
      into: extraction, version: version)
    #expect(FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/MacOS/EasyFlow").path))
    let bundle = try #require(Bundle(url: app))
    let build = UpdateBuildIdentity(bundle: bundle)
    #expect(build.channel == .publicRelease)
    #expect(build.version == version)
    #expect(build.publicKey == key)
    #expect(build.canInstallUpdates)

    // Exercise the signed B bundle against an isolated older A bundle. No app
    // launches and no production workspace files are opened by this test.
    let isolated = FileManager.default.temporaryDirectory
      .appendingPathComponent("EasyFlow-update-replacement-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: isolated) }
    try FileManager.default.createDirectory(at: isolated, withIntermediateDirectories: false)
    let installed = isolated.appendingPathComponent("EasyFlow.app")
    try FileManager.default.copyItem(at: app, to: installed)
    let plist = installed.appendingPathComponent("Contents/Info.plist")
    let oldInfo = try #require(NSMutableDictionary(contentsOf: plist))
    oldInfo["CFBundleShortVersionString"] = "1.4.9"
    oldInfo["CFBundleVersion"] = "8"
    #expect(oldInfo.write(to: plist, atomically: true))
    try UpdateSecurity.runFixedTool("/usr/bin/codesign",
      arguments: ["--force", "--deep", "--sign", "-", installed.path])
    let userData = isolated.appendingPathComponent("EasyFlow.sqlite")
    try Data("isolated workspace".utf8).write(to: userData)
    let backup = try UpdateInstaller.replace(source: app, destination: installed) {
      try UpdateSecurity.validateApp(at: $0, expectedVersion: version)
    }
    try UpdateSecurity.validateApp(at: installed, expectedVersion: version)
    let backupInfo = try #require(NSDictionary(contentsOf: backup.appendingPathComponent("Contents/Info.plist")))
    #expect(backupInfo["CFBundleShortVersionString"] as? String == "1.4.9")
    #expect(try String(contentsOf: userData, encoding: .utf8) == "isolated workspace")
  }

  @Test("Failed replacement restores the old app and leaves sibling user data untouched")
  func rollbackAndDataSafety() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("source/EasyFlow.app")
    let destination = directory.appendingPathComponent("installed/EasyFlow.app")
    let userData = directory.appendingPathComponent("installed/EasyFlow.sqlite")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    try Data("new".utf8).write(to: source.appendingPathComponent("marker"))
    try Data("old".utf8).write(to: destination.appendingPathComponent("marker"))
    try Data("workspace".utf8).write(to: userData)
    var validations = 0
    #expect(throws: UpdateSecurityError.self) {
      _ = try UpdateInstaller.replace(source: source, destination: destination) { _ in
        validations += 1
        if validations == 2 { throw UpdateSecurityError.invalidApp }
      }
    }
    #expect(try String(contentsOf: destination.appendingPathComponent("marker"), encoding: .utf8) == "old")
    #expect(try String(contentsOf: userData, encoding: .utf8) == "workspace")
    let backup = try UpdateInstaller.replace(source: source, destination: destination) { _ in }
    #expect(try String(contentsOf: destination.appendingPathComponent("marker"), encoding: .utf8) == "new")
    #expect(try String(contentsOf: backup.appendingPathComponent("marker"), encoding: .utf8) == "old")
    #expect(try String(contentsOf: userData, encoding: .utf8) == "workspace")
  }

  @Test("Automatic replacement accepts a writable app and rejects translocated or read-only locations")
  func destinationPolicy() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let app = directory.appendingPathComponent("EasyFlow.app")
    try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"),
      withIntermediateDirectories: true)
    let info: NSDictionary = ["CFBundleIdentifier": UpdateSecurity.bundleIdentifier]
    _ = info.write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true)
    #expect(UpdateInstaller.canReplaceAutomatically(at: app))
    #expect(!UpdateInstaller.canReplaceAutomatically(at:
      URL(fileURLWithPath: "/Volumes/ReadOnly/EasyFlow.app")))
    #expect(!UpdateInstaller.canReplaceAutomatically(at:
      URL(fileURLWithPath: "/private/var/folders/AppTranslocation/EasyFlow.app")))
  }

  private func releaseJSON(
    _ version: String, draft: Bool = false, prerelease: Bool = false,
    signedAssets: Bool = true, foreignURL: Bool = false
  ) -> Data {
    let tag = "v\(version)"
    let root = "https://github.com/Natizh/easyflow/releases/download/\(tag)/"
    let names = signedAssets
      ? [GitHubUpdateFeed.archiveName, GitHubUpdateFeed.manifestName, GitHubUpdateFeed.signatureName]
      : [GitHubUpdateFeed.archiveName]
    let assets = names.map { name in
      ["name": name, "state": "uploaded", "browser_download_url": root + name]
    }
    let value: [String: Any] = [
      "tag_name": tag,
      "html_url": foreignURL ? "https://example.invalid/release" : "https://github.com/Natizh/easyflow/releases/tag/\(tag)",
      "body": "Release notes",
      "draft": draft,
      "prerelease": prerelease,
      "assets": assets,
    ]
    return try! JSONSerialization.data(withJSONObject: value)
  }

  private func isolatedDefaults() -> UserDefaults {
    let name = "SoftwareUpdateTests.\(UUID().uuidString)"
    return UserDefaults(suiteName: name)!
  }

  private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("EasyFlowUpdaterTests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
  }
}
