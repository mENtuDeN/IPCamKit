// swift-tools-version: 6.0

import PackageDescription

// Pins the ONVIF replay fork to one commit. The requirement is a revision.
let package = Package(
  name: "OnvifReplayPin",
  platforms: [
    .macOS(.v13),
    .iOS(.v16),
    .tvOS(.v16),
    .macCatalyst(.v16),
    .visionOS(.v1),
  ],
  dependencies: [
    .package(
      url: "https://github.com/mENtuDeN/IPCamKit.git",
      revision: "4f5b0ff20e0158c93ec3fbf6745377bb1352a962"
    )
  ],
  targets: [
    .testTarget(
      name: "OnvifReplayPinTests",
      path: "Tests/OnvifReplayPinTests"
    )
  ]
)
