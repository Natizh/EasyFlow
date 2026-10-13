import CryptoKit
import Foundation

guard CommandLine.arguments.count == 5 || CommandLine.arguments.count == 6 else {
  fputs("Usage: swift verify-update-artifact.swift [PUBLIC_KEY] ZIP MANIFEST SIGNATURE VERSION\n", stderr)
  exit(1)
}
let explicitKey = CommandLine.arguments.count == 6
let publicURL = explicitKey
  ? URL(fileURLWithPath: CommandLine.arguments[1])
  : FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/EasyFlowSigning/update-public-key.txt")
let offset = explicitKey ? 1 : 0
let archiveURL = URL(fileURLWithPath: CommandLine.arguments[1 + offset])
let manifestURL = URL(fileURLWithPath: CommandLine.arguments[2 + offset])
let signatureURL = URL(fileURLWithPath: CommandLine.arguments[3 + offset])
let version = CommandLine.arguments[4 + offset]
guard let keyBytes = Data(base64Encoded: try String(contentsOf: publicURL, encoding: .utf8)
  .trimmingCharacters(in: .whitespacesAndNewlines)),
  keyBytes.count == 32,
  let signature = Data(base64Encoded: try String(contentsOf: signatureURL, encoding: .utf8)
    .trimmingCharacters(in: .whitespacesAndNewlines)),
  signature.count == 64
else { fatalError("Invalid public key or signature") }
let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyBytes)
let manifestData = try Data(contentsOf: manifestURL)
guard key.isValidSignature(signature, for: manifestData),
  let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
  manifest["repository"] as? String == "Natizh/easyflow",
  manifest["version"] as? String == version,
  manifest["bundleIdentifier"] as? String == "io.github.natizh.easyflow",
  manifest["archiveName"] as? String == "EasyFlow.zip",
  archiveURL.lastPathComponent == "EasyFlow.zip"
else { fatalError("Signed metadata does not match this EasyFlow release") }
let handle = try FileHandle(forReadingFrom: archiveURL)
defer { try? handle.close() }
var hasher = SHA256()
while true {
  let bytes = try handle.read(upToCount: 1024 * 1024) ?? Data()
  if bytes.isEmpty { break }
  hasher.update(data: bytes)
}
let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
let archiveBytes = try FileManager.default.attributesOfItem(atPath: archiveURL.path)[.size] as? Int64 ?? 0
guard manifest["archiveSHA256"] as? String == digest,
  manifest["archiveBytes"] as? Int64 == archiveBytes
else { fatalError("Archive checksum or size does not match signed metadata") }
print("Signed update artifact verified: EasyFlow \(version)")
