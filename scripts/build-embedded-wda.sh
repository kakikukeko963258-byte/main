#!/bin/bash
set -euo pipefail
WDA_REV=d17782422d55ff1e5e0ceb74eb1fd509cc0c35b6
git clone --filter=blob:none https://github.com/appium/WebDriverAgent.git wda-source
git -C wda-source checkout "$WDA_REV"
# A real dynamic framework is signed by AltForge's existing framework signer.
# Put the WDA XCTest entry point in this framework, avoiding a second app or
# an unsigned .xctest plug-in. The main executable never links this framework.
ruby - <<'RUBY'
require 'xcodeproj'
project = Xcodeproj::Project.open('wda-source/WebDriverAgent.xcodeproj')
target = project.targets.find { |t| t.name == 'WebDriverAgentLib' }
raise 'WDA library target missing' unless target
file = project.main_group.new_file('WebDriverAgentRunner/UITestingUITests.m')
target.source_build_phase.add_file_reference(file)
project.save
RUBY
xcodebuild -project wda-source/WebDriverAgent.xcodeproj -target WebDriverAgentLib \
  -configuration Release -sdk iphoneos \
  CONFIGURATION_BUILD_DIR="$PWD/wda-products" CODE_SIGNING_ALLOWED=NO build
APP=build/Build/Products/Release-iphoneos/main.app
mkdir -p "$APP/Frameworks"
ditto wda-products/WebDriverAgentLib.framework "$APP/Frameworks/WebDriverAgentLib.framework"
find "$APP/Frameworks/WebDriverAgentLib.framework" -type d \( -name Headers -o -name PrivateHeaders -o -name Modules \) -prune -exec rm -rf {} +
cp wda-source/LICENSE "$APP/WebDriverAgent-LICENSE.txt"
python3 - "$APP" "$WDA_REV" <<'PY'
import json, plistlib, sys
from pathlib import Path
app = Path(sys.argv[1])
framework = app / 'Frameworks/WebDriverAgentLib.framework'
info = plistlib.loads((framework / 'Info.plist').read_bytes())
assert info['CFBundlePackageType'] == 'FMWK'
assert (framework / info['CFBundleExecutable']).is_file()
metadata = dict(revision=sys.argv[2], bundlePath='Frameworks/WebDriverAgentLib.framework',
                requiresXCTestLaunch=True, port=8100, mjpegPort=9100)
(app / 'EmbeddedWDA.json').write_text(json.dumps(metadata, indent=2))
PY
/usr/bin/codesign --force --sign - "$APP/Frameworks/WebDriverAgentLib.framework"
/usr/bin/nm -gU "$APP/Frameworks/WebDriverAgentLib.framework/WebDriverAgentLib" | grep '_OBJC_CLASS_\$_UITestingUITests'

