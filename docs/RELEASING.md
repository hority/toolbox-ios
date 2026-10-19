# TestFlight setup

App identity: `com.hority.toolbox`; display name: 工具箱; suggested SKU: `hority-toolbox-ios`.

The owner must first create the Apple Developer App ID and App Store Connect app record. CI does not register apps or create certificates/profiles.

## Signing prerequisite

Create an App Store distribution profile for `com.hority.toolbox` in Apple Developer, named `match AppStore com.hority.toolbox`, selecting the same existing distribution certificate used by Penguin. Existing valid distribution certificates may be reused. The new Bundle ID needs its own profile. Never copy private repository history, keys, certificates, or profiles into this public repository. CI imports certificates from readonly match with profile syncing disabled, then downloads only the existing named profile from Apple using readonly `get_provisioning_profile`. It will fail if the profile is absent, expired, or not readable by the API key. No profile import into Git, extra profile secret, certificate creation, or private-key export is needed.

## GitHub environment

Create/configure `testflight` with deployment restricted to `master`; preserve any intended approval gate. Variables: `APPLE_TEAM_ID`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `MATCH_GIT_URL` (credential-free HTTPS `.git` URL of private signing repository).

Owner-entered secrets: `APP_STORE_CONNECT_PRIVATE_KEY`, `MATCH_PASSWORD`, `SIGNING_GIT_TOKEN` (read-only access to private signing repository). Do not paste these into chat, commit them, or grant unnecessary access. Repository secrets cannot be read back from another repository. Configure them through secure owner-controlled setup.

## Release

After unsigned CI passes and signing setup is complete, manually run **Upload to TestFlight (manual)** from master. The workflow uploads only to TestFlight, waits for processing, and does not submit external beta or App Store review. Tester group membership is not changed. Verify delivery and flows on the real device separately. Builds increment from the latest TestFlight build for version 0.1.0.

The workflow intentionally does not run automatically on pushes. This repository's initialization does not authorize installing credentials or expanding persistent access.
