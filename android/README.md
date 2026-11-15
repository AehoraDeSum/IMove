# IMove for Android 1.1.0

A dark-green Android client that brings the Mac app's Location, Map, Saved places, Routes and Tracking sections together in one menu. On the Connection screen you sign in with the private HTTPS address published by Tailscale Serve on the Mac and the 32-character pairing code. The code is encrypted with the Android Keystore; codes saved by older versions are migrated to encrypted storage at launch, and Sign out removes the code and stops tracking.

Install the APK over an existing IMove Android installation; the application ID and local signing key are unchanged. IMove 1.1.0 must be running on the Mac, and the Mac and phone must be on the same private Tailscale network. The iPhone connected over USB does not need Tailscale.

The Location screen sends coordinates and can refresh a fixed location every 1–60 seconds. Places and route points can be picked on the map. Saved places and routes are stored on the Mac. Routes can have any number of stops; the total time can be split evenly or each segment can get its own minutes and seconds. The Tracking screen sends the phone's location about every five minutes with a visible notification.

Saved places appear as quick picks on the Location screen. The map opens full screen and switches between dark and light styles. Maps use OpenStreetMap data; Apple MapKit JS requires a Maps token and is not included in this version.

## Building

Requires JDK 17 or newer, Android SDK 36 and the Gradle Wrapper:

```bash
./gradlew assembleDebug
```

The APK is written to `app/build/outputs/apk/debug/app-debug.apk`. A local `.signing/debug.keystore` is only used for development and is not part of the repository; the same key is needed to install updates over an earlier build.
