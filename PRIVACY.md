# Privacy

Toolbox has no analytics, advertising, or tracking SDK. The shortcut mini app optionally connects to the user’s ChatGPT account. Tool search and text counting run locally. Text-counter input is kept in memory and is not intentionally persisted or transmitted.

The shortcut studio saves user-created/imported drafts and their recent editing history in the app’s on-device Application Support directory with iOS file protection. Deleting a draft removes it from this library; separately exported files remain under the user’s control. Signed files are temporarily stored for the system share sheet and cleaned up when sharing finishes.

ChatGPT login opens OpenAI’s browser consent page. Validated account identity, issued client registration, tokens and a random opaque host ID are stored in this app’s device-only Keychain namespace. The app contacts OpenAI authentication endpoints to sign in, validate identity, refresh and revoke sessions. Signing out clears local tokens but retains the account/client mapping and opaque host ID for returning sign-in; remote revocation failures are disclosed with a link to ChatGPT settings.

Only after explicit generation confirmation, the typed request and, if separately selected, the current draft’s name and full JSON are sent to `api.openai.com`. This may include embedded text, URLs and attachments. Selection defaults to off. The generation path never reads the saved library, editing history, QR configuration, clipboard or files implicitly. Do not include secrets or sensitive QR values in a request or selected draft. Model catalog requests use the active account’s access token. Generation consumes that account’s available ChatGPT usage and sends `store:false`; OpenAI’s processing policies still apply. The app does not log credentials or user content. Responses become editable previews and are saved only when explicitly accepted.

Only after the user confirms signing, the complete shortcut definition (including embedded text, URLs and data) is sent via HTTPS to Shortcuty at `sign.shortcuty.app`. Shortcuty is an independent service that performs Apple shortcut signing. Do not submit shortcuts containing passwords, tokens, confidential information, or personal data that should not be shared. No API key or Apple account credential is requested by this app for signing. The request does not send the local draft library or editing history.

The system share sheet sends exported or signed files to the destination the user chooses. The app does not automatically install or run shortcuts. Apple Shortcuts makes the final trust/import decision.

These notes describe the implemented app behavior, not a completed App Store privacy declaration. Reassess Apple privacy/export-compliance disclosures before public App Store submission or when features change.

## Attendance QR widget

QR text and labels are entered in the system widget configuration on the device. The widget’s default launch delivers its configuration on device through WidgetKit’s NSUserActivity to open the app’s full-screen QR after normal system authentication. The legacy App Intent / Live Activity path is retained. The screen prevents idle sleep only while visible and active. There is no QR server, account, analytics, or automatic attendance submission. No App Group is used. iOS manages widget configuration and Live Activity state; this is not a promise that OS-managed configuration is excluded from device backups.

A displayed attendance QR can be read by nearby people or cameras, including on the Lock Screen. Users should follow their employer's rules and should not store passwords or unrelated secrets in QR configuration. iOS controls authentication, visibility and removal timing. Removing a widget and dismissing its card removes those visible instances; the app does not provide remote revocation of fixed QR contents.

## Brushing coach

The brushing coach uses the front camera only while its screen is open and the app is active. Frames are analyzed on device with Apple's Vision framework to place the bunny/panda effects and to measure motion around the mouth, then discarded. No photo, video or face data is saved or transmitted. The stamp card keeps only each completed session's date, star count and chosen mask in this app's on-device settings; it is never transmitted. The score is a motion-based guide for children and does not assess plaque or oral health.
