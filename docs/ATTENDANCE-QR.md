# Attendance QR

## Intended behavior

Add the small circular **勤怠QR** widget in Lock Screen customization, then tap it
while still editing to set a label and the fixed QR text. Arrival and departure
use one identical QR. Existing rectangular widgets also work. Finish editing;
tapping the widget opens Toolbox directly to a full-screen QR after any required
system unlock. Invalid or missing configuration opens setup instructions.

The QR is generated locally and remains until Close. While it is visible and the
app is active, ordinary idle sleep is disabled. Leaving the app hides the QR and
restores the previous idle-timer state; returning shows it again. Close returns
to the catalog. This does not bypass authentication or prevent the power button
from locking the device. No Live Activity permission is required for this flow.

Old operation/duration settings remain stored for compatibility but do not affect
the full-screen QR. The current widget no longer invokes the old Live Activity
button. WidgetKit may retain an earlier snapshot until its timeline reloads;
re-add the widget if it still behaves like the old release.

WidgetKit delivers the selected configuration through NSUserActivity; QR payloads
are not placed in URLs, logs or additional app storage. No App Group is needed.
See [implementation notes](ATTENDANCE-QR-IMPLEMENTATION.md) for lifecycle details.

## Apple signing setup

1. Register explicit App ID `com.hority.toolbox.widgets` (description: Toolbox Widgets).
2. Using the existing Apple Distribution certificate, create an App Store Connect profile for that ID named `match AppStore com.hority.toolbox.widgets`.
3. Existing host App ID/profile remain `com.hority.toolbox` / `match AppStore com.hority.toolbox`. Live Activities use the host's `NSSupportsLiveActivities` Info.plist flag. No App Group or ActivityKit push capability is requested.
4. CI downloads both profiles read-only. Missing profiles fail rather than creating them. The app and extension have separate provisioning-profile build settings and export mappings.

No new key, certificate or GitHub secret is expected for this extension. If existing App Store Connect API permissions cannot retrieve its profile, inspect the error instead of broadening access automatically.

## Verification

- Fast unsigned device archive includes the embedded extension; no simulator is started by the build workflow.
- Unit tests remain a separate manual workflow. QR tests use synthetic text only.
- Real iPhone: verify circular and existing rectangular widgets, cold/warm launch, exact tapped configuration, lock/authentication, repeat taps, close, background/foreground, screen locking, idle-timer restoration, rotation and readable size.
- Scan a synthetic QR from a second device/reader and confirm the exact decoded text. Confirm workplace approval before entering actual attendance data.
- On-device display, timing and reader compatibility are not established merely by a successful archive.

## Privacy

Widget configuration and ActivityKit state are managed by iOS. Payloads are passed directly; no App Group is used. The QR is visible to nearby observers while displayed. Do not commit real QR payloads, screenshots of real codes, employee identifiers or access tokens to this public repository.
