# 工具箱 / Toolbox

Independent iPhone and iPad utility collection. Bundle ID: `com.hority.toolbox`.

The app contains a tool catalog, local text counter, Shortcut signing studio, and a children’s brushing coach (front-camera 2-minute guide with on-device bunny/panda effects; see [privacy notes](PRIVACY.md)). The signing studio reuses the owner’s earlier utility: import JSON/plist/`.shortcut`, edit and save local drafts with history, export editing data, and request signing from Shortcuty after explicit confirmation. It never runs shortcuts. Optional ChatGPT login and AI generation create editable draft previews after explicit transmission confirmation. Only selected current draft material is sent; library history and QR configuration are excluded. Paid RoutineHub and custom-server setup are not included. See [signing notes](docs/SHORTCUT-SIGNING.md) and [AI implementation and verification notes](docs/SHORTCUT-AI.md).

ChatGPT flow eligibility and actual user consent remain unverified; this preparation does not infer a licensing requirement from the repository’s existing rights notice.

## Development

Requires a Mac with Xcode supporting iOS 18, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open Toolbox.xcodeproj
bash ci/test.sh
bash ci/build.sh
```

`project.yml` is the source of truth for the generated project. The generated Xcode project is ignored. Like Penguin, builds run only when manually dispatched; pushes and pull requests do not start builds. The Build iOS workflow creates an unsigned device archive with a 10-minute limit and does not start a simulator. Simulator tests remain available separately in the manual Simulator tests workflow. TestFlight uploads are manual and do not run simulator tests. Simulator success does not replace real-device testing.

TestFlight is manual-only and requires owner-managed private signing setup. See [release instructions](docs/RELEASING.md). This repository contains no Penguin game code, assets, or signing material.

The brushing coach bundles the DotGothic16 font under the SIL Open Font License 1.1 (`Toolbox/Resources/Fonts/DotGothic16-OFL.txt`). Its mask sprites were made with OpenAI image generation and pixelated locally; germ, nose and star sprites are hand-authored.

## Privacy and rights

See [privacy notes](PRIVACY.md). No general source or asset license is granted. Public visibility is not an additional redistribution or reuse license.

## Attendance QR (WidgetKit)

The attendance widget accepts fixed QR text in the system widget settings and generates QR images locally. Its circular or rectangular Lock Screen launcher opens a full-screen shared arrival/departure QR after normal system authentication, preventing idle sleep only while the QR is visible and the app is active. See `docs/ATTENDANCE-QR.md` for setup and device-verification requirements. The widget extension uses `com.hority.toolbox.widgets` and requires its own App Store profile named `match AppStore com.hority.toolbox.widgets`; no App Group or push service is used.
