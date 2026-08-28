import CryptoKit
import Foundation

// MARK: - Entry

// Top-level `let` in main.swift initialises eagerly in declaration order, so this
// must appear before the command switch below that uses it.
let defaultKeyDirectory = NSHomeDirectory() + "/.light-stats-license"

let arguments = Array(CommandLine.arguments.dropFirst())

guard let command = arguments.first else {
    printUsage()
    exit(1)
}

switch command {
case "generate-keypair":
    generateKeypair(arguments: Array(arguments.dropFirst()))
case "issue":
    issue(arguments: Array(arguments.dropFirst()))
case "verify":
    verify(arguments: Array(arguments.dropFirst()))
default:
    fail("Unknown command '\(command)'")
}

// MARK: - Commands

func generateKeypair(arguments: [String]) {
    let directory = value(for: "--dir", in: arguments) ?? defaultKeyDirectory
    do {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    } catch {
        fail("Cannot create directory \(directory): \(error)")
    }
    let privatePath = directory + "/private.key"
    let publicPath = directory + "/public.key"
    guard !FileManager.default.fileExists(atPath: privatePath),
          !FileManager.default.fileExists(atPath: publicPath) else {
        fail("Key files already exist in \(directory); move them explicitly before generating a replacement")
    }
    let key = Curve25519.Signing.PrivateKey()
    do {
        try key.rawRepresentation.base64EncodedString()
            .write(toFile: privatePath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privatePath)
        try key.publicKey.rawRepresentation.base64EncodedString()
            .write(toFile: publicPath, atomically: true, encoding: .utf8)
    } catch {
        fail("Cannot write key files: \(error)")
    }
    print("Private key: \(privatePath)")
    print("Public key:  \(publicPath)")
    print("")
    print("Embed the public key (base64) into Light Stats/Services/LicenseValidator.swift:")
    print(key.publicKey.rawRepresentation.base64EncodedString())
    print("")
    print("Back up \(privatePath). Losing it prevents issuing new codes with the embedded public key.")
}

func issue(arguments: [String]) {
    guard let privatePath = value(for: "--private-key", in: arguments) else {
        fail("Missing --private-key <path>")
    }
    let owner = value(for: "--owner", in: arguments) ?? ""
    let feature = value(for: "--feature", in: arguments) ?? "findMouse"
    guard let privateKey = loadPrivateKey(at: privatePath) else {
        fail("Cannot read private key at \(privatePath)")
    }
    guard let payload = Payload.build(features: [feature], owner: owner, issuedAt: Int64(Date().timeIntervalSince1970)),
          let signature = try? privateKey.signature(for: payload) else {
        fail("Cannot sign payload")
    }
    print(LicenseCodec.encode(payload: payload, signature: signature))
}

func verify(arguments: [String]) {
    guard let publicPath = value(for: "--public-key", in: arguments),
          let code = value(for: "--code", in: arguments) else {
        fail("Missing --public-key <path> or --code <code>")
    }
    guard let publicKey = loadPublicKey(at: publicPath) else {
        fail("Cannot read public key at \(publicPath)")
    }
    guard let (payload, signature) = LicenseCodec.decode(code) else {
        fail("Malformed code")
    }
    guard publicKey.isValidSignature(signature, for: payload) else {
        fail("Signature does not match the supplied public key")
    }
    guard let json = Payload.decode(payload) else {
        fail("Payload does not parse")
    }
    let issued = Date(timeIntervalSince1970: TimeInterval(json.i))
    print("Valid activation code")
    print("  owner:     \(json.o)")
    print("  features:  \(json.f.joined(separator: ", "))")
    print("  issued at: \(issued)")
}

// MARK: - Helpers

func value(for flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func loadPrivateKey(at path: String) -> Curve25519.Signing.PrivateKey? {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8),
          let data = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
    return try? Curve25519.Signing.PrivateKey(rawRepresentation: data)
}

func loadPublicKey(at path: String) -> Curve25519.Signing.PublicKey? {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8),
          let data = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
    return try? Curve25519.Signing.PublicKey(rawRepresentation: data)
}

func printUsage() {
    print("""
    license-tool — offline activation code generator for Light Stats

    Commands:
      generate-keypair [--dir <path>]
          Create an Ed25519 keypair (default: ~/.light-stats-license).
      issue --private-key <path> [--owner <name>] [--feature <key>]
          Issue an activation code (default feature: findMouse).
      verify --public-key <path> --code <code>
          Validate an activation code and print its payload.
    """)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
