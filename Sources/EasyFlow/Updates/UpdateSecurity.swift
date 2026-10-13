import CryptoKit
import Foundation

struct SignedUpdateManifest: Codable, Equatable, Sendable {
  let repository: String
  let version: String
  let bundleIdentifier: String
  let archiveName: String
  let archiveSHA256: String
  let archiveBytes: Int64
}

enum UpdateSecurityError: Error, Equatable {
  case missingTrustKey
  case invalidSignature
  case invalidManifest
  case invalidArchive
  case invalidApp
}

enum UpdateSecurity {
  static let bundleIdentifier = "io.github.natizh.easyflow"
  static let maximumArchiveBytes: Int64 = 250 * 1024 * 1024

  static func verify(
    manifestData: Data,
    signatureData: Data,
    archiveURL: URL,
    publicKeyData: Data,
    expectedVersion: SemanticVersion
  ) throws -> SignedUpdateManifest {
    guard publicKeyData.count == 32,
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    else { throw UpdateSecurityError.missingTrustKey }
    guard manifestData.count <= 16_384,
      let signatureText = String(data: signatureData, encoding: .utf8),
      let signature = Data(base64Encoded: signatureText.trimmingCharacters(in: .whitespacesAndNewlines)),
      signature.count == 64,
      publicKey.isValidSignature(signature, for: manifestData)
    else { throw UpdateSecurityError.invalidSignature }
    guard let manifest = try? JSONDecoder().decode(SignedUpdateManifest.self, from: manifestData),
      manifest.repository == GitHubUpdateFeed.repository,
      manifest.bundleIdentifier == bundleIdentifier,
      manifest.archiveName == GitHubUpdateFeed.archiveName,
      SemanticVersion(manifest.version) == expectedVersion,
      manifest.archiveSHA256.count == 64,
      manifest.archiveSHA256.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
      manifest.archiveBytes > 0,
      manifest.archiveBytes <= maximumArchiveBytes
    else { throw UpdateSecurityError.invalidManifest }

    let values = try archiveURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard archiveURL.lastPathComponent == GitHubUpdateFeed.archiveName,
      values.isRegularFile == true, values.isSymbolicLink != true,
      Int64(values.fileSize ?? -1) == manifest.archiveBytes,
      try sha256(archiveURL) == manifest.archiveSHA256
    else { throw UpdateSecurityError.invalidArchive }
    return manifest
  }

  static func sha256(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var digest = SHA256()
    while true {
      let bytes = try handle.read(upToCount: 1024 * 1024) ?? Data()
      if bytes.isEmpty { break }
      digest.update(data: bytes)
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }

  static func validateArchiveEntries(_ names: [String]) throws {
    guard !names.isEmpty, names.count <= 10_000 else { throw UpdateSecurityError.invalidArchive }
    var seen = Set<String>()
    var hasExecutable = false
    for name in names {
      guard name.hasPrefix("EasyFlow.app/"), !name.contains("\\"), !name.contains("\0"),
        seen.insert(name).inserted
      else { throw UpdateSecurityError.invalidArchive }
      let components = name.split(separator: "/", omittingEmptySubsequences: false)
      guard components.allSatisfy({ $0 != "." && $0 != ".." }),
        !components.dropLast().contains("")
      else { throw UpdateSecurityError.invalidArchive }
      if name == "EasyFlow.app/Contents/MacOS/EasyFlow" { hasExecutable = true }
    }
    guard hasExecutable else { throw UpdateSecurityError.invalidArchive }
  }

  static func validateApp(at url: URL, expectedVersion: SemanticVersion) throws {
    guard url.pathExtension == "app", url.lastPathComponent == "EasyFlow.app",
      FileManager.default.fileExists(atPath: url.path)
    else { throw UpdateSecurityError.invalidApp }
    let root = url.standardizedFileURL
    guard let enumerator = FileManager.default.enumerator(
      at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []
    ) else { throw UpdateSecurityError.invalidApp }
    for case let file as URL in enumerator {
      if (try file.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == true {
        throw UpdateSecurityError.invalidApp
      }
    }
    let infoURL = root.appendingPathComponent("Contents/Info.plist")
    guard let info = NSDictionary(contentsOf: infoURL),
      info["CFBundleIdentifier"] as? String == bundleIdentifier,
      SemanticVersion(info["CFBundleShortVersionString"] as? String ?? "") == expectedVersion,
      info["CFBundleExecutable"] as? String == "EasyFlow",
      info["EasyFlowBuildChannel"] as? String == UpdateBuildChannel.publicRelease.rawValue,
      FileManager.default.isExecutableFile(atPath: root.appendingPathComponent("Contents/MacOS/EasyFlow").path)
    else { throw UpdateSecurityError.invalidApp }
    try runFixedTool("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", root.path])
  }

  static func runFixedTool(_ executable: String, arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw UpdateSecurityError.invalidArchive }
  }
}
