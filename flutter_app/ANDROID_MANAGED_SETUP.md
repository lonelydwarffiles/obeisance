# Obeisance Android Managed Setup (Device Admin + Accessibility)

This runbook gets a test device into full enforcement mode.

## 1) Prerequisites

- Android 9+ recommended (package suspension requires API 28+).
- USB debugging enabled.
- adb installed and available in PATH.
- Build and install app once:

```powershell
cd flutter_app
flutter pub get
flutter run
```

## 2) Provision as Device Owner (best for full MDM)

Device Owner provisioning only works on a freshly reset / unprovisioned device.

1. Factory reset device/emulator.
2. Install APK via adb.
3. Run:

```powershell
adb shell dpm set-device-owner com.obeisance.app/.ObeisanceDeviceAdminReceiver
```

Expected success message includes `Success: Device owner set`.

If you need to remove it on a test device:

```powershell
adb shell dpm remove-active-admin com.obeisance.app/.ObeisanceDeviceAdminReceiver
```

## 3) Grant Accessibility Service

In app: `Compliance Checklist` -> `Accessibility Service` -> enable `ScrollService`.

Or direct adb deep-link to settings UI:

```powershell
adb shell am start -a android.settings.ACCESSIBILITY_SETTINGS
```

## 4) Validate Runtime Compliance in App

Open `Compliance Checklist` and use `Refresh Status`.

You should see:

- Ignore Battery Optimizations: Granted
- Device Admin: Granted
- Accessibility Service: Granted

## 5) Exact Alarm + Slumber Mode

Android 12+ may require manual exact-alarm allowance in system settings for strict timing.

If alarms seem delayed, verify:

- App not battery-optimized.
- Exact alarm permission allowed by OEM settings.

## 6) Common Failure Modes

- `admin_required` errors when suspending packages:
  - App is not active Device Admin / Device Owner.
- Accessibility appears enabled but app says false:
  - Ensure `ScrollService` is enabled (not another service).
  - Tap `Refresh Status` after returning from settings.
- `set-device-owner` fails:
  - Device already provisioned. Factory reset and retry.

## 7) Quick sanity commands

```powershell
adb shell dpm list owners
adb shell dumpsys device_policy
adb shell settings get secure enabled_accessibility_services
```
