// SPDX-License-Identifier: MIT
// Fork addition (mENtuDeN/IPCamKit): PlayOptions for ONVIF replay and playback speed.

import Foundation
import Testing

@testable import IPCamKit

@Suite struct PlayOptionsTests {
  @Test func liveIsTheOriginalPlayRequest() {
    let live = PlayOptions.live
    #expect(live.range == "npt=0.000-")
    #expect(live.scale == nil)
    #expect(live.requestHeaders.isEmpty)
  }

  @Test func clockTimestampIsUTCWithMilliseconds() {
    // 2026-11-03 14:00:05.250 UTC
    let date = Date(timeIntervalSince1970: 1_793_714_405.25)
    #expect(PlayOptions.clockTimestamp(date) == "20261103T140005.250Z")
  }

  @Test func onvifReplayAsksForClockRangeAndReplayFeature() {
    let date = Date(timeIntervalSince1970: 1_793_714_400)
    let options = PlayOptions.onvifReplay(from: date, scale: 2)
    #expect(options.range == "clock=20261103T140000.000Z-")
    #expect(options.scale == 2)
    #expect(options.requestHeaders == [RTSPHeaderField(name: "Require", value: "onvif-replay")])
  }
}
