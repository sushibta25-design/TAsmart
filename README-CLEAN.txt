A510Player v0.4.1 iPhone CLEAN baseline

Purpose:
- Restore a simple iPhone-only baseline before adding CarPlay back.
- No CarPlay scene manifest.
- CarPlaySceneDelegate is not compiled.
- Only one PlayerViewController starts the RTSP loop.
- Video gravity is Aspect Fit so the entire decoded frame is visible.

Test:
1. Build/install this package.
2. Respring only if your install flow normally requires it.
3. Connect the iPhone to the A510 network exactly as you did when the stream previously worked.
4. Open A510Player on iPhone.
5. Do NOT connect CarPlay for this first test.

If the screen is still black, the next target is RTSP/SDP/H264 diagnostics rather than CarPlay lifecycle.
