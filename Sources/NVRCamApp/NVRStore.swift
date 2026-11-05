// Copyright (c) 2026 Steel Brain
// SPDX-License-Identifier: MIT
// Saved NVR configuration. Demo entry and exit do not change this value.
// Secrets are not stored here.

import Foundation

/// Hooks a caller can observe. Configuration saves and the offline demo
/// do not invoke them.
public struct NVRSideEffects: Sendable {
  public var network: @Sendable () -> Void
  public var keychainWrite: @Sendable () -> Void

  public init(
    network: @escaping @Sendable () -> Void = {},
    keychainWrite: @escaping @Sendable () -> Void = {}
  ) {
    self.network = network
    self.keychainWrite = keychainWrite
  }
}

/// Non-secret fields needed to open a real NVR later.
public struct NVRConfiguration: Equatable, Sendable {
  public var host: String
  public var port: Int
  public var username: String

  public init(host: String, port: Int, username: String) {
    self.host = host
    self.port = port
    self.username = username
  }
}

/// In-memory configuration for one install. A fresh store has no host.
public struct NVRStore: Equatable, Sendable {
  public private(set) var savedConfiguration: NVRConfiguration?

  public init(savedConfiguration: NVRConfiguration? = nil) {
    self.savedConfiguration = savedConfiguration
  }

  public var isFreshInstall: Bool {
    savedConfiguration == nil
  }

  public mutating func save(
    _ configuration: NVRConfiguration,
    effects: NVRSideEffects = NVRSideEffects()
  ) {
    // Retain the hooks so a caller can pass them, and do not invoke them.
    _ = effects.network
    _ = effects.keychainWrite
    savedConfiguration = configuration
  }
}
