# CORTEX for iOS

Native iPhone/iPad port of the existing Cortex Consumer Android app. The goal is the same design, content, and behavior, with no redesign.

## Current state

The port includes catalog browsing, chapter lists, heading search, personal Word imports and the offline Android rendering engine. The latest source adds the Google sign-in gate, account restoration/sign-out, first-login trial transaction, account-specific imports, shared catalog refresh and lazy document downloads. These latest additions are undergoing cloud/emulator validation. Annotations, study tools, the full Android home/navigation and real-device parity remain unfinished.

The app compiled and both reader integration tests passed on a hosted iPhone simulator in [build #6](https://github.com/nayanby/Cortex-IOS/actions/runs/40408756211), testing commit `de16dc4`. Checks cover Word tables/formulas, escaped text, font loading, heading navigation, scroll restoration, native progress persistence and imported-document storage/deletion. Visual parity and real-device behavior remain unverified. See [port status](docs/PORT-STATUS.md) for the remaining work.

## Personal Word documents

Use the import icon at the upper right of Deep Dive to choose a `.docx` in Files. Imported notes appear under **My notes** and remain available after relaunch. Open a note to read it; the outline button jumps to headings and Share exports the original DOCX. Long-press an imported note to delete its local copy. Imports currently have a 32 MB limit. These documents stay in the app's local storage and are not uploaded to Firebase.

The reader bundles JSZip, the extracted `DocxPrototype`, the Android formula patch, Android styles, and the original fonts. It does not include the exported author's embedded study state or provider keys. The native bridge passes document bytes as WebKit arguments, blocks external page navigation, and uses a restrictive content security policy. It is not yet connected to catalog downloads.

`CortexTests/ReaderTests.swift` exercises actual WKWebView rendering with a synthetic DOCX containing a heading, literal script-like text, a table and a formula. It also checks imported-byte persistence and deletion. The cloud workflow runs these tests on an iPhone simulator.

The Xcode 16.4 / iOS 18.5 simulator on the hosted runner has [a WebKit runtime startup issue](https://bugs.webkit.org/show_bug.cgi?id=293831). Following Apple's workaround, only the separate simulator test products use an iOS 18.4 deployment target. The normal app build still targets iOS 17; this test run does not establish iOS 17 runtime compatibility.

## Firebase setup

`Cortex Consumer iOS` is registered in the existing `cortex-v1b` project. A validated `Config/GoogleService-Info.plist` enables the SDK and Google sign-in; the actual file is local and excluded from Git. Run `python3 scripts/prepare-firebase.py` before generating the Xcode project to configure the Google callback scheme. Firebase is pinned to 12.19.3 and Google Sign-In to 9.2.0 for the runner's toolchain. See [Firebase setup status](docs/FIREBASE-IOS-SETUP.md).

The cloud workflow can optionally receive the complete plist through a private repository Actions secret named `FIREBASE_IOS_CONFIG_PLIST`. That secret has not been created. Without it, debug builds offer an offline library preview; release builds do not enable sign-in. Live Google OAuth and production App Check still need validation on an appropriately configured Apple device or simulator. Production backend rules have not been changed.

Current Android policy, re-read for this port: Google is the visible sign-in route, the first eligible login starts one 60-day trial, device/session restrictions are disabled, and signed-in free accounts can read notes. Full/trial/beta access enables remote catalog refresh and the later study tools. The iOS source preserves this policy rather than enabling the older two-phone restriction described by stale comments.

Shared Word downloads are authenticated, cancellable and cached for 24 hours with ETag invalidation. Shared raw DOCX export remains disabled; personal imports can still be shared. Account profile caches use Keychain and are accepted only for the same authenticated UID/email on network faults, never for disabled accounts or permission failures.

## Build without owning a Mac

1. Place this project in a GitHub repository.
2. Run **iOS simulator build** in the repository's Actions tab.
3. The workflow installs XcodeGen, generates the Xcode project from `project.yml`, and builds the iOS simulator app without signing.
4. Download `Cortex-iOS-Simulator` to inspect the build artifact. A simulator `.app` cannot be installed on an iPhone or run on Windows.

The repository is [nayanby/Cortex-IOS](https://github.com/nayanby/Cortex-IOS). GitHub Actions availability and usage charges depend on the account and repository. See its Actions tab for build results.

Installing through TestFlight requires Apple Developer Program enrollment, an App Store Connect app, signing configuration, and a separate device archive/upload workflow. No signing credentials are included. There is no need to purchase a Mac to use a hosted macOS builder, but simulator testing still needs a Mac environment or a cloud device service.

For a macOS environment:

```sh
brew install xcodegen
python3 scripts/prepare-firebase.py
xcodegen generate
xcodebuild -project Cortex.xcodeproj -scheme Cortex -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Local validation

```sh
node scripts/validate-catalog.cjs
```

This checks the imported catalog data; it does not compile Swift or verify the UI.

## Account/download integration tests

The new integration test uses a named `demo-cortex-ios` app against localhost Auth, Firestore and Storage emulators, synthetic users and a generated DOCX. It does not use production credentials. Test-host startup explicitly suppresses production initialization. App Check's test provider is confined to the test bundle and accepts only this demo project.

On macOS with Node, Java 21, Python and XcodeGen installed:

```sh
python3 scripts/prepare-firebase.py
xcodegen generate
npx --yes firebase-tools@15.34.1 emulators:exec --project demo-cortex-ios \
  --config test-backend/firebase.json --only auth,firestore,storage \
  'bash scripts/run-ios-emulator-tests.sh'
```

Never deploy `test-backend/` rules to the live project. They are a disposable test harness, not a production security policy. Live OAuth, App Check registration, production rule compatibility and cross-platform account behavior still need manual acceptance testing.

## Reference source

Android source: `../Cortex Consumer 2`, inspected at version 1.0.22 (version code 52). `Reference/android-source-manifest.json` records source hashes so later Android changes can be identified. `Reference/WebReader` contains unmodified reader integration assets as porting references; they are excluded from the iOS app. In particular, `bridge.js` requires Android's synchronous JavaScript bridge and must not be injected into WKWebView unchanged.

The account/download phase was re-audited against Android 1.0.23. `Reference/consumer-access-contract.json` records that source hash and current access behavior. The reader extraction retains its original 1.0.22 provenance until the final parity audit.

Existing Android signing keys, embedded beta credentials, Firebase account data, and local build secrets have not been imported.

## Platform references

- [GitHub-hosted macOS runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [Apple Developer Program enrollment](https://developer.apple.com/help/account/membership/program-enrollment)
- [Apple distribution and TestFlight membership](https://developer.apple.com/help/account/membership/programs-overview/)
- [WKURLSchemeHandler](https://developer.apple.com/documentation/webkit/wkurlschemehandler)
