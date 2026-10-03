// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "iMCP-HTTP",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "IMCPHTTP", targets: ["IMCPHTTP"])
  ],
  dependencies: [
    .package(url: "https://github.com/Cocoanetics/SwiftMCP.git", exact: "1.13.0", traits: []),
    .package(url: "https://github.com/hummingbird-project/hummingbird.git", exact: "2.27.0"),
    .package(url: "https://github.com/apple/swift-http-types.git", exact: "1.8.0"),
    .package(url: "https://github.com/apple/swift-log.git", exact: "1.15.1"),
  ],
  targets: [
    .target(
      name: "IMCPCore",
      dependencies: [
        .product(name: "SwiftMCP", package: "SwiftMCP"),
        .product(name: "Hummingbird", package: "hummingbird"),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "Logging", package: "swift-log"),
      ]),
    .executableTarget(name: "IMCPHTTP", dependencies: ["IMCPCore"]),
    .testTarget(
      name: "IMCPCoreTests",
      dependencies: ["IMCPCore", .product(name: "SwiftMCP", package: "SwiftMCP")]),
  ]
)
