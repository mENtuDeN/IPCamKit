// Copyright (c) 2026 Steel Brain
// SPDX-License-Identifier: MIT
// Routes among the offline demo, NVR settings, and a live session.

import Foundation

public enum NVRRoute: Equatable, Sendable {
  case offlineDemo(OfflineDemo)
  case settings
  case live(NVRConfiguration)

  public var isOfflineDemo: Bool {
    if case .offlineDemo = self {
      return true
    }
    return false
  }

  public var demoBanner: String? {
    if case .offlineDemo(let demo) = self {
      return demo.banner
    }
    return nil
  }
}

public enum NVRRouter {
  /// A fresh install opens the labeled demo. A saved host opens settings.
  public static func initial(store: NVRStore, demo: OfflineDemo?) -> NVRRoute {
    if store.isFreshInstall, let demo {
      return .offlineDemo(demo)
    }
    return .settings
  }

  public static func exitDemo() -> NVRRoute {
    .settings
  }

  public static func enterDemo(_ demo: OfflineDemo) -> NVRRoute {
    .offlineDemo(demo)
  }

  public static func showLive(_ configuration: NVRConfiguration) -> NVRRoute {
    .live(configuration)
  }
}
