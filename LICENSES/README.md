# Retained third-party licenses

Original iMCP-HTTP code uses the root Apache-2.0 [LICENSE](../LICENSE). These files preserve separate upstream terms; they are not relicensed by the application.

- `swift-mcp-sdk.txt`: unmodified license from official Swift MCP SDK 0.12.1, revision `a0ae212ebf6eab5f754c3129608bc5557637e605`, for the adapted PKCE challenge helper. Includes the upstream MIT-to-Apache transition statement.
- `boringssl-nio-ssl.txt`: BoringSSL license at `817ab07ebb53da35afea409ab9328f578492832d`, matching SwiftNIO SSL 2.37.5's vendored source.
- `boringssl-crypto.txt`: BoringSSL license at `0226f30467f540a3f62ef48d453f93927da199b6`, matching Swift Crypto 5.0.0's vendored source.
- `ushet.txt`: MIT license from uSHET at `c09e0acafd86720efe42dc15c63e0cc228244c32`, for SwiftNIO's `cpp_magic.h` component.
- `swift-nio-sha1.txt`: BSD-3-Clause copyright/license block retained from SwiftNIO's `Sources/CNIOSHA1/c_nio_sha1.c` at `21de5f08c1a166a6dd293d0e587ad977bf8dac5d`.

Trailing whitespace in the retained BoringSSL notice is normalized; the license text is otherwise unchanged.

BoringSSL license sources: [SwiftNIO SSL revision](https://github.com/google/boringssl/blob/817ab07ebb53da35afea409ab9328f578492832d/LICENSE) and [Swift Crypto revision](https://github.com/google/boringssl/blob/0226f30467f540a3f62ef48d453f93927da199b6/LICENSE). uSHET license: [pinned source](https://github.com/18sg/uSHET/blob/c09e0acafd86720efe42dc15c63e0cc228244c32/LICENSE).

Bundling also copies root license/notice files for every dependency in `Package.resolved` and component license files under each dependency's `Sources/`, including llhttp. Notices may cover code not linked on a particular platform. Review these files when upgrading the dependency graph.
