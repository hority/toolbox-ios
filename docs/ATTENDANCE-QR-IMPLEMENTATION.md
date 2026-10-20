# Attendance QR implementation and verification

## Current flow

The small circular Lock Screen widget (or an existing rectangular widget) opens
Toolbox directly to a full-screen QR after the system's normal authentication.
Arrival and departure use the same verbatim payload. There is no intervening Live
Activity or enlargement button in this route. Close returns to the tool catalog.
An unconfigured, invalid or missing configuration opens setup guidance instead.

`AttendanceQRWidget` retains its kind and configuration intent type. It uses the
normal WidgetKit tap behavior, without `Button`, `Link` or `widgetURL`. WidgetKit
passes an `NSUserActivity` containing the tapped widget's configuration. The scene
delegate checks `WidgetCenter.UserInfoKey.kind`, then uses
`widgetConfigurationIntent(of:)`; it never chooses the first installed widget or
places a QR in a URL. No custom URL scheme or guessed activity type is needed.

Cold launch reads `connectionOptions.userActivities`; warm delivery uses
`scene(_:continue:)`. Both enter the same handler. SwiftUI injects the observable
scene delegate into that scene's environment. Each scene owns its own presentation
state. Repeat taps replace that scene's current configuration; they do not stack
modal presentations. Closing clears that scene's payload reference.

## Compatibility and privacy

Label and payload retain their original parameter names, validation limits
(16 characters / 64 UTF-8 bytes for label; 64 UTF-8 bytes for payload) and verbatim
payload semantics. Legacy operation and duration parameters, enum cases, intent
identities and activity types remain in the binary for archived configurations.
Operation and duration are omitted from the editor summary and ignored by the
full-screen route. Existing rectangular widgets remain supported. Changing to a
circular widget is optional; add the small variant in the Lock Screen editor.

Legacy Live Activity code is retained for previously archived buttons/cards, but
the current widget view never calls it. An old widget snapshot may remain until
WidgetKit reloads its timeline; update/re-add the widget if necessary. The old
request-then-immediate-end path was not a scheduled active timer: `.after` controls
removal of already-ended content. This patch does not rely on that lifecycle.

No App Group, entitlement, provisioning-profile, credential, network, analytics,
extra payload file, log or persistent app storage is introduced. WidgetKit owns
the saved configuration. The QR is removed from the view when the scene becomes
inactive, and is marked privacy-sensitive; device testing must check app-switcher
snapshots. Screen recording/screenshots and copies of the fixed QR cannot be
revoked by closing the screen.

## Rendering and idle sleep

The QR canvas fills the smaller available dimension after safe areas, a close
header, concise instructions and 16-point outer padding. It is capped at 1024
points. Canvas size and placement are snapped to physical pixels. The renderer
keeps M correction, strips Core Image's border, adds exactly four white modules
on every edge and renders whole physical pixels per module, without interpolation.
The quiet zone is part of the canvas, not part of the usable QR matrix.

For a symbol with N modules, scale S and canvas C:

- Pixels per module: floor(C × S / (N + 8))
- Usable matrix side: N × pixels per module / S
- Bitmap side including quiet zone: (N + 8) × pixels per module / S
- Each quiet-zone edge: 4 × pixels per module / S

The released card used a 136-point canvas in a 156-point card. This full-screen
view sizes to actual available space, so there is no single fixed new QR size.
For example, a 361-point canvas at 3x with a 29-module symbol gives a 280.33-point
matrix in a 357.67-point bitmap, including a 38.67-point quiet zone per edge.
These are layout calculations, not measurements of a real device or user's QR.

A successfully rendered QR in an active scene acquires an idle-timer lease.
Inactive/background, close, rendering failure or disappearance releases it.
The first lease snapshots `UIApplication.isIdleTimerDisabled`; the last release
restores that value, including a preexisting `true`. Duplicate callbacks are
idempotent and multiple scenes cannot prematurely release each other's lease.
Foregrounding takes a new snapshot. No brightness, system Auto-Lock setting,
audio session, background execution or authentication policy is changed.
This prevents ordinary idle sleep while viewing the QR, not deliberate device
locking or other system interruptions. The full-screen QR has no 30/60-second
expiry; the user closes it after scanning.

## Verification

The editing environment is Linux without Swift, Xcode or XcodeGen. No iOS build,
XCTest, Vision test, simulator, camera, authentication or real-device behavior has
been run here. No external CI was launched. `git diff --check` and local patch
application checks are the available static checks; see the accompanying local
verification report for results.

Source tests added for routing to setup/QR, replacing repeated requests, close and
reopen, ignoring unrelated activities, legacy operation/duration, idle restoration
from both prior states, multiple scene leases, larger render sizes, quiet zones,
pixel alignment and Vision byte decoding. The routing tests inject configuration
extraction; they do not simulate WidgetKit's archive or OS cold/warm scene delivery.
Existing tests remain intact. Simulator tests remain optional and manual-only.

Before release on an iPhone, check installed rectangular widget migration, the
new circular widget, cold/warm launches, exact tapped configuration with multiple
widgets, repeated taps, invalid/empty input, close/reopen, Home/app switcher,
background/foreground, screen lock/unlock, Face ID/passcode, split view/rotation,
large text, app-switcher privacy and real scanner decoding. Confirm auto-lock
resumes after leaving QR and after closing. Use only synthetic test payloads in
recorded evidence.

## Apple references

- [Widget configuration delivery](https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget)
- [Default widget tap and NSUserActivity](https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity)
- [Configuration extraction](https://developer.apple.com/documentation/foundation/nsuseractivity/widgetconfigurationintent(of:))
- [SwiftUI scene delegate injection](https://developer.apple.com/documentation/swiftui/uiapplicationdelegateadaptor)
- [Idle timer scope](https://developer.apple.com/documentation/uikit/uiapplication/isidletimerdisabled)
- [Widget interaction and authentication](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- [Legacy ended-card dismissal](https://developer.apple.com/documentation/activitykit/activityuidismissalpolicy/after(_:))
