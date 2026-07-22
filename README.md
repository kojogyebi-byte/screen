# Expanse

Use an Android tablet as a **real second display** for a Mac — not a mirror. macOS sees an actual extra monitor that you can drag windows onto, and the tablet renders it and sends your touches back as mouse input.

> The apps are branded **Expanse**; the build identifiers (Xcode target, bundle ID, Android package) remain `ScreenExtend` / `com.shamaapps.screenextend`.

Two apps live in this repo:

- `mac/` — native macOS app (Swift / SwiftUI). Creates a virtual display, captures it, encodes H.264, serves it over the network, and injects the tablet's touches as mouse events.
- `android/` — native Android tablet app (Kotlin / Jetpack Compose). Connects to the Mac, hardware-decodes the H.264 stream to the screen, and streams touch input back.

Both are designed to build entirely in the cloud with GitHub Actions — no local Xcode or Android Studio required.

## How it works

The Mac creates a virtual display using the private CoreGraphics `CGVirtualDisplay` API (the same mechanism BetterDisplay uses), so no kernel extension or DriverKit driver is needed on Apple Silicon. That display is captured with ScreenCaptureKit, encoded to H.264 with VideoToolbox, converted to Annex-B, and streamed over a single TCP connection. The tablet decodes with `MediaCodec` straight to a `SurfaceView`, and sends back normalized pointer events that the Mac maps into the virtual display's coordinate space and posts as `CGEvent` mouse actions.

Wire protocol is a tiny length-prefixed binary format: `[1 byte type][4 byte big-endian length][payload]`. Mac→tablet sends INFO (geometry JSON), CONFIG (SPS/PPS), and FRAME messages; tablet→Mac sends HELLO (its native resolution + name) on connect and POINTER messages while streaming. In **Automatic** mode the Mac reads the tablet's HELLO and creates the virtual display at the sharpest resolution that matches the tablet's aspect ratio (long edge capped at 2560 for bandwidth); **Manual** mode lets you pick from presets. Default port is `53121`.

## Building

Push the repo to GitHub. Each app builds from its own workflow under `.github/workflows/`, and both can also be run manually from the Actions tab (Run workflow).

**macOS** (`macos.yml`, runs on `macos-14`): selects the latest Xcode, installs XcodeGen, generates the Xcode project from `mac/project.yml`, builds Release ad-hoc signed, and uploads `Expanse-macos.zip` as a build artifact. Download it, unzip, and move `Expanse.app` to Applications.

**Android** (`android.yml`, runs on `ubuntu-latest`): builds a debug APK with Gradle and uploads it as the `Expanse-Android` artifact. Download the APK and sideload it onto the tablet (enable "Install unknown apps" for your file manager / browser).

The APK is debug-signed, which is fine for personal sideloading. For Play Store distribution you'd add a signed-release workflow with an upload keystore.

## macOS permissions

The Mac app needs two permissions, both granted in System Settings → Privacy & Security. The app shows the status of each and has buttons that jump straight to the right settings pane.

- **Screen Recording** — required to capture the virtual display. Without it you get a black screen on the tablet.
- **Accessibility** — required to inject mouse events into the virtual display. Without it the picture works but your touches do nothing.

After enabling either one you may need to quit and reopen the app.

## Connecting

1. Launch the Mac app, pick a resolution and frame rate, and press Start. It lists the Mac's local IP address.
2. Make sure the tablet is on the **same Wi-Fi network** as the Mac (5 GHz strongly recommended).
3. On the tablet, enter the Mac's IP address and port `53121`, then tap Connect.
4. A new display appears in System Settings → Displays on the Mac. Arrange it where you want relative to your main screen, then drag windows over.

## Touch mapping

- **One finger** — move / left-click / drag (direct touch: press, move, lift).
- **Two fingers dragging** — scroll.
- **Two-finger quick tap** — right-click.

If scrolling feels inverted, flip `SCROLL_SIGN` in `TouchHandler.kt`.

## Limitations

This is a functional v1. Know the trade-offs:

- The virtual display relies on a **private Apple API**. It works well today on Apple Silicon but is not guaranteed across future macOS releases, and Apple could change it without notice.
- Transport is **Wi-Fi LAN only** right now. Latency depends entirely on your network; a congested 2.4 GHz network will feel laggy. USB tethering is the obvious next step but isn't implemented.
- **HiDPI / Retina** scaling on the virtual display is experimental — start with the non-HiDPI presets if anything looks off.
- **Single tablet** per Mac session, **video only** (no audio is streamed), and there's no encryption on the link, so use it on a trusted network.
- Nothing here has been device-tested by me — treat the first run as the start of tuning the encoder bitrate / latency for your specific tablet and network.

## Troubleshooting

- **Black screen on the tablet** → Screen Recording permission isn't granted on the Mac, or the app wasn't restarted after granting it.
- **Picture works but touches do nothing** → Accessibility permission isn't granted on the Mac.
- **Can't connect** → wrong IP, devices on different networks/VLANs, or a firewall blocking port `53121`. Confirm the IP shown in the Mac app and that both devices are on the same Wi-Fi.
- **Laggy / stuttery** → move to 5 GHz Wi-Fi, lower the resolution or frame rate, or reduce distance to the router.

## Splitting into two repos

It's a monorepo for convenience. If you'd rather keep separate per-app repos (matching your usual setup), move `mac/` into one repo and `android/` into another, and drop the corresponding workflow file into each — they're already self-contained and scoped to their own folder.
