#!/bin/bash
set -euo pipefail
node scripts/seed-emulators.cjs
DEVICE_ID=$(xcrun simctl list devices available -j | python3 -c "import json,sys; d=json.load(sys.stdin); print(next(x['udid'] for k,v in d['devices'].items() if 'iOS' in k for x in v if x['name'].startswith('iPhone')))")
xcrun simctl bootstatus "$DEVICE_ID" -b
# Pass only a test selector to the app, never production credentials.
export SIMCTL_CHILD_CORTEX_TEST_EMULATORS=1
xcodebuild -project Cortex.xcodeproj -scheme Cortex -configuration Debug \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" -parallel-testing-enabled NO \
  -clonedSourcePackagesDirPath .spm-cache -derivedDataPath test-build \
  -resultBundlePath build/ReaderTests.xcresult IPHONEOS_DEPLOYMENT_TARGET=18.4 CODE_SIGNING_ALLOWED=NO test
