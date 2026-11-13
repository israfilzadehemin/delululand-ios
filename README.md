# Delulutopia for iOS

The native iOS app of Delululand (users see **Delulutopia**). Same functionality as the Android app;
iOS components on the Delulutopia look.

- Design: "Delululand — iOS App Design" (canvas + project doc). Web prod CSS is the visual source of truth
  for content; the canvas decides the iOS chrome (decision D5).
- Decisions: project doc "Delululand — iOS Build".

## Requirements

| | |
| --- | --- |
| Mac | Apple silicon, macOS Tahoe 26.6 or later |
| Xcode | 27.1 or later (Swift 6.4, iOS 27 SDK) |
| Minimum iOS | 17.0 (Liquid Glass on iOS 26+, classic bars before) |
| Tools | `brew install xcodegen` |

## Open and run

```sh
xcodegen generate          # only after editing project.yml; the generated project is committed
open Delulutopia.xcodeproj
```

| Scheme | Server | Bundle id | Home Screen name |
| --- | --- | --- | --- |
| Delulutopia Staging | test.delulutopia.com | `com.delulutopia.app.test` | Delulutopia TST |
| Delulutopia | delulutopia.com | `com.delulutopia.app` | Delulutopia |

Release rule: every change goes to staging (TestFlight) first, prod only after sign-off.

## Layout

```
App/                         app target: entry point, Info.plist, assets, privacy manifest
Configs/                     Staging.xcconfig, Prod.xcconfig
Packages/DelulutopiaKit/     all code, as local Swift packages
  Sources/Core/DesignSystem  DLDesignSystem: colours, type, motion, glass, components, fonts
  Sources/Core/Data          DLData: device settings, build config
  Sources/App/Shell          AppShell: tab bar and the screens behind it
  Tests/                     unit tests (Swift Testing) and the screenshot helper
App/ScreenTests/             screenshots, hosted by the app (DelulutopiaScreens)
project.yml                  XcodeGen spec (source of Delulutopia.xcodeproj)
tools/                       icons, fonts, CI scripts
```

Swift 6 language mode with complete concurrency checking; SwiftUI first, UIKit only where SwiftUI
falls short; Apple frameworks only at runtime (decisions D1, D3, D4).

## Tests and screenshots

```sh
# unit tests
cd Packages/DelulutopiaKit
xcodebuild test -scheme DelulutopiaKit-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
# screenshots (hosted by the app so system glass renders)
xcodebuild test -project Delulutopia.xcodeproj -scheme "Delulutopia Staging" -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

CI (`.github/workflows/ci.yml`, `xcode-27` runner) builds Staging and Prod, runs the tests and publishes
the screenshots to the [`ci-screenshots`](../../tree/ci-screenshots) branch, one folder per branch.
Screenshots are review material, not a gate. Set `DL_SNAPSHOT_DIR` to choose where local runs write them.

## Assets

- `tools/icons/render.py` renders the app icons (default, dark, tinted; staging adds a TST band),
  the launch mark and the asset-catalog colours.
- Fonts: Manrope, Literata, Caveat (SIL OFL, `tools/fonts/licenses`). Manrope carries capital schwa Ə
  merged from Noto Sans (`tools/fonts/merge_schwa.py`).
