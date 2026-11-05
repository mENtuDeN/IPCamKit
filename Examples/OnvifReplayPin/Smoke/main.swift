// Copyright (c) 2026 Steel Brain
// SPDX-License-Identifier: MIT
// Mac smoke for the pinned ONVIF replay API. No network and no credentials.

import Foundation
import IPCamKit

let date = Date(timeIntervalSince1970: 1_793_714_400)
let options = PlayOptions.onvifReplay(from: date, scale: 1)
precondition(options.range == "clock=20261103T140000.000Z-", options.range)
precondition(options.scale == 1)
precondition(
  options.requestHeaders == [RTSPHeaderField(name: "Require", value: "onvif-replay")]
)
print("onvif replay smoke \(options.range)")
