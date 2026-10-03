# Third-party notices

The app is original SwiftUI/EventKit application code. iMCP informed the initial product inventory; no iMCP implementation, networking, identity, or branding assets are included.

## Runtime dependencies

- [SwiftMCP 1.13.0](https://github.com/Cocoanetics/SwiftMCP/tree/v1.13.0), revision `3f7e8db79cf8647eb11b7b420909e0f74f16ab68`, copyright Oliver Drobnik, BSD-2-Clause. Core protocol/tool/schema functionality only; optional Server, Client, and OpenAPI traits disabled.
- [Hummingbird 2.27.0](https://github.com/hummingbird-project/hummingbird/tree/2.27.0), Apache-2.0. HTTP server, body/connection limits, lifecycle, form decoding.
- Apple [swift-http-types 1.8.0](https://github.com/apple/swift-http-types/tree/1.8.0) and [swift-log 1.15.1](https://github.com/apple/swift-log/tree/1.15.1), Apache-2.0. Used directly for HTTP fields and a no-op logger.

`Package.resolved` records exact revisions of direct and transitive dependencies. Their original license/notice files remain in SwiftPM checkouts; `build-app.sh` includes their top-level license/notice files in the bundle's `Contents/Resources/Licenses`. Review notices again before distributing a release.

## Adapted source

`Sources/IMCPCore/Authorization/PKCE.swift` adapts only the CryptoKit S256 challenge function from `Sources/MCP/Base/Authorization/PKCE.swift` in the [official Swift MCP SDK 0.12.1](https://github.com/modelcontextprotocol/swift-sdk/tree/0.12.1), revision `a0ae212ebf6eab5f754c3129608bc5557637e605`.

Copyright (c) 2024–2025 Model Context Protocol a Series of LF Projects, LLC. Changes: internal visibility, macOS-only CryptoKit support, inline base64url conversion; no verifier generator or authorization client code is included. The SDK is not a runtime dependency.

Upstream is transitioning from MIT to Apache-2.0. The full upstream license text, including that transition statement and original copyright, is retained in [LICENSES/swift-mcp-sdk.txt](LICENSES/swift-mcp-sdk.txt) and copied into the bundle.
