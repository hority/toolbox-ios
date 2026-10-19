#!/bin/bash
set -euo pipefail
mkdir -p build
xcodegen generate
xcodebuild -project Toolbox.xcodeproj -scheme Toolbox -configuration Release -destination 'generic/platform=iOS' -archivePath build/Toolbox.xcarchive CODE_SIGNING_ALLOWED=NO archive | tee build/archive.log
