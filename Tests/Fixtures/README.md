# Public synthetic shortcut fixture

Generated on 2026-10-20 using a single documented Shortcuty signing request. The input contains only an alert titled “Synthetic fixture” with “No personal data”. No user shortcut, credential, photo, QR, or other user content is included. Files are test resources, not application content.

- synthetic-input.plist: exact unsigned bytes submitted; SHA-256 71c8514f734d0ff2102c094d5ca342d46ff85b0a83c46703265e2b1c6cd1b59d
- synthetic-signed.shortcut: HTTP 200 AEA1 result; SHA-256 76a6bda56494c92fa70f5eb97517266c2f8988a07152900c8990bbc6c83f2c2d
- synthetic-returned.plist: recovered binary plist from the inner AA01 payload, using an independent decoder and the included public certificate's key. It differs from input in signer-normalized workflow metadata. Tests must reject that input/output difference, not whitelist it away.

The fixture is never executed. Its embedded public certificate is used for integrity verification only; Apple Shortcuts determines issuer trust/import acceptance. No signing private key is included.
