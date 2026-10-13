import CryptoKit
import Foundation

guard CommandLine.arguments.count == 2 else {
  fputs("Usage: swift create-update-keypair.swift /secure/directory-outside-repository\n", stderr)
  exit(1)
}
let destination = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
guard destination != repositoryRoot,
  !destination.path.hasPrefix(repositoryRoot.path + "/") else {
  fatalError("Signing keys must be outside the repository")
}
let privateURL = destination.appendingPathComponent("update-private-key.txt")
let publicURL = destination.appendingPathComponent("update-public-key.txt")
guard !FileManager.default.fileExists(atPath: privateURL.path),
  !FileManager.default.fileExists(atPath: publicURL.path)
else { fatalError("Key files already exist; refusing to overwrite them") }
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true,
  attributes: [.posixPermissions: 0o700])
let key = Curve25519.Signing.PrivateKey()
try Data(key.rawRepresentation.base64EncodedString().utf8).write(to: privateURL, options: .atomic)
try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateURL.path)
try Data(key.publicKey.rawRepresentation.base64EncodedString().utf8).write(to: publicURL, options: .atomic)
try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: publicURL.path)
print("Signing key files created outside the repository. Back up the private key securely.")
