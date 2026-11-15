# IMove Probe (experimental)

A small iOS 15+ app that reports the iPhone's **Core Location** reading to IMove on the Mac. It does not send locations over USB and it cannot read what the other side sees in Find My directly. It was written as an experiment after Safari repeatedly returned `No GPS` on an iPhone 6s while Apple Maps and Find My still showed a location: the goal is a local location reading that does not depend on Safari.

> **Status:** the source, project file and Info.plist were checked, but the app has not yet been built and tested on a device. Do not treat it as a reliable background verification tool until it has been proven on hardware.

## Setup and testing

1. Open `IMoveProbe.xcodeproj` on a Mac with full Xcode. In **Signing & Capabilities** for the `IMoveProbe` target, choose your Apple development team and set a unique bundle identifier if needed.
2. Connect the iPhone to that Mac, choose it as the run destination and run the app. Then connect the phone back to the Mac running IMove over USB.
3. Join the iPhone to the same private Tailscale network as the Mac. Enter the existing `https://…ts.net` address and the Mac app's 32-character pairing code in IMove Probe.
4. Tap **Start reading** and allow location access when iOS asks. With the app open, check that coordinates, accuracy, time and any simulation flag appear on screen. If there is an error, note its domain and code. The app listens for regular Core Location updates instead of Safari's one-shot request. To keep it running on the lock screen, set the app's Location permission to **Always** in Settings, and do not close it from the app switcher.
5. The **Location** screen of IMove on the Mac shows the new reading, its accuracy and the distance from the last USB coordinate. The Android and web screens show the same status. If the app sends no report for 30 seconds, IMove marks the result as **out of date**.

iOS may delay background readings and network requests; there is no guaranteed 5 or 10 second rate. While a route keeps changing the USB command, the iPhone reading may still belong to the previous command and IMove will wait for a newer one. A Core Location match only tests the iPhone's location API; check the screen of the person receiving the Find My share separately.
