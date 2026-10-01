# Pepper Watch

[![Tests](https://github.com/TristanListanco/Pepper-Watch/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/TristanListanco/Pepper-Watch/actions/workflows/tests.yml)

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

The [Tests workflow](.github/workflows/tests.yml) runs both suites on every pull request and every push to `main`.
