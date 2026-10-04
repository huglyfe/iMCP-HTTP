import CryptoKit
import Foundation
import Security

public struct ServerConfiguration: Sendable {
  public let port: Int
  public init(port: Int = 18765) {
    precondition((1024...65535).contains(port))
    self.port = port
  }
  public var issuer: String { "http://127.0.0.1:\(port)" }
  public var resource: String { "\(issuer)/mcp" }
  public static let scope = "apple-services"
  public static let clientID = "codex"

  /// The public client is not an application identity. Native consent authorizes each grant.
  func validCallback(_ raw: String) -> Bool {
    guard let url = URLComponents(string: raw), url.scheme == "http",
      url.host == "127.0.0.1", let port = url.port, (1024...65535).contains(port),
      port != self.port, url.path == "/callback", url.user == nil, url.password == nil,
      url.query == nil, url.fragment == nil
    else { return false }
    return raw == "http://127.0.0.1:\(port)/callback"
  }
}

public struct AuthorizationViewState: Sendable {
  public let approvals: [PendingApproval]
  public let clients: [ClientGrant]
}

public struct PendingApproval: Identifiable, Sendable {
  public let id: String
  public let clientID: String
  public let callback: String
  public let expiresAt: Date
}

public struct ClientGrant: Codable, Identifiable, Sendable {
  public let id: UUID
  public let clientID: String
  public let createdAt: Date
  public var revoked: Bool
  var accessHash: String
  var accessExpiresAt: Date
  var refreshHash: String
  var usedRefreshHashes: [String]
}

struct AuthorizationRequest: Sendable {
  let clientID: String
  let callback: String
  let state: String
  let challenge: String
  let resource: String
}

struct PendingRequest: Sendable {
  let request: AuthorizationRequest
  let expiresAt: Date
  var callbackURL: URL?
}

struct AuthorizationCode: Sendable {
  let request: AuthorizationRequest
  let expiresAt: Date
}

struct TokenResponse: Codable, Sendable {
  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case tokenType = "token_type"
    case expiresIn = "expires_in"
    case refreshToken = "refresh_token"
    case scope
  }
  let accessToken: String
  var tokenType: String = "Bearer"
  var expiresIn: Int = 900
  let refreshToken: String
  var scope: String = ServerConfiguration.scope
}

struct OAuthFailure: Error, Sendable {
  let code: String
  init(_ code: String) { self.code = code }
}

enum Credential {
  static func make() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw OAuthFailure("server_error")
    }
    return Data(bytes).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
  static func hash(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
  static func validVerifier(_ value: String) -> Bool {
    (43...128).contains(value.utf8.count)
      && value.utf8.allSatisfy {
        (65...90).contains($0) || (97...122).contains($0)
          || (48...57).contains($0) || [45, 46, 95, 126].contains($0)
      }
  }
}
