// Modified S256 helper from the official Swift MCP SDK 0.12.1.
// Copyright (c) 2024-2025 Model Context Protocol a Series of LF Projects, LLC.
// Upstream license transition terms are retained in LICENSES/swift-mcp-sdk.txt.
// See THIRD_PARTY_NOTICES.md. CryptoKit implements the cryptographic primitive.
import CryptoKit
import Foundation

enum PKCE {
  static func makeChallenge(from verifier: String) throws -> String {
    let hash = SHA256.hash(data: Data(verifier.utf8))
    return Data(hash).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
