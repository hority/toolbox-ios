# Shortcut signing

Port of the owner’s prior Shortcut Studio utility, limited to local import/edit/history/export and Shortcuty signing. No game implementation or assets are used. Optional AI generation/login, RoutineHub credentials and custom server configuration are not included.

## Service and consent

The app sends unsigned binary Apple plist data to `https://sign.shortcuty.app/api/v1/sign`, using the documented unauthenticated raw-byte request. It asks before each send and identifies the destination and complete shortcut content being transmitted. The service can have outages, queueing, timeouts and rate limits. No own Mac or new backend is provisioned.

Official service documentation: https://github.com/Shortcuty/Signing-Server-API-Documentation

The response must decode as a signed AEA archive and contain the same workflow definition that was submitted. Container validation does not establish Apple issuer trust; the Apple Shortcuts app performs the final trust and import checks. The app never executes shortcut actions.

## Verification

Unit tests cover the local format validation and signing request/response handling. CI does not call the public signing API. The UI sharing, file-import permissions, final Apple trust/import acceptance and actual shortcut execution require real-iPhone verification and are not implied by compilation or unit-test success.

A separate live check uses only a synthetic one-alert workflow containing no personal data, credentials, or user files. Current verification results are reported with the release, including service failures.

### Live check: 2026-10-19

A synthetic alert-only unsigned binary plist was sent to the documented endpoint. Both the initial request and one bounded retry returned HTTP 502; `/healthz` returned HTTP 200 with `status: ok` between them. No signed artifact was returned. Therefore current live signing success and iPhone import have not been verified. No user shortcut, personal information or credential was submitted in this check.

A single diagnostic comparison using the service-advertised multipart upload also returned plain-text HTTP 504 after about 34.5 seconds, while GET `/api/v1` succeeded. The input parsed as a valid 727-byte binary plist. This weakens a raw-upload-format mismatch explanation, but does not establish the precise root cause or which gateway/origin component failed; provider logs would be needed. No further automated live retries were made.
