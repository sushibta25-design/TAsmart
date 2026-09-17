TAsmart 0.5.2 stable recovery

Purpose:
- Roll back the experimental Vision/CoreML AI integration that was added after the last working A510 stream baseline.
- Keep bundle identifier/executable compatibility with com.sushibta.a510player / A510Player.
- Change only visible branding to TAsmart.
- No MiniBridge/CarPlay hooks are added to the app.
- Test iPhone launch first, then CarBridge ON/OFF.

If this build launches again, re-add AI later behind an opt-in module after the stream/CarPlay baseline is stable.
