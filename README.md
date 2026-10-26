# CORTEX for iOS

Native iPhone/iPad port of the existing Cortex Consumer Android app. The goal is the same design, content, and behavior, with no redesign.

## Current state

The port includes catalog browsing, chapter lists, heading search, and outlines against the actual bundled Android catalog (14 subjects, 126 chapters, 2,603 headings). It also supports importing personal DOCX files, offline reading with the Android rendering engine, heading navigation, saved reading position, sharing the original Word file, and deleting imported notes. The original fonts and palette are reused. It is not yet a complete copy: Firebase accounts, trial enforcement, shared document downloads, annotations, and study tools are still pending. The library metadata is bundled; the shared document bodies are not.

The Swift code compiled successfully on a hosted macOS runner in [build #1](https://github.com/nayanby/Cortex-IOS/actions/runs/40406193244), producing a simulator app artifact. The app has not been launched or visually tested. See [port status](docs/PORT-STATUS.md) for the remaining work.

## Personal Word documents

Use the import icon at the upper right of Deep Dive to choose a `.docx` in Files. Imported notes appear under **My notes** and remain available after relaunch. Open a note to read it; the outline button jumps to headings and Share exports the original DOCX. Long-press an imported note to delete its local copy. Imports currently have a 32 MB limit. These documents stay in the app's local storage and are not uploaded to Firebase.

The reader bundles JSZip, the extracted `DocxPrototype`, the Android formula patch, Android styles, and the original fonts. It does not include the exported author's embedded study state or provider keys. The native bridge passes document bytes as WebKit arguments, blocks external page navigation, and uses a restrictive content security policy. It is not yet connected to catalog downloads.

`CortexTests/ReaderTests.swift` exercises actual WKWebView rendering with a synthetic DOCX containing a heading, literal script-like text, a table and a formula. It also checks imported-byte persistence and deletion. The cloud workflow runs these tests on an iPhone simulator.

The Xcode 16.4 / iOS 18.5 simulator on the hosted runner has [a WebKit runtime startup issue](https://bugs.webkit.org/show_bug.cgi?id=293831). Following Apple's workaround, only the separate simulator test products use an iOS 18.4 deployment target. The normal app build still targets iOS 17; this test run does not establish iOS 17 runtime compatibility.

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
xcodegen generate
xcodebuild -project Cortex.xcodeproj -scheme Cortex -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Local validation

```sh
node scripts/validate-catalog.cjs
```

This checks the imported catalog data; it does not compile Swift or verify the UI.

## Reference source

Android source: `../Cortex Consumer 2`, inspected at version 1.0.22 (version code 52). `Reference/android-source-manifest.json` records source hashes so later Android changes can be identified. `Reference/WebReader` contains unmodified reader integration assets as porting references; they are excluded from the iOS app. In particular, `bridge.js` requires Android's synchronous JavaScript bridge and must not be injected into WKWebView unchanged.

Existing Android signing keys, embedded beta credentials, Firebase account data, and local build secrets have not been imported.

## Platform references

- [GitHub-hosted macOS runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [Apple Developer Program enrollment](https://developer.apple.com/help/account/membership/program-enrollment)
- [Apple distribution and TestFlight membership](https://developer.apple.com/help/account/membership/programs-overview/)
- [WKURLSchemeHandler](https://developer.apple.com/documentation/webkit/wkurlschemehandler)
