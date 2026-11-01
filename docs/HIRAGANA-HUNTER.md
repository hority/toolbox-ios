# ひらがなハンター

Photograph signs and printed pages to collect the 46 basic hiragana (あ〜ん) into a zukan. Each letter can be caught many times; the zukan cell shows the latest crop and a ×N badge.

## Engines chosen (researched 2026-11)

- **Live view:** VisionKit `DataScannerViewController` with `.text(languages: ["ja-JP"])`, accurate quality and system highlighting. Its `recognizedItems` stream drives the live “みえてる” chip. Requires an A12-or-newer device; unsupported devices fall back to picking a photo.
- **Capture:** `capturePhoto()` (or a PhotosPicker image) is read by Vision `VNRecognizeTextRequest` (accurate, `ja-JP`, language correction). Per-character boxes come from `boundingBox(for:)`; when a line-sized box is returned, the line is divided evenly (horizontal or vertical writing). Only one crop per letter per photo is offered, and the child can untick misreads before saving.
- **Precision filters (fewer misreads, lower recall by design):** a line counts only with top-candidate confidence ≥ 0.5, at least two non-punctuation characters and ≥ 80% Japanese script (no Latin/symbol-mixed garbage, no lone glyphs). The photo is also read horizontally flipped; when the flipped image reads the same place at least as confidently, the line is treated as mirrored text and dropped. Letters smaller than 18 px (of a 2400 px photo) are ignored. Camera shots additionally require the letter to have been seen by the live scanner within the last 3 seconds. Thresholds are constants in `HiraganaReader` for tuning after device tests.
- **Voice:** `AVSpeechSynthesizer` with the best installed `ja-JP` voice (premium > enhanced > default). Letters are spoken via katakana so a lone は/へ is not read as a particle. Sign in with ChatGPT supports only the Responses API (no speech/realtime/audio endpoints per OpenAI's preview limitations), so cloud TTS is not used; Personal/premium voices can be downloaded by the user in iOS Settings → Accessibility → Spoken Content.
- **AI:** not needed for v1. If later added (e.g. word hints), it uses the shared AI設定 `ChatGPTAccount`.

Only the 46 basic letters are collected. Voiced (が), small (ゃ, っ) and katakana are ignored; text is NFC-normalized first.

## Storage

`Application Support/HiraganaHunter/catches.json` plus one 240×240 JPEG crop per catch. Full photos are not kept. Nothing is sent.

## Unverified

No Swift compiler in the preparation environment; build is checked by CI. Recognition quality, per-character crop accuracy for Japanese, DataScanner start timing, voice quality and the UI must be checked on a real device.
