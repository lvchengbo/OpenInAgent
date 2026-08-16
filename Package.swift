// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "OpenInAgent",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(
      name: "OpenInAgent",
      targets: ["OpenInAgent"]
    )
  ],
  targets: [
    .executableTarget(
      name: "OpenInAgent",
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),
    .testTarget(
      name: "OpenInAgentTests",
      dependencies: ["OpenInAgent"],
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
