# CORTEX for iOS

Native iPhone/iPad port of the existing Cortex Consumer Android app. The goal is the same design, content, and behavior, with no redesign.

## Current state

Initial source only; not yet a complete or verified iOS app. Catalog browsing, chapter lists, heading search, and outlines are implemented against the actual bundled Android catalog (14 subjects, 126 chapters, 2,603 headings). The original Averia fonts and blue/ink palette are reused. There is no account, document, trial, or backend access in this initial build. The library metadata is visible offline; the document bodies are not bundled.

The Swift code compiled successfully on a hosted macOS runner in [build #1](https://github.com/nayanby/Cortex-IOS/actions/runs/40406193244), producing a simulator app artifact. The app has not been launched or visually tested. See [port status](docs/PORT-STATUS.md) for the remaining work.

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
