#!/bin/bash
set -euo pipefail
APP_PATH="build/Build/Products/Release-iphoneos/main.app"
EXT_PATH="$APP_PATH/PlugIns/PCFileBridgeFileProvider.appex"
ENTITLEMENTS="$RUNNER_TEMP/bridge.entitlements"
python3 - "$APP_PATH" "$EXT_PATH" <<'PY'
import plistlib, sys
from pathlib import Path
app, extension = [plistlib.loads((Path(p) / 'Info.plist').read_bytes()) for p in sys.argv[1:]]
for key in ('CFBundleShortVersionString', 'CFBundleVersion'):
    assert app[key] == extension[key], f'App and extension differ: {key}'
assert extension['CFBundleIdentifier'].startswith(app['CFBundleIdentifier'] + '.')
PY
cat > "$ENTITLEMENTS" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.application-groups</key><array><string>group.com.kakikukeko.main.pcfilebridge</string></array>
</dict></plist>
EOF
/usr/bin/codesign --force --sign - --entitlements "$ENTITLEMENTS" "$EXT_PATH"
/usr/bin/codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_PATH"
/usr/bin/codesign --verify --deep --strict "$APP_PATH"
mkdir -p dist/Payload
/usr/bin/ditto "$APP_PATH" dist/Payload/main.app
(cd dist && /usr/bin/zip -qry main.ipa Payload)
