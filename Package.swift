// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "iMCP-HTTP",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "IMCPHTTP", targets: ["IMCPHTTP"])
  ],
  targets: [
    .target(name: "IMCPCore"),
    .executableTarget(name: "IMCPHTTP", dependencies: ["IMCPCore"]),
  ]
)
