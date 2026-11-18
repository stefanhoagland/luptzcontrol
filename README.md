# LU PTZ Control

A Mac app (iPad later) for controlling Panasonic PTZ cameras (AW-UE150 and others) with live video
and full camera controls, similar to Panasonic PTZ Control Center.

## Plan

1. **Check the cameras** – `tools/scan-cameras.sh` scans the camera VLAN and reports each camera's
   model, firmware, PTZ control and RTSP/NDI video status.
2. **Basic Mac app** – SwiftUI app with camera list, live video, pan/tilt joystick, zoom, presets.
3. **Full feature set** – focus, iris, white balance, gain/shutter, multi-camera grid, tally,
   saved setups, USB joystick / gamepad / Stream Deck.
4. **iPad version** – touch-friendly controls from the same codebase.

## Scanning cameras

```bash
bash tools/scan-cameras.sh 192.168.10              # first three numbers of a camera IP
bash tools/scan-cameras.sh 192.168.10 admin pass   # if the cameras need a login
```

The scan is read-only. It never moves the cameras. Results are saved to `cameras.csv`.
