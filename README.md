# 工具箱 / Toolbox

Independent iPhone and iPad utility collection. Bundle ID: `com.hority.toolbox`.

This initial version contains a tool catalog and a local text counter. Shortcut signing is clearly marked as planned and is not implemented. It does not claim to sign or install shortcuts.

## Development

Requires a Mac with Xcode supporting iOS 18, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open Toolbox.xcodeproj
bash ci/test.sh
bash ci/build.sh
```

`project.yml` is the source of truth for the generated project. The generated Xcode project is ignored. CI tests on an available iPhone simulator and creates an unsigned device archive. Simulator success does not replace real-device testing.

TestFlight is manual-only and requires owner-managed private signing setup. See [release instructions](docs/RELEASING.md). This repository contains no Penguin game code, assets, or signing material.

## Privacy and rights

See [privacy notes](PRIVACY.md). No general source or asset license is granted. Public visibility is not an additional redistribution or reuse license.
