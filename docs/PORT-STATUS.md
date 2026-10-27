# Exact-copy port status

Target: preserve the Android consumer app's screens, labels, typography, library contents, study behavior, saved data, and access policy. Initial platform target: iOS/iPadOS 17 and later. The deployment target can change after device requirements are known.

## Implemented, with initial reader runtime checks passing

- SwiftUI app entry point and declarative XcodeGen project.
- Actual bundled catalog with stable IDs, storage paths, subject names, chapter ordering, headings, and study-tool availability flags.
- Subject → chapter → outline navigation.
- Search across chapter titles, subjects, and headings; empty and catalog failure states.
- Original Averia Serif Libre fonts, brand colors, blue card gradient, and original Deep Dive label.
- Personal DOCX import with durable local storage, removal, sharing, and a 32 MB input limit.
- Bundled Android DOCX renderer, OMML formula patch, styles, typography helpers, JSZip and sixteen original font faces inside a native WKWebView host.
- Reader heading navigation and persistent fractional scroll position.
- Firebase Apple app registration completed after user approval; verified active via Firebase CLI. Actual iOS configuration retrieved locally and excluded from Git. Google sign-in, profile access, trial policy and shared catalog/download code are implemented; integration validation is in progress.
- [Firebase setup build](https://github.com/nayanby/Cortex-IOS/actions/runs/40411806905) compiled commit `b3c6f9f` successfully and passed the reader and Firebase configuration-validation simulator tests. This cloud run omits the local live plist, so it verifies SDK integration and offline behavior rather than live backend access.
- Simulator integration tests for real WebKit rendering, escaping, tables, formulas, font loading, reading position and local document persistence/deletion.
- Unsigned simulator build workflow using a hosted macOS runner. [Build #6](https://github.com/nayanby/Cortex-IOS/actions/runs/40408756211) compiled commit `de16dc4`, passed both reader integration tests and uploaded the simulator app on 27 October 2026 (India time). Test products use the documented iOS 18.4 deployment-target workaround for the runner's iOS 18.5 WebKit runtime issue. The ordinary app build still targets iOS 17; that OS version has not been runtime tested.

Configured builds start at the Google authentication gate, then open Home. Debug builds without Firebase configuration open an offline Home preview directly. The Android home layout, header, drawer, floating bottom navigation, menu gradients and original artwork now have an initial native port; subject illustrations and chapter cards use the original assets and dimensions. Study, PDF and notebook actions still identify themselves as unfinished. Recent-reading data and full reader chrome remain incomplete. Neither functional nor pixel parity is claimed.

## Remaining implementation and acceptance criteria

| Area | Android reference | Required iOS behavior |
| --- | --- | --- |
| Authentication | `data/auth/AccessRepository.kt`, `screen_gate.xml` | Google gate, restoration, sign-out, Keychain profile cache and atomic 60-day trial implemented; demo emulator integration passed in run 40422568453. Current Android hides email/password controls and disables device/session restrictions. Live OAuth acceptance testing remains |
| Firebase registration | `FirebaseSetup.kt` | Apple app registered, local plist retrieved, Auth/Firestore/Storage/App Check SDKs and generated Google callback scheme wired. Remaining: private cloud-build config, production App Check registration and live account testing |
| Home and navigation | `screen_home.xml`, `activity_main.xml`, menu resources | Initial home, drawer, custom header/search and bottom pill ported with original artwork; visual acceptance and functional study/PDF/notebook screens remain |
| Library sync | `FirebaseLibraryClient.kt`, `CatalogStore.kt`, `SyncRepository.kt` | Shared catalog refresh, Android path deduplication, Storage lazy download, progress, cancellation and 24-hour/ETag cache implemented; demo emulator integration passed in run 40422568453. Live shared-note acceptance remains |
| Reader | generated `index.html`, `web/ManifestProvider.kt`, `web/ApiPathHandler.kt`, `assets/bridge.js` | Core DOCX rendering, formulas, fonts, headings and scroll restoration ported; shared download now routes into the same reader. Remaining: Android toolbar controls, poster scope, export quotas/formatting, and visual parity checks |
| Reader/native bridge | `assets/bridge.js`, `MainActivity.kt` | Replace synchronous `AndroidBridge` calls with explicit asynchronous WebKit messages and JavaScript state caching; audit every bridge method and reject untrusted navigation |
| Ink and annotations | `ui/InkCanvas.kt`, `ui/InkStore.kt` | Pen/highlighter, eraser, undo/redo, zoom coordinates, storage and sharing; check Apple Pencil behavior on iPad |
| Snapshots | `web/PosterStore.kt`, `ui/PosterHtml.kt` | Shared/personal snapshots, scope keys, outline association, printing and export |
| Flashcards | `ui/FlashcardPanel.kt`, database entities | Existing pack schema, solve events, revision scheduling, due counts, persistence and sync |
| Qbank | native quiz screens and saved quiz entities | Existing bank parsing, revision state, scoring, history and restore |
| AI tools | `data/ai/FirebaseStudyAi.kt`, `ui/AiScreens.kt` | Existing Firebase AI integration, prompts, access/usage rules and generated-content persistence |
| Audio | `data/ai/CloudTts.kt`, `AudiobookPlayer.kt` | Existing TTS contract, playback position, interruptions, background playback and speed |
| PDFs and notebooks | `ui/PaperScreens.kt`, `PdfEngine.kt`, `NotebookPdf.kt` | Import/export, page rendering, ink layers, ruled/blank paper, persistent notebooks |
| Personal data | `FirebaseUserDataStore.kt` | Preserve per-user paths and serialization; verify cross-platform round trips before writes |
| Settings and feedback | native dialogs and preference classes | Match settings, help, storage controls and feedback behavior |
| Distribution | hosted macOS build | Successful simulator build, iPhone/iPad testing, signed device archive, TestFlight and final App Store assets |

## Backend observations

- The consumer library uses Firestore and Firebase Storage. OneDrive master upload code remains in the Android source but is not the consumer's primary content path.
- Notes are indexed in `library/catalog/notes/{id}`; shared snapshots in `library/catalog/snapshots/{id}`.
- Android profile records use `users/{email}`. The iOS port must preserve normalization and entitlement rules. Firebase sign-in alone does not establish consumer access.
- Current Android `AccessRepository.kt` has `DEVICE_RESTRICTIONS_ENABLED = false`: no device-cap or live-session fields should be written by iOS. A first eligible sign-in starts a 60-day trial atomically. Signed-in free accounts retain note reading; full/trial/beta access gates metadata refresh and study tools. The actual visible Android gate is Google-only. Older comments and hidden strings describing two phones or a 40-day trial are stale.
- Library listing uses case-insensitive path deduplication and natural chapter ordering. The initial bundled catalog has unique stable IDs and paths.

## Verification required before calling this a copy

Use equivalent test accounts on Android and iOS. Compare each screen at equivalent logical widths and text sizes, then run the same navigation, reading, search, annotation, study, import/export, offline and account scenarios. Confirm that data written on one platform can be read on the other. A successful cloud compilation alone does not establish any of these properties.

## External setup still needed

- GitHub remote and hosted macOS workflow are configured and running.
- iOS app `Cortex Consumer iOS` is registered and its configuration is present locally. Cloud builds still need that config supplied privately to initialize Firebase; the current workflow deliberately supports offline builds without it.
- Apple Developer membership, identifiers, signing and App Store Connect before TestFlight.
- A real or hosted Apple device environment for visual and interaction testing.

## Windows browser preview

The user's Appetize account has a CORTEX simulator app. The initial offline build was uploaded and launched on an iPhone 14 Pro with iOS 26.0 from Windows. It is an incomplete port, not a completed copy. Appetize's iOS media-upload control does not support DOCX, so that control cannot populate the Files picker for personal imports.

`scripts/package-appetize.py` wraps the downloaded simulator artifact with its required `Cortex.app/` root and executable permissions. With `--notes-dir`, it can include explicitly supplied local DOCX files and a Debug-only `preview-library.json` mapping. Such files stay in ignored build output and outside Git. `PreviewLibrary` never fetches server content or grants anonymous Firebase access. The normal shared-note reader still requires an authenticated profile. The user explicitly approved private configuration transfer to GitHub/Appetize; `FIREBASE_IOS_CONFIG_PLIST` was saved as an encrypted GitHub Actions secret on 27 October 2026 (India time). A configured, locally signed browser build from commit `675ecf5` was validated and uploaded, but Appetize returned a generic session-launch error. Its live Google sign-in is unverified. The user selected physical iPad testing instead. The actual cardiology DOCX retrieved for a possible offline preview remains only in ignored local build output; it has not been bundled into an uploaded app.

## Physical iPad testing from Windows

The workflow now builds a separate unsigned `iphoneos` IPA with a `Payload/Cortex.app` root for local Apple-account signing. Run 40422791574 produced the device artifact at commit `f35a88a`; its archive, physical-iOS Mach-O platform, iPad device family and Firebase/Google callback configuration were independently validated after download. The simulator ZIP cannot install on an iPad. Sideloadly 0.71.1 was installed from its official vendor after explicit action-time approval. Device installation, signing and live Google sign-in remain pending; no Apple account credentials were requested in chat or handled by the agent.
