import Foundation
import Testing

@testable import IMCPHTTP

struct ClientSetupTests {
  @Test func searchAndRecipesUseCurrentEndpoint() throws {
    let endpoint = "http://127.0.0.1:19876/mcp"
    let clients = ClientSetup.clients(resource: endpoint)
    #expect(ClientSetup.matching("  visual   studio  ", in: clients).map(\.id) == ["vscode"])
    #expect(
      ClientSetup.matching("ANTHROPIC", in: clients).map(\.id) == ["claude-code", "claude-desktop"])
    #expect(ClientSetup.matching("nothing-matches", in: clients).isEmpty)
    for client in clients {
      if let configuration = client.configuration {
        #expect(configuration.contains(endpoint))
        if configuration.hasPrefix("{") {
          _ = try JSONSerialization.jsonObject(with: Data(configuration.utf8))
        }
      }
      if client.support == .unavailable { #expect(client.configuration == nil) }
    }
  }
}
