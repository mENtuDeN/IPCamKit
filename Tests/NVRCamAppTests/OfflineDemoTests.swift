// Copyright (c) 2026 Steel Brain
// SPDX-License-Identifier: MIT
// Behavioral tests for the offline demo. The source-token scan is static
// and is not a device or archive pass.

import Foundation
import Testing

@testable import NVRCamApp

private final class EffectCounter: @unchecked Sendable {
  var network = 0
  var keychain = 0
}

private func countingEffects(_ counter: EffectCounter) -> NVRSideEffects {
  NVRSideEffects(
    network: { counter.network += 1 },
    keychainWrite: { counter.keychain += 1 }
  )
}

private actor RecordingConnector: NVRLiveConnecting {
  private(set) var starts = 0
  private(set) var stops = 0

  func start(configuration: NVRConfiguration) async throws {
    starts += 1
    _ = configuration
  }

  func stop() async {
    stops += 1
  }
}

private struct ProbeError: Error {}

private actor ThrowingConnector: NVRLiveConnecting {
  private(set) var starts = 0
  private(set) var stops = 0

  func start(configuration: NVRConfiguration) async throws {
    starts += 1
    _ = configuration
    throw ProbeError()
  }

  func stop() async {
    stops += 1
  }
}

private func sampleConfiguration() -> NVRConfiguration {
  NVRConfiguration(host: "nvr.example.test", port: 554, username: "operator")
}

@Suite("Offline NVR demo")
struct OfflineDemoTests {

  @Test("A fresh install opens the labeled demo and can leave it")
  func freshInstallEntersAndExitsDemo() async {
    let counter = EffectCounter()
    var app = NVRCamApp(effects: countingEffects(counter))
    #expect(app.store.isFreshInstall)
    #expect(app.route.isOfflineDemo)
    #expect(app.route.demoBanner == OfflineDemo.banner)
    #expect(app.isDemoRunning)
    if case .offlineDemo(let demo) = app.route {
      #expect(demo.cameras.map(\.name) == ["Offline demo lobby", "Offline demo dock"])
    } else {
      Issue.record("Fresh install was not on the offline demo")
    }

    app.exitDemo()
    #expect(app.route == .settings)
    #expect(app.isDemoRunning == false)
    #expect(app.store.isFreshInstall)
    #expect(counter.network == 0)
    #expect(counter.keychain == 0)

    let again = EffectCounter()
    await app.enterDemo(effects: countingEffects(again))
    #expect(app.route.demoBanner == "Offline demo — not a real NVR")
    #expect(app.isDemoRunning)
    #expect(again.network == 0)
    #expect(again.keychain == 0)
    app.exitDemo()
    #expect(app.route == .settings)
  }

  @Test("Demo frames come from the fixture backend")
  func syntheticFramesStayLocal() {
    var backend = SyntheticNVRBackend()
    let counter = EffectCounter()
    let demo = backend.start(effects: countingEffects(counter))
    #expect(demo.banner == OfflineDemo.banner)
    #expect(backend.frame(for: "demo-lobby") == Data("offline-demo-frame".utf8))
    #expect(backend.frame(for: "nvr.example.test") == nil)
    backend.stop()
    #expect(backend.isRunning == false)
    #expect(counter.network == 0)
    #expect(counter.keychain == 0)
  }

  @Test("Saved configuration survives entering and leaving the demo")
  func savedConfigurationSurvivesDemo() async throws {
    let saved = sampleConfiguration()
    let counter = EffectCounter()
    var store = NVRStore()
    store.save(saved, effects: countingEffects(counter))
    #expect(counter.network == 0)
    #expect(counter.keychain == 0)

    var app = NVRCamApp(store: store)
    #expect(app.route == .settings)
    #expect(app.store.savedConfiguration == saved)

    let demoEffects = EffectCounter()
    await app.enterDemo(effects: countingEffects(demoEffects))
    #expect(app.route.isOfflineDemo)
    #expect(app.store.savedConfiguration == saved)
    #expect(demoEffects.network == 0)
    #expect(demoEffects.keychain == 0)

    app.exitDemo()
    #expect(app.route == .settings)
    #expect(app.store.savedConfiguration == saved)

    let connector = RecordingConnector()
    try await app.beginLive(using: connector)
    #expect(await connector.starts == 1)
    #expect(app.route == .live(saved))
    await app.teardown()
    #expect(await connector.stops == 1)
    #expect(app.route == .settings)
    #expect(app.store.savedConfiguration == saved)
    await app.teardown()
    #expect(await connector.stops == 1)
  }

  @Test("The demo cannot start the live connector")
  func demoDoesNotStartLiveConnection() async {
    var app = NVRCamApp()
    let connector = RecordingConnector()
    var thrown: NVRAppError?
    do {
      try await app.beginLive(using: connector)
    } catch let error as NVRAppError {
      thrown = error
    } catch {
      Issue.record("Unexpected error \(error)")
    }
    #expect(thrown == .demoIsOffline)
    #expect(await connector.starts == 0)
    #expect(await connector.stops == 0)
    #expect(app.route.isOfflineDemo)
  }

  @Test("Live start failure and a second start do not skip teardown")
  func liveLifecycleStaysPaired() async throws {
    var store = NVRStore()
    store.save(sampleConfiguration())
    var app = NVRCamApp(store: store)

    let failing = ThrowingConnector()
    var didThrow = false
    do {
      try await app.beginLive(using: failing)
    } catch is ProbeError {
      didThrow = true
    } catch {
      Issue.record("Unexpected error \(error)")
    }
    #expect(didThrow)
    #expect(await failing.starts == 1)
    #expect(app.route == .settings)
    await app.teardown()
    #expect(await failing.stops == 0)

    let connector = RecordingConnector()
    try await app.beginLive(using: connector)
    var second: NVRAppError?
    do {
      try await app.beginLive(using: connector)
    } catch let error as NVRAppError {
      second = error
    } catch {
      Issue.record("Unexpected error \(error)")
    }
    #expect(second == .alreadyLive)
    #expect(await connector.starts == 1)

    await app.enterDemo()
    #expect(app.route.isOfflineDemo)
    #expect(app.store.savedConfiguration == sampleConfiguration())
    #expect(await connector.stops == 1)
    await app.teardown()
    #expect(await connector.stops == 1)
    #expect(app.route == .settings)
  }

  @Test("Settings with no saved host cannot go live")
  func emptySettingsRefuseLive() async {
    var app = NVRCamApp()
    app.exitDemo()
    let connector = RecordingConnector()
    var thrown: NVRAppError?
    do {
      try await app.beginLive(using: connector)
    } catch let error as NVRAppError {
      thrown = error
    } catch {
      Issue.record("Unexpected error \(error)")
    }
    #expect(thrown == .noSavedConfiguration)
    #expect(await connector.starts == 0)
  }

  @Test("Static guard: demo sources do not reference network, keychain, or defaults APIs")
  func demoSourcesOmitNetworkAndKeychain() throws {
    let root = repositoryRoot()
    let manifest = try String(
      contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
    #expect(manifest.contains("name: \"IPCamKit\""))
    let directory = root.appendingPathComponent("Sources/NVRCamApp")
    let files = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil
    )
    let forbidden = [
      "URLSession", "NWConnection", "SecItem", "kSecClass", "UserDefaults", "AppStorage",
      "CFPreferences",
    ]
    for file in files where file.pathExtension == "swift" {
      let text = try String(contentsOf: file, encoding: .utf8)
      for token in forbidden {
        #expect(text.contains(token) == false, "\(file.lastPathComponent) contains \(token)")
      }
    }
  }

  @Test("Static guard: RTSP start and stop signatures are still the live client")
  func realClientLifecycleSignaturesRemain() throws {
    let url = repositoryRoot()
      .appendingPathComponent("Sources/IPCamKit/Client/RTSPSession.swift")
    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(text.contains("public func start() async throws -> SessionDescription"))
    #expect(text.contains("public func stop() async"))
  }
}

private func repositoryRoot(file: String = #filePath) -> URL {
  var url = URL(fileURLWithPath: file).resolvingSymlinksInPath().deletingLastPathComponent()
  let manager = FileManager.default
  while url.path != "/" {
    if manager.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
      return url
    }
    url.deleteLastPathComponent()
  }
  return URL(fileURLWithPath: file).resolvingSymlinksInPath().deletingLastPathComponent()
}
