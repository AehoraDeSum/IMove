# IMove for macOS 1.1.0

The main IMove app. It manages the simulated location of an iPhone connected to the Mac over USB, and serves a private control API and web page so that Android, iPhone, iPad and browsers can send locations, saved places and routes.

## Install

Unzip **IMove-1.1.0-macOS-arm64.zip** and copy the single **IMove.app** into your Applications folder. The USB tool is bundled inside the app, so no separate Python environment or third-party device manager is needed. Connect and unlock the iPhone, then scan for and select it on the Connection screen. Mount the developer image if asked. Pairing codes, saved places and routes from earlier versions are kept under the same Mac user account.

## Remote access

Install Tailscale on **the Mac and on the Android/iPhone/iPad you will control it from**. The iPhone connected over USB does not need Tailscale just to receive locations. In the Mac app, open Remote access → Start control page, then run `tailscale serve --bg 8765` on the Mac. Open the private HTTPS address it prints on the other device. Do not use Funnel.

## Features

- A USB refresh interval of 1–60 seconds on the Location screen.
- Picking points on the map, saving them as places, and building routes with any number of stops. Each segment can have its own minutes and seconds.
- Saved-place shortcuts that are shared by the Mac, Android and web interfaces.
- Dark and light map styles. Android and the web use OpenStreetMap; Apple MapKit JS would work on those devices but needs an Apple Developer Maps token.
- Android Tracking sends the phone's location about every five minutes; web tracking only runs while the page is open. The Mac must stay connected over USB.

### Istanbul rail routes

The route editor can add consecutive sections of the **B1 Marmaray, M2 and M6** lines by choosing boarding and alighting stations. Nearby transfers at Yenikapı and Levent are joined with short walks. For other boarding points, use "Walk to boarding station" first. You can reshape a segment with waypoints on the map, or snap it to Apple Maps' pedestrian route with "Calculate walking path". Walking calculations run on the Mac and need internet: Apple Maps is tried first, and if it does not answer the FOSSGIS Valhalla demo service is used, which means the chosen walking coordinates are sent to FOSSGIS. The result is shared with Android and the web.

Station names were checked against the operators' pages. Approximate line geometry was taken from a third-party open map layer and bundled for offline use; it contains no real-time service or timetable data. Default segment durations are drafts, so edit them before saving. The M2 Şişhane–Taksim source path is incomplete, so that section is marked approximate. Sources: [Metro Istanbul M2](https://metro.istanbul/Hatlarimiz/HatDetay?hat=M2), [M6](https://metro.istanbul/Hatlarimiz/HatDetay?hat=M6), [TCDD Marmaray](https://www.tcddtasimacilik.gov.tr/marmaray/tr/neredennereye), [third-party ArcGIS map layer](https://services5.arcgis.com/tj2c2sBQpCvO7ufK/ArcGIS/rest/services/%C4%B0stanbul_Rayl%C4%B1_Sistemler_Kronoloji_Haritas%C4%B1_WFL1/FeatureServer).

## Building from source

Full instructions are in [Guide.html](Guide.html).

```bash
./BuildUSB.command   # builds the bundled USB tool (needs internet the first time)
./Build.command      # builds IMove.app
./Test.command       # runs the logic tests
```
