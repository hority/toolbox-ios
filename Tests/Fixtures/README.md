# Public synthetic shortcut fixture

Generated on 2026-10-20 using a single documented Shortcuty signing request. The input contains only an alert titled “Synthetic fixture” with “No personal data”. No user shortcut, credential, photo, QR, or other user content is included. Files are test resources, not application content.

- synthetic-input.plist: exact unsigned bytes submitted; SHA-256 71c8514f734d0ff2102c094d5ca342d46ff85b0a83c46703265e2b1c6cd1b59d
- synthetic-signed.shortcut: HTTP 200 AEA1 result; SHA-256 76a6bda56494c92fa70f5eb97517266c2f8988a07152900c8990bbc6c83f2c2d
- synthetic-returned.plist: recovered binary plist from the inner AA01 payload, using an independent decoder and the included public certificate's key. It differs from input in signer-normalized workflow metadata. Tests accept only the five bounded serialization-bookkeeping differences described in the signing notes; semantic or unknown-field changes must still be rejected.

The fixture is never executed. Its embedded public certificate is used for integrity verification only; Apple Shortcuts determines issuer trust/import acceptance. No signing private key is included.

A second synthetic photo-filter/preview fixture was signed on the same date (no photo data or real library access was involved). Its actions are `is.workflow.actions.filter.photos` and `is.workflow.actions.previewdocument`, with a synthetic limit of one. The response changed exactly the same five metadata fields and preserved actions/parameters. `synthetic-photo-signed.shortcut` SHA-256: ff03efc2b1c4e580fca6e6cf6ab36d396e9861564bf8e235d70fc21e7e6fbfa6.
