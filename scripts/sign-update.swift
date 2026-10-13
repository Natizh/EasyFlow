import CryptoKit
import Foundation

guard CommandLine.arguments.count == 4 || CommandLine.arguments.count == 6 else {
  fputs("Usage: swift sign-update.swift [PRIVATE_KEY PUBLIC_KEY] EasyFlow.zip VERSION OUTPUT_DIR\n", stderr)
  exit(1)
}
let defaultKeyDirectory = FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent("Library/Application Support/EasyFlowSigning")
let explicitKeys = CommandLine.arguments.count == 6
let privateURL = (explicitKeys
  ? URL(fileURLWithPath: CommandLine.arguments[1])
  : defaultKeyDirectory.appendingPathComponent("update-private-key.txt")).standardizedFileURL
let publicURL = (explicitKeys
  ? URL(fileURLWithPath: CommandLine.arguments[2])
  : defaultKeyDirectory.appendingPathComponent("update-public-key.txt")).standardizedFileURL
let offset = explicitKeys ? 2 : 0
let archiveURL = URL(fileURLWithPath: CommandLine.arguments[1 + offset]).standardizedFileURL
let version = CommandLine.arguments[2 + offset]
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3 + offset]).standardizedFileURL
let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
guard archiveURL.lastPathComponent == "EasyFlow.zip",
  !privateURL.path.hasPrefix(repositoryRoot.path + "/"),
  (try privateURL.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true,
  version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil,
  (try FileManager.default.attributesOfItem(atPath: privateURL.path)[.posixPermissions] as? Int ?? 0) & 0o077 == 0,
  let privateBytes = Data(base64Encoded: try String(contentsOf: privateURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)),
  privateBytes.count == 32,
  let publicBytes = Data(base64Encoded: try String(contentsOf: publicURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)),
  publicBytes.count == 32
else { fatalError("Invalid key, version, archive name, or private-key file permissions") }
let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateBytes)
guard privateKey.publicKey.rawRepresentation == publicBytes else {
  fatalError("The public key does not match the private signing key")
}

let handle = try FileHandle(forReadingFrom: archiveURL)
defer { try? handle.close() }
var hasher = SHA256()
while true {
  let bytes = try handle.read(upToCount: 1024 * 1024) ?? Data()
  if bytes.isEmpty { break }
  hasher.update(data: bytes)
}
let checksum = hasher.finalize().map { String(format: "%02x", $0) }.joined()
let size = try FileManager.default.attributesOfItem(atPath: archiveURL.path)[.size] as? Int64 ?? 0
guard size > 0, size <= 250 * 1024 * 1024 else {
  fatalError("Archive size is outside the updater's supported range")
}
let manifest: [String: Any] = [
  "repository": "Natizh/easyflow",
  "version": version,
  "bundleIdentifier": "io.github.natizh.easyflow",
  "archiveName": "EasyFlow.zip",
  "archiveSHA256": checksum,
  "archiveBytes": size,
]
let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
let signature = try privateKey.signature(for: data)
try data.write(to: outputURL.appendingPathComponent("EasyFlow.update.json"), options: .atomic)
try Data(signature.base64EncodedString().utf8).write(
  to: outputURL.appendingPathComponent("EasyFlow.update.sig"), options: .atomic
)
print("Signed EasyFlow.zip (SHA-256: \(checksum))")
