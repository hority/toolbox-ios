# ひらがなハンター

Photograph signs and printed pages to collect the 46 basic hiragana (あ〜ん) into a zukan. Each letter can be caught many times; the zukan cell shows the latest crop and a ×N badge.

## Engines chosen (researched 2026-11)

- **Live view:** VisionKit `DataScannerViewController` with `.text(languages: ["ja-JP"])`, accurate quality and system highlighting. Its `recognizedItems` stream drives the live “みえてる” chip. Requires an A12-or-newer device; unsupported devices fall back to picking a photo.
- **Capture:** `capturePhoto()` (or a PhotosPicker image) is read by Vision `VNRecognizeTextRequest` (accurate, `ja-JP`, language correction). Per-character boxes come from `boundingBox(for:)`; when a line-sized box is returned, the line is divided evenly (horizontal or vertical writing). Only one crop per letter per photo is offered, and the child can untick misreads before saving.
- **Voice:** `AVSpeechSynthesizer` with the best installed `ja-JP` voice (premium > enhanced > default). Letters are spoken via katakana so a lone は/へ is not read as a particle. Sign in with ChatGPT supports only the Responses API (no speech/realtime/audio endpoints per OpenAI's preview limitations), so cloud TTS is not used; Personal/premium voices can be downloaded by the user in iOS Settings → Accessibility → Spoken Content.
- **AI:** not needed for v1. If later added (e.g. word hints), it uses the shared AI設定 `ChatGPTAccount`.

Only the 46 basic letters are collected. Voiced (が), small (ゃ, っ) and katakana are ignored; text is NFC-normalized first.

## Storage

`Application Support/HiraganaHunter/catches.json` plus one 240×240 JPEG crop per catch. Full photos are not kept. Nothing is sent.

## Unverified

No Swift compiler in the preparation environment; build is checked by CI. Recognition quality, per-character crop accuracy for Japanese, DataScanner start timing, voice quality and the UI must be checked on a real device.
