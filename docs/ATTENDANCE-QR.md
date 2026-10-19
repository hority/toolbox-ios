# Attendance QR

## Intended behavior

Configure a fixed QR payload, label, attendance direction and 30/60-second duration in the system widget editor. A Lock Screen button invokes a LiveActivityIntent without deliberately opening the main app. Core Image generates the QR on-device. No network request records attendance: the workplace reader must scan the code.

The temporary card is a system-managed Live Activity, not a custom popup or arbitrary Lock Screen overlay. The implementation requests an activity and ends it with a future dismissal policy. This means the activity is ended immediately and its Lock Screen UI is retained until scheduled dismissal. Dynamic Island presentation can disappear immediately. No background timer or process lifetime is relied upon. iOS determines visibility, authentication and dismissal timing; verify on a real device before relying on this at work.

## Apple signing setup

1. Register explicit App ID `com.hority.toolbox.widgets` (description: Toolbox Widgets).
2. Using the existing Apple Distribution certificate, create an App Store Connect profile for that ID named `match AppStore com.hority.toolbox.widgets`.
3. Existing host App ID/profile remain `com.hority.toolbox` / `match AppStore com.hority.toolbox`. Live Activities use the host's `NSSupportsLiveActivities` Info.plist flag. No App Group or ActivityKit push capability is requested.
4. CI downloads both profiles read-only. Missing profiles fail rather than creating them. The app and extension have separate provisioning-profile build settings and export mappings.

No new key, certificate or GitHub secret is expected for this extension. If existing App Store Connect API permissions cannot retrieve its profile, inspect the error instead of broadening access automatically.

## Verification

- Fast unsigned device archive includes the embedded extension; no simulator is started by the build workflow.
- Unit tests remain a separate manual workflow. QR tests use synthetic text only.
- Real iPhone: configure separate attendance widgets, tap while locked, verify any authentication requirement, placement and readable size, verify 30/60-second dismissal, repeat taps, dismiss/close, test disabled Live Activities and device restart.
- Scan a synthetic QR from a second device/reader and confirm the exact decoded text. Confirm workplace approval before entering actual attendance data.
- On-device display, timing and reader compatibility are not established merely by a successful archive.

## Privacy

Widget configuration and ActivityKit state are managed by iOS. Payloads are passed directly; no App Group is used. The QR is visible to nearby observers while displayed. Do not commit real QR payloads, screenshots of real codes, employee identifiers or access tokens to this public repository.
