# Exact-copy port status

Target: preserve the Android consumer app's screens, labels, typography, library contents, study behavior, saved data, and access policy. Initial platform target: iOS/iPadOS 17 and later. The deployment target can change after device requirements are known.

## Implemented, awaiting runtime and visual checks

- SwiftUI app entry point and declarative XcodeGen project.
- Actual bundled catalog with stable IDs, storage paths, subject names, chapter ordering, headings, and study-tool availability flags.
- Subject → chapter → outline navigation.
- Search across chapter titles, subjects, and headings; empty and catalog failure states.
- Original Averia Serif Libre fonts, brand colors, blue card gradient, and original Deep Dive label.
- Unsigned simulator build workflow using a hosted macOS runner. [Build #1](https://github.com/nayanby/Cortex-IOS/actions/runs/40406193244) compiled commit `18e9b90` successfully and uploaded the simulator app on 27 October 2026 (India time). No launch or interaction testing has been performed.

Current UI starts at Deep Dive. It does not yet reproduce the Android home screen, authentication gate, drawer, or bottom navigation. The SF Symbols in the initial library are temporary; the Android illustrations need asset conversion. Neither functional nor pixel parity is claimed.

## Remaining implementation and acceptance criteria

| Area | Android reference | Required iOS behavior |
| --- | --- | --- |
| Authentication | `data/auth/AccessRepository.kt`, `screen_gate.xml` | Email/password, Google sign-in, profile registration/recovery, trial, device registration and live session policy; compare schema and transactions before enabling writes |
| Firebase registration | `FirebaseSetup.kt` | Register an Apple app in the same Firebase project; supply an iOS plist, App Check configuration and URL schemes; never reuse Android app credentials as iOS configuration |
| Home and navigation | `screen_home.xml`, `activity_main.xml`, menu resources | Match continue-reading, due work, Deep Dive, Snapshots, PDFs, notebooks, drawer, search and bottom tabs |
| Library sync | `FirebaseLibraryClient.kt`, `CatalogStore.kt`, `SyncRepository.kt` | Use `library/catalog/notes` and Storage `files/...`; lazy download, cache, progress, refresh, cancellation and offline recovery |
| Reader | generated `index.html`, `web/ManifestProvider.kt`, `web/ApiPathHandler.kt`, `assets/bridge.js` | Reuse DOCX layout/rendering; port `/api/library`, `/api/file`, poster storage, scrolling, table sizing, fonts, export and reader progress into WKWebView |
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
- Android describes a 60-day trial, two registered phones and one live session for non-beta accounts. Exact transaction behavior remains to be ported and tested; beta shortcuts must not become an iOS access bypass.
- Library listing uses case-insensitive path deduplication and natural chapter ordering. The initial bundled catalog has unique stable IDs and paths.

## Verification required before calling this a copy

Use equivalent test accounts on Android and iOS. Compare each screen at equivalent logical widths and text sizes, then run the same navigation, reading, search, annotation, study, import/export, offline and account scenarios. Confirm that data written on one platform can be read on the other. A successful cloud compilation alone does not establish any of these properties.

## External setup still needed

- GitHub remote to run the prepared macOS workflow.
- iOS Firebase app registration/configuration for the existing backend.
- Apple Developer membership, identifiers, signing and App Store Connect before TestFlight.
- A real or hosted Apple device environment for visual and interaction testing.
