// Copyright (c) 2026 Steel Brain
// SPDX-License-Identifier: MIT
// Launch flow for the offline demo and a later real NVR session.
//
// The real RTSP client stays `RTSPClientSession` in IPCamKit. This type
// only starts and stops an injected `NVRLiveConnecting` value, and only
// after the user has left the demo and saved a configuration.

import Foundation

public enum NVRAppError: Error, Equatable, Sendable {
  case demoIsOffline
  case noSavedConfiguration
  case alreadyLive
}

/// Real NVR lifecycle. The demo never calls this.
public protocol NVRLiveConnecting: Sendable {
  func start(configuration: NVRConfiguration) async throws
  func stop() async
}

public struct NVRCamApp: Sendable {
  public private(set) var route: NVRRoute
  public private(set) var store: NVRStore
  private var backend: SyntheticNVRBackend?
  private var connector: (any NVRLiveConnecting)?

  public var isDemoRunning: Bool {
    backend?.isRunning == true
  }

  public init(store: NVRStore = NVRStore(), effects: NVRSideEffects = NVRSideEffects()) {
    self.store = store
    self.connector = nil
    if store.isFreshInstall {
      var backend = SyntheticNVRBackend()
      let demo = backend.start(effects: effects)
      self.backend = backend
      self.route = NVRRouter.initial(store: store, demo: demo)
    } else {
      self.backend = nil
      self.route = NVRRouter.initial(store: store, demo: nil)
    }
  }

  /// Leave the demo for NVR settings. Saved configuration is kept.
  public mutating func exitDemo() {
    guard route.isOfflineDemo else {
      return
    }
    backend?.stop()
    backend = nil
    route = NVRRouter.exitDemo()
  }

  /// Open the labeled demo. Stops a live session first. Does not clear the store.
  public mutating func enterDemo(effects: NVRSideEffects = NVRSideEffects()) async {
    if let connector {
      await connector.stop()
      self.connector = nil
    }
    var backend = SyntheticNVRBackend()
    let demo = backend.start(effects: effects)
    self.backend = backend
    self.route = NVRRouter.enterDemo(demo)
  }

  /// Start the real connector. Refuses to run while the offline demo is on screen.
  public mutating func beginLive(using connector: any NVRLiveConnecting) async throws {
    if route.isOfflineDemo {
      throw NVRAppError.demoIsOffline
    }
    guard let configuration = store.savedConfiguration else {
      throw NVRAppError.noSavedConfiguration
    }
    if self.connector != nil {
      throw NVRAppError.alreadyLive
    }
    try await connector.start(configuration: configuration)
    self.connector = connector
    self.route = NVRRouter.showLive(configuration)
  }

  /// Stop the demo backend and, if a live session was started, stop it once.
  public mutating func teardown() async {
    backend?.stop()
    backend = nil
    if let connector {
      await connector.stop()
      self.connector = nil
    }
    route = .settings
  }
}
