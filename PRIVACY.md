# Privacy

Toolbox has no account, analytics, advertising, or tracking SDK. Tool search and text counting run locally. Text-counter input is kept in memory and is not intentionally persisted or transmitted.

The shortcut studio saves user-created/imported drafts and their recent editing history in the app’s on-device Application Support directory with iOS file protection. Deleting a draft removes it from this library; separately exported files remain under the user’s control. Signed files are temporarily stored for the system share sheet and cleaned up when sharing finishes.

Only after the user confirms signing, the complete shortcut definition (including embedded text, URLs and data) is sent via HTTPS to Shortcuty at `sign.shortcuty.app`. Shortcuty is an independent service that performs Apple shortcut signing. Do not submit shortcuts containing passwords, tokens, confidential information, or personal data that should not be shared. No API key or Apple account credential is requested by this app for signing. The request does not send the local draft library or editing history.

The system share sheet sends exported or signed files to the destination the user chooses. The app does not automatically install or run shortcuts. Apple Shortcuts makes the final trust/import decision.

These notes describe the implemented app behavior, not a completed App Store privacy declaration. Reassess Apple privacy/export-compliance disclosures before public App Store submission or when features change.

## Attendance QR widget

QR text and labels are entered in the system widget configuration on the device. The widget passes this data to a local App Intent to generate a QR image and show a short-lived Live Activity. There is no QR server, account, analytics, or automatic attendance submission. No App Group is used. iOS manages widget configuration and Live Activity state; this is not a promise that OS-managed configuration is excluded from device backups.

A displayed attendance QR can be read by nearby people or cameras, including on the Lock Screen. Users should follow their employer's rules and should not store passwords or unrelated secrets in QR configuration. iOS controls authentication, visibility and removal timing. Removing a widget and dismissing its card removes those visible instances; the app does not provide remote revocation of fixed QR contents.
