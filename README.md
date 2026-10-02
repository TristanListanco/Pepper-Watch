# Pepper Watch

[![Tests](https://github.com/TristanListanco/Pepper-Watch/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/TristanListanco/Pepper-Watch/actions/workflows/tests.yml)
[![Static Analysis](https://github.com/TristanListanco/Pepper-Watch/actions/workflows/static-analysis.yml/badge.svg?branch=main)](https://github.com/TristanListanco/Pepper-Watch/actions/workflows/static-analysis.yml)

On-device aphid detection for bell pepper fields. The iPhone and iPad app scans leaves with a Core ML model and keeps every result on the device. A companion Apple Watch app and widgets show each field's status at a glance.

## Requirements

- Xcode 27
- iOS / iPadOS 27 and watchOS 27

## Running the tests

The app and the watch app each have a Swift Testing suite. In Xcode, choose the **Pepper Watch** or **PepperWatchWatchApp** scheme and press ⌘U, or run them from the command line:

```sh
xcodebuild test -project "Pepper Watch.xcodeproj" -scheme "Pepper Watch" \
  -destination "platform=iOS Simulator,name=iPhone 17"

xcodebuild test -project "Pepper Watch.xcodeproj" -scheme PepperWatchWatchApp \
  -destination "platform=watchOS Simulator,name=Apple Watch Ultra 4 (49mm)"
```

The **Pepper Watch** scheme also runs `PepperWatchUITests`, which runs Xcode's accessibility audit (contrast, element descriptions, hit regions, Dynamic Type, clipped text and traits) on each screen of the app, opened on demo data. Contrast and Dynamic Type findings the app has today are reported as expected failures, so they stay visible in the test report while the rest of the audit gates the build.

The [Tests workflow](.github/workflows/tests.yml) runs all of these on every pull request and every push to `main`.

## Static analysis

Two layers check the code without running the app:

- **SwiftLint** lints every target with the rules in [`.swiftlint.yml`](.swiftlint.yml). Install it with `brew install swiftlint` and run `swiftlint` from the repository root.
- **`StaticAnalysisTests`**, a Swift Testing suite in `PepperWatchTests`, reads the Xcode project and the sources each target compiles. It checks that SF Symbol and asset names resolve, that every SwiftData model is in the schema, that privacy-protected APIs have usage descriptions, that entitlements work with a free developer account, and that shipped code has no `print` calls, leftover TODOs or plain-HTTP URLs. It runs with the other tests on ⌘U, and failures point at the offending line.

The [Static Analysis workflow](.github/workflows/static-analysis.yml) runs SwiftLint in strict mode and shows findings inline on pull requests. The Tests workflow also fails on any compiler warning.
