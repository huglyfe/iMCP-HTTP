import Foundation

/// Display-only setup recipes. OAuth compatibility lives in the core, not this catalog.
struct ClientSetup: Identifiable {
  enum Support: String {
    case verified = "Verified"
    case loginVerified = "Login verified"
    case unverified = "Not yet verified"
    case unavailable = "Unavailable locally"
  }
  let id: String
  let name: String
  let keywords: String
  let support: Support
  let instructions: String
  let documentation: URL
  var configuration: String? = nil

  static func clients(resource: String) -> [ClientSetup] {
    let entries: [ClientSetup] = [
      .init(
        id: "chatgpt", name: "ChatGPT", keywords: "OpenAI web mobile", support: .unavailable,
        instructions:
          "ChatGPT's hosted connections cannot reach this Mac's local address directly. A tunnel or hosted endpoint would require a separate deployment decision. Use a local client such as Codex with this version of iMCP-HTTP.",
        documentation: URL(string: "https://developers.openai.com/plugins/deploy/connect-chatgpt")!),
      .init(
        id: "claude-code", name: "Claude Code", keywords: "Anthropic terminal CLI",
        support: .unverified,
        instructions:
          "Run the command below on this Mac. Open Claude Code, run /mcp, and authenticate iMCP-HTTP. Approve the connection from the iMCP-HTTP menu-bar icon.",
        documentation: URL(string: "https://code.claude.com/docs/en/mcp")!,
        configuration: "claude mcp add --transport http imcp-http \(resource)"),
      .init(
        id: "claude-desktop", name: "Claude Desktop", keywords: "Anthropic Cowork",
        support: .unavailable,
        instructions:
          "Claude's remote connectors connect from Anthropic's cloud, even in the desktop app. They cannot reach this local endpoint. The desktop stdio integration is a different transport. Use Claude Code for a direct local HTTP connection.",
        documentation: URL(
          string:
            "https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp"
        )!),
      .init(
        id: "codex", name: "Codex", keywords: "OpenAI terminal CLI desktop", support: .verified,
        instructions:
          "Run these commands on this Mac, then approve the connection from the iMCP-HTTP menu-bar icon.",
        documentation: URL(string: "https://learn.chatgpt.com/docs/extend/mcp?surface=cli")!,
        configuration:
          "codex mcp add imcp-http --url \(resource)\ncodex mcp login imcp-http"
      ),
      .init(
        id: "cursor", name: "Cursor", keywords: "editor desktop", support: .unverified,
        instructions:
          "In the desktop editor, open MCP settings and merge this entry into mcp.json. Enable the server and follow its sign-in prompt, then approve in iMCP-HTTP. Use a local workspace; cloud agents cannot reach this address.",
        documentation: URL(string: "https://cursor.com/docs/mcp")!,
        configuration: json(root: "mcpServers", fields: ["url": resource])),
      .init(
        id: "gemini", name: "Gemini CLI", keywords: "Google terminal", support: .unverified,
        instructions:
          "Merge this entry into your Gemini CLI settings.json. Start Gemini on this Mac and run /mcp auth imcp-http, then approve in iMCP-HTTP.",
        documentation: URL(string: "https://geminicli.com/docs/tools/mcp-server/")!,
        configuration: json(root: "mcpServers", fields: ["httpUrl": resource])),
      .init(
        id: "opencode", name: "OpenCode", keywords: "terminal CLI", support: .loginVerified,
        instructions:
          "Merge this entry into opencode.json, then run opencode mcp auth imcp-http on this Mac. Approve the connection from the iMCP-HTTP menu-bar icon. OAuth login is tested; tool use, restart, and revocation through this client still need acceptance.",
        documentation: URL(string: "https://opencode.ai/docs/mcp-servers/")!,
        configuration: json(root: "mcp", fields: ["type": "remote", "url": resource])),
      .init(
        id: "vscode", name: "VS Code", keywords: "Visual Studio Code GitHub Copilot Microsoft",
        support: .unverified,
        instructions:
          "In a local desktop workspace, run MCP: Add Server from the Command Palette, choose HTTP, and enter the server address above. Name it imcp-http and follow sign-in. This build accepts local OAuth callbacks only; a flow requesting vscode.dev callbacks is not supported.",
        documentation: URL(
          string: "https://code.visualstudio.com/docs/agent-customization/mcp-servers")!),
      .init(
        id: "windsurf", name: "Windsurf", keywords: "Devin Desktop Cascade editor",
        support: .unverified,
        instructions:
          "Open Cascade's MCP configuration and merge this entry into mcp_config.json. Enable the server and follow its sign-in prompt on this Mac, then approve in iMCP-HTTP. Current vendor documentation calls this Devin Desktop.",
        documentation: URL(string: "https://docs.devin.ai/desktop/cascade/mcp")!,
        configuration: json(root: "mcpServers", fields: ["serverUrl": resource])),
      .init(
        id: "zed", name: "Zed", keywords: "editor agent", support: .unverified,
        instructions:
          "Merge this entry into Zed's settings.json. Open the Agent Panel and follow the server's authentication prompt, then approve in iMCP-HTTP. Run Zed and the server on the same Mac.",
        documentation: URL(string: "https://zed.dev/docs/ai/mcp")!,
        configuration: json(root: "context_servers", fields: ["url": resource])),
    ]
    return entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  static func matching(_ query: String, in clients: [ClientSetup]) -> [ClientSetup] {
    let words = query.split(whereSeparator: \.isWhitespace)
    return clients.filter { client in
      words.allSatisfy {
        (client.name + " " + client.keywords).localizedStandardContains(String($0))
      }
    }
  }

  private static func json(root: String, fields: [String: String]) -> String {
    // Only fixed keys and the app's numeric loopback endpoint enter these recipes.
    let data = try! JSONSerialization.data(
      withJSONObject: [root: ["imcp-http": fields]],
      options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    return String(decoding: data, as: UTF8.self)
  }
}
