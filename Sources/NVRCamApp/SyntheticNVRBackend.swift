// Copyright (c) 2026 Steel Brain
// SPDX-License-Identifier: MIT
// Fixture cameras for the offline demo. This type has no connection API.

import Foundation

public struct SyntheticCamera: Equatable, Sendable {
  public let id: String
  public let name: String

  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}

/// Screen copy and fixture list shown before a real NVR is configured.
public struct OfflineDemo: Equatable, Sendable {
  public static let banner = "Offline demo — not a real NVR"

  public let banner: String
  public let cameras: [SyntheticCamera]

  public init(banner: String = OfflineDemo.banner, cameras: [SyntheticCamera]) {
    self.banner = banner
    self.cameras = cameras
  }
}

public struct SyntheticNVRBackend: Equatable, Sendable {
  public static let cameras = [
    SyntheticCamera(id: "demo-lobby", name: "Offline demo lobby"),
    SyntheticCamera(id: "demo-dock", name: "Offline demo dock"),
  ]

  public private(set) var isRunning: Bool

  public init() {
    self.isRunning = false
  }

  public mutating func start(effects: NVRSideEffects = NVRSideEffects()) -> OfflineDemo {
    _ = effects.network
    _ = effects.keychainWrite
    isRunning = true
    return OfflineDemo(cameras: Self.cameras)
  }

  public mutating func stop() {
    isRunning = false
  }

  /// Fixed payload for a fixture camera. Unknown ids produce nothing.
  public func frame(for cameraID: String) -> Data? {
    guard Self.cameras.contains(where: { $0.id == cameraID }) else {
      return nil
    }
    return Data("offline-demo-frame".utf8)
  }
}
