# Attendance QR implementation and verification

## Contract

- iOS 18 / Swift 6, `AppIntentConfiguration`, Lock Screen `accessoryRectangular`
- Label, verbatim UTF-8 QR payload, 登庁/退庁 and 30/60 seconds are configured per widget
- Empty/whitespace-only payloads and payloads exceeding 64 UTF-8 bytes are rejected
- The verb label is descriptive; it does not modify payload bytes or confirm that a time clock accepted a scan
- Widget parameters are passed directly to `ShowAttendanceQRIntent`; no App Group, shared database or network is required
- WidgetKit stores the widget configuration and ActivityKit holds its content. The app does not write extra payload files, analytics, logs or images
- Both intent types and attributes are in both targets. Define `TOOLBOX_WIDGET_EXTENSION` in the extension only. `LiveActivityIntent` executes in the host app; `openAppWhenRun` is false

## Lifecycle: scheduled dismissal, not scheduled active termination

`Activity.request(attributes:content:pushType: nil)` is followed immediately by
`await activity.end(content, dismissalPolicy: .after(expiresAt))`.

Apple's iOS 18 public API does **not** have an `end(afterDate:)` operation. The
code ends the activity immediately, preserves the final QR content on the Lock
Screen, and asks the OS to remove that ended card after 30 or 60 seconds. It does
not keep a background task alive, schedule a notification, request background
execution, or depend on the app remaining alive. Dynamic Island ends immediately;
its supplied layouts are fallback/brief presentations, not a lasting QR surface.

The OS owns actual presentation/removal timing. No sub-second deadline or
unconditional visibility is promised. `staleDate`, `context.isStale` and explicit
date validation suppress a QR whenever an expired view is rendered; reading
`Date()` is not a scheduler and does not itself cause a redraw. Dismissing a card
does not revoke a fixed QR or invalidate copies/screenshots of its payload.

An already-ended card is not guaranteed to support a second content update,
second end call, or interactive button. The Lock Screen card therefore says to
use the system swipe-to-dismiss affordance. `HideAttendanceQRIntent` can stop an
activity that is still active/stale, and reports a missing/ended activity instead
of claiming success. It is only used in the brief Dynamic Island fallback.

Repeated taps are serialized during creation. The host attempts to clear known
earlier cards before creating another, but this is only best effort for cards
already ended. After process termination, the previous ended card might not be
returned by `Activity.activities` and may coexist until its original OS dismissal
date. No persistent handle or payload store is introduced to conceal this limit.

## Rendering

Core Image generates an M-correction QR. The renderer finds and removes the
generator's border, then adds exactly four white modules on every edge. It checks
for a valid 21–37 module symbol and paints each module at an integer physical
pixel size into a binary black/white bitmap. No interpolation, fractional resize,
URL lookup, remote QR service, tinting or cached personal image is used.

The QR sits inside a 136-point white square; the full card is 156 points tall.
At 2x/3x display scale, the bitmap including its quiet zone is 123–136 points
depending on QR version. Spare pixels are assigned asymmetrically when needed
so the image origin is not shifted onto a half pixel. The QR is privacy-sensitive
and can be hidden by system redaction; users must check their Lock Screen settings.
Real scanners, screen brightness, Always-On dimming, contrast and user settings
can affect readability.

## Verification status

No Xcode/Swift toolchain is installed in the implementation environment. No
simulator or Vision test has been run, and no device behavior is claimed verified.
The optional, manually dispatched simulator tests include:

- Vision QR decoding to exact `payloadData` UTF-8 bytes at 2x and 3x
- ASCII, Japanese, decomposed Unicode, whitespace and maximum-length fixtures
- Exact four-module white quiet zone, integer modules and binary pixels
- 64-byte input limit, label validation, 30/60-second-only validation
- Expired, stale, stopped and malformed content states do not expose a QR
- Intent parameters preserve bytes and do not request foreground app opening
- Encoded activity attributes/content remain well below 4 KB

Before release, manually check on an iPhone: app UI does not open from the widget;
both configured verbs; 30/60-second OS dismissal with the app suspended/terminated;
repeated taps; swipe dismissal; disabled Live Activities; locked/unlocked and
privacy-redacted states; Always-On; 2x/3x QR scanning; and the actual workplace
reader using a user-provided test code. Keep actual QR payloads out of logs,
screenshots, source control and test fixtures.

## Apple references

- [LiveActivityIntent](https://developer.apple.com/documentation/appintents/liveactivityintent)
- [Adding interactivity](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- [Displaying Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [Ending an activity](https://developer.apple.com/documentation/activitykit/activity/end(_:dismissalpolicy:))
- [OS dismissal policy](https://developer.apple.com/documentation/activitykit/activityuidismissalpolicy/after(_:))
- [Configurable widgets](https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget)
- [Vision raw barcode bytes](https://developer.apple.com/documentation/vision/vnbarcodeobservation/payloaddata)
