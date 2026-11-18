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

## Running the app

1. Install Xcode 16 or newer from the Mac App Store.
2. Clone this repo and open `LUPTZControl.xcodeproj`.
3. Press **Run** (⌘R). The first time, macOS asks to allow access to devices on your local
   network. Click **Allow**, or the app can't reach the cameras. (If you missed it:
   System Settings → Privacy & Security → Local Network.)
4. The **Find Cameras** window opens and scans your network. Select the cameras and click **Add**.

### What's in the app (step 2)

- Find Cameras: scans a network range for Panasonic cameras, handles cameras that need a login,
  or add one by IP address.
- Live video from each camera (MJPEG over HTTP, falling back to JPEG stills).
- Pan/tilt joystick with a speed limit, zoom rocker, auto/manual focus with a focus rocker.
- 24 presets: click to recall, turn on Save mode and click to store.
- Power on/standby and red tally.
- Camera list on the left, saved between launches. Passwords are kept in the macOS Keychain.

Control uses Panasonic's HTTP CGI commands (`/cgi-bin/aw_ptz`, `/cgi-bin/aw_cam`), sent no faster
than every 130 ms per camera as Panasonic recommends.

## Keyboard, gamepad and Stream Deck

Keyboard (the app window must be in front):

| Key | Action |
| --- | --- |
| Arrow keys (hold) | Pan / tilt. Hold Shift for full speed |
| `+` / `-` (hold) | Zoom in / out |
| `1`–`9`, `0` | Recall presets 1–10 |
| `[` / `]` | Previous / next preset |
| `F` | Push autofocus |
| `T` | Toggle tally |

Gamepad (Xbox, PlayStation and other controllers macOS supports): left stick pan/tilt,
right stick zoom, L2/R2 focus near/far, L1/R1 previous/next preset, D-pad presets 1–4,
A push AF, Y tally.

Stream Deck: add a **Hotkey** action for any of the keys above, e.g. `1` to recall preset 1.

## Scanning cameras from Terminal (optional)

```bash
bash tools/scan-cameras.sh 192.168.10              # first three numbers of a camera IP
bash tools/scan-cameras.sh 192.168.10 admin pass   # if the cameras need a login
```

The scan is read-only. It never moves the cameras. Results are saved to `cameras.csv`.
