#!/bin/bash
set -euo pipefail
mkdir -p build
swiftc -swift-version 6 \
  Toolbox/Models/Shortcuts/ShortcutModels.swift \
  Toolbox/Models/ChatGPTButtonPalette.swift \
  Toolbox/Services/ShortcutImport.swift \
  Toolbox/Services/ShortcutSigner.swift \
  ci/verify-shortcut-fixture.swift -o build/verify-shortcut-fixture
build/verify-shortcut-fixture "$PWD/Tests/Fixtures"
