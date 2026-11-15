# IMove for iPhone and iPad

A native SwiftUI app for controlling the IMove Mac server from an iPhone or iPad. Nothing needs to be installed on the target USB iPhone: Tailscale only has to run on the Mac and on the device **you control it from**.

For the goal of changing a device's own Find My location without a Mac, and the architectural limits between devices, see [DEVICE_ECOSYSTEM.md](../docs/DEVICE_ECOSYSTEM.md). The current version does not change the system location of the iPad it runs on.

## Features

- Pairing with a Tailscale Serve address and a 32-character code; the code is stored in the device Keychain.
- Mac/USB status, sending a hand-picked location or this device's own location, a 1–60 second Mac refresh interval, stopping fixed refresh, and removing the simulated location.
- Adding, sending and deleting saved places.
- Picking points on an Apple MapKit map, with the last sent location and route path drawn on top.
- Viewing, starting and stopping saved routes. Creating new routes with stops, custom segment durations, evenly split total time, walking paths and waypoints, and B1/M2/M6 stations with transfers.
- Optional device tracking: sends new location fixes at most every five minutes and requests a fresh fix every five minutes while the app is running. iOS does not guarantee an exact five-minute interval or continuous background execution.

## Setup

1. Open `IMoveMobile.xcodeproj` on a Mac with full Xcode installed.
2. Under **Signing & Capabilities** for the `IMoveMobile` target, choose your own Apple account/team. Change the bundle identifier if needed. Connect the iPhone/iPad, select it as the run destination and press **Run**. If the device asks for Developer Mode or developer trust, approve it in the device's Settings.
3. With IMove running on the Mac, start Tailscale Serve with `tailscale serve --bg 8765`. Sign the Mac and the controlling device in to the same Tailscale account.
4. On the app's **Connection** tab, enter the `https://…ts.net` address and the pairing code shown in IMove on the Mac. Do **not** use Funnel.

Minimum system version: iOS/iPadOS 15.0. iPhone and iPad share a single Xcode target (`TARGETED_DEVICE_FAMILY = 1,2`). The app needs the route and place APIs of the current IMove Mac version.

## Verification

The iPhone/iPad device target and the iOS Simulator target were built without errors in Xcode 27. The app was installed, launched and visually checked on the iPhone 18 Pro and iPad Pro 11-inch simulators. It was also installed on a physical iPad (A16, iPadOS 27) with a personal development team, launched after granting developer trust, and used to send locations through the Mac.

If the command-line developer directory still points to the Command Line Tools, prefix Xcode commands in Terminal with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. This is not needed when working in the Xcode app.
