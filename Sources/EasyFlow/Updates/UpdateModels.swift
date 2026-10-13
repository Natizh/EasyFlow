import Foundation

struct SemanticVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
  let major: Int
  let minor: Int
  let patch: Int

  init?(_ text: String) {
    let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3,
      parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
      let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2])
    else { return nil }
    self.major = major
    self.minor = minor
    self.patch = patch
  }

  var description: String { "\(major).\(minor).\(patch)" }

  static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.major != rhs.major { return lhs.major < rhs.major }
    if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
    return lhs.patch < rhs.patch
  }
}

enum UpdateBuildChannel: String, Sendable {
  case development
  case publicRelease = "public"
}

struct UpdateBuildIdentity: Sendable {
  let channel: UpdateBuildChannel
  let version: SemanticVersion?
  let buildNumber: String
  let publicKey: Data?

  init(bundle: Bundle = .main) {
    channel = UpdateBuildChannel(rawValue: bundle.object(forInfoDictionaryKey: "EasyFlowBuildChannel") as? String ?? "development") ?? .development
    version = SemanticVersion(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
    buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    publicKey = (bundle.object(forInfoDictionaryKey: "EasyFlowUpdatePublicKey") as? String)
      .flatMap { Data(base64Encoded: $0) }
  }

  init(channel: UpdateBuildChannel, version: SemanticVersion?, buildNumber: String = "test", publicKey: Data? = nil) {
    self.channel = channel
    self.version = version
    self.buildNumber = buildNumber
    self.publicKey = publicKey
  }

  var canInstallUpdates: Bool { channel == .publicRelease && publicKey?.count == 32 && version != nil }
}

struct UpdateCandidate: Equatable, Sendable {
  let version: SemanticVersion
  let notes: String
  let releasePage: URL
  let archiveURL: URL?
  let manifestURL: URL?
  let signatureURL: URL?

  var hasSignedAssets: Bool { archiveURL != nil && manifestURL != nil && signatureURL != nil }
}

enum UpdateDiscoveryResult: Equatable, Sendable {
  case upToDate
  case available(UpdateCandidate)
}

enum UpdateFeedError: Error, Equatable {
  case invalidResponse
  case rateLimited
  case serverUnavailable
}

enum GitHubUpdateFeed {
  static let latestURL = URL(string: "https://api.github.com/repos/Natizh/easyflow/releases/latest")!
  static let repository = "Natizh/easyflow"
  static let archiveName = "EasyFlow.zip"
  static let manifestName = "EasyFlow.update.json"
  static let signatureName = "EasyFlow.update.sig"

  private struct Release: Decodable {
    let tag_name: String
    let html_url: URL
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
  }

  private struct Asset: Decodable {
    let name: String
    let browser_download_url: URL
    let state: String
  }

  static func interpret(_ data: Data, installed: SemanticVersion) throws -> UpdateDiscoveryResult {
    guard let release = try? JSONDecoder().decode(Release.self, from: data),
      validReleasePage(release.html_url, tag: release.tag_name)
    else { throw UpdateFeedError.invalidResponse }
    guard !release.draft, !release.prerelease else { return .upToDate }
    guard let version = SemanticVersion(release.tag_name) else { throw UpdateFeedError.invalidResponse }
    guard version > installed else { return .upToDate }
    func asset(_ name: String) -> URL? {
      let matching = release.assets.filter { $0.name == name && $0.state == "uploaded" }
      guard matching.count == 1,
        validAssetURL(matching[0].browser_download_url, tag: release.tag_name, name: name)
      else { return nil }
      return matching[0].browser_download_url
    }
    return .available(UpdateCandidate(
      version: version,
      notes: String((release.body ?? "").prefix(4_000)),
      releasePage: release.html_url,
      archiveURL: asset(archiveName),
      manifestURL: asset(manifestName),
      signatureURL: asset(signatureName)
    ))
  }

  private static func validReleasePage(_ url: URL, tag: String) -> Bool {
    url.scheme == "https" && url.host == "github.com"
      && url.path == "/Natizh/easyflow/releases/tag/\(tag)"
  }

  private static func validAssetURL(_ url: URL, tag: String, name: String) -> Bool {
    url.scheme == "https" && url.host == "github.com"
      && url.path == "/Natizh/easyflow/releases/download/\(tag)/\(name)"
  }
}

struct UpdateSchedule {
  static let interval: TimeInterval = 24 * 60 * 60
  static let launchDelay: TimeInterval = 10

  static func delay(lastCheck: Date?, now: Date) -> TimeInterval {
    guard let lastCheck, lastCheck <= now else { return launchDelay }
    return max(launchDelay, lastCheck.addingTimeInterval(interval).timeIntervalSince(now))
  }
}
