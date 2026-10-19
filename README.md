# 工具箱 / Toolbox

Independent iPhone and iPad utility collection. Bundle ID: `com.hority.toolbox`.

The app contains a tool catalog, local text counter, and Shortcut signing studio. The signing studio reuses the owner’s earlier utility: import JSON/plist/`.shortcut`, edit and save local drafts with history, export editing data, and request signing from Shortcuty after explicit confirmation. It never runs shortcuts. Optional AI generation, ChatGPT login, paid RoutineHub and custom-server setup from the earlier prototype are not included in this focused port. See [signing notes](docs/SHORTCUT-SIGNING.md).

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

## Privacy and rights

See [privacy notes](PRIVACY.md). No general source or asset license is granted. Public visibility is not an additional redistribution or reuse license.
