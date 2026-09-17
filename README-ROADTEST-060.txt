TAsmart 0.6.0 road test
- No MiniBridge.
- Keeps RTSP/RTP parser but replaces AVSampleBufferDisplayLayer with VideoToolbox -> CVPixelBuffer -> normal CALayer.
- Aspect Fill removes black side bars.
- Live-first rendering drops frames when renderer is busy instead of building latency.
- On-screen meter: receive/decode/render latency estimate (ms), displayed fps, dropped render frames.
- Install-time helper attempts to add com.sushibta.a510player to CarBridge bridgedApps if CarBridge prefs exist. It does not inject into CarPlay/SpringBoard.
