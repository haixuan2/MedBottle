# MedBottle

MedBottle is a SwiftUI iOS app for tracking medications, dose history, refills, and reminder notifications. It keeps medication data on device and uses RxNav/openFDA lookups to help fill in medication names, shapes, and prescription/OTC classification when adding a new medication.

## Features

- Add and manage multiple medications.
- Track tablets remaining and tablets per dose.
- Log doses and keep dose history.
- Refill a medication bottle back to a chosen count.
- Set daily, custom-day, or as-needed reminders.
- Log a dose or snooze directly from reminder notifications.
- Search medication names through RxNav and resolve classification details through openFDA.
- View each medication with a custom 3D bottle scene.

## Project Structure

- `MedBottle/MedBottle.xcodeproj` - Xcode project.
- `MedBottle/MedBottle/` - SwiftUI app source.
- `MedBottle/MedBottleTests/` - Unit tests.
- `MedBottle/MedBottle/Resources/` - Runtime resources such as the HDR lighting file used by the bottle scene.
- `MedBottle/MedBottle/Assets.xcassets/` - App icons, accent color, and other asset catalog files.

## Requirements

- Xcode with iOS 26 simulator support.
- Swift 5.
- Internet access for medication search results.

## Getting Started

1. Open the project in Xcode:

   ```sh
   open MedBottle/MedBottle.xcodeproj
   ```

2. Select the `MedBottle` scheme.
3. Choose an iOS simulator or device.
4. Build and run.

The app ships with a sample medication if no saved data exists yet. Medication and dose history are stored locally using `UserDefaults`.

## Running Tests

From Xcode, select the `MedBottle` scheme and run the test suite.

From the command line, use an available iOS simulator destination:

```sh
xcodebuild test \
  -project MedBottle/MedBottle.xcodeproj \
  -scheme MedBottle \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

If your installed simulator has a different name, replace `iPhone 17` with a device from Xcode's Devices and Simulators window.

## Notes

- Notification reminders require notification permission at runtime.
- RxNav and openFDA requests are best-effort; the add-medication form still works if lookup details are unavailable.
- The current app target deployment setting is iOS 26.0.
