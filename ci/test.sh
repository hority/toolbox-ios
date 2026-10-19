#!/bin/bash
set -euo pipefail
mkdir -p build
xcodegen generate
# Use an installed, available iPhone rather than assuming a specific simulator model.
DEVICE_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); phones=[x["udid"] for k,v in d["devices"].items() if "iOS" in k for x in v if x.get("isAvailable") and x["name"].startswith("iPhone")]; assert phones, "No available iPhone simulator"; print(phones[0])')
xcodebuild -project Toolbox.xcodeproj -scheme Toolbox -destination "platform=iOS Simulator,id=$DEVICE_ID" -resultBundlePath build/Tests.xcresult CODE_SIGNING_ALLOWED=NO test | tee build/test.log
