import Foundation

/// RFC 7591 public clients. Registration identifies callback addresses, not a trusted app.
struct ClientRegistrationRequest: Decodable {
  let redirectURIs: [String]
  var clientName: String?
  var tokenEndpointAuthMethod: String?
  var grantTypes: [String]?
  var responseTypes: [String]?
  var scope: String?

  enum CodingKeys: String, CodingKey {
    case redirectURIs = "redirect_uris"
    case clientName = "client_name"
    case tokenEndpointAuthMethod = "token_endpoint_auth_method"
    case grantTypes = "grant_types"
    case responseTypes = "response_types"
    case scope
  }

  func validate(configuration: ServerConfiguration) throws {
    guard (1...8).contains(redirectURIs.count), Set(redirectURIs).count == redirectURIs.count,
      redirectURIs.allSatisfy({ configuration.localCallback($0) != nil })
    else { throw OAuthFailure("invalid_redirect_uri") }
    guard tokenEndpointAuthMethod == nil || tokenEndpointAuthMethod == "none",
      responseTypes == nil || responseTypes == ["code"],
      grantTypes.map({
        !$0.isEmpty && $0.contains("authorization_code")
          && Set($0).isSubset(of: ["authorization_code", "refresh_token"])
      }) ?? true,
      scope == nil || scope == ServerConfiguration.scope,
      clientName.map({
        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 100
          && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
      }) ?? true
    else { throw OAuthFailure("invalid_client_metadata") }
  }
}

struct RegisteredClient: Codable, Sendable {
  let id: String
  let name: String
  let redirectURIs: [String]
  let createdAt: Date
}

struct ClientRegistrationResponse: Encodable {
  let clientID: String
  let clientName: String
  let redirectURIs: [String]
  let clientIDIssuedAt: Int
  let tokenEndpointAuthMethod = "none"
  let grantTypes = ["authorization_code", "refresh_token"]
  let responseTypes = ["code"]
  let scope = ServerConfiguration.scope
  enum CodingKeys: String, CodingKey {
    case clientID = "client_id"
    case clientName = "client_name"
    case redirectURIs = "redirect_uris"
    case clientIDIssuedAt = "client_id_issued_at"
    case tokenEndpointAuthMethod = "token_endpoint_auth_method"
    case grantTypes = "grant_types"
    case responseTypes = "response_types"
    case scope
  }
}

extension ServerConfiguration {
  /// Local native clients only; no remote redirect, userinfo, query, or fragment.
  func localCallback(_ raw: String) -> URLComponents? {
    guard raw.utf8.count <= 2048, let url = URLComponents(string: raw),
      url.scheme == "http", let host = url.host,
      ["localhost", "127.0.0.1", "[::1]"].contains(host),
      let port = url.port, (1024...65535).contains(port), port != self.port,
      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
      raw == "http://\(host):\(port)\(url.percentEncodedPath)"
    else { return nil }
    return url
  }

  func matchesCallback(_ raw: String, registered: String) -> Bool {
    guard var requested = localCallback(raw), var expected = localCallback(registered) else {
      return false
    }
    // RFC 8252 permits the native client to choose a new loopback port for each login.
    requested.port = nil
    expected.port = nil
    return requested.string == expected.string
  }
}
