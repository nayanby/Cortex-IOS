# Port status

The user requested a matching iOS Consumer app, then explicitly requested a private offline test build using the Windows library and personal Gemini API settings. The offline build does not require sign-in to read its bundled files. Full Android parity is not claimed.

## Implemented source

| Area | Current behavior |
| --- | --- |
| Catalog | Private catalog generated from actual local DOCX/DOTX files, Roman chapter ordering, headings, stable path identifiers, bundled-file resolution; local catalog takes priority |
| Reader | Android renderer/styles/fonts, images/tables/OMML, persistent position, outline, font/line/paragraph controls, quote-validated highlights, bookmarks |
| Snapshots | Subject/chapter/heading navigation, original Consumer CSS and safe HTML renderer, font controls, drawing and paginated PDF sharing |
| Flashcards | Consumer subject/topic fields and tick pickers, due/document-order sessions, full-height review card, answer reveal, canonical per-card ratings and persistence |
| Qbank | Existing local sets, explanations, unscored missing-answer states, saved attempts and completed-quiz history |
| AI | Direct Gemini API with a user-entered Keychain key, editable model, structured/validated Notes/Snapshots/Flashcards/Qbank, cancellation and quota/network errors, local persistence |
| Paper | PDF import, blank/ruled notebooks, coalesced uniform-width pen input, vector annotations and exports, multiplied wash, original controls, drawing persistence and note-to-PDF copies |
| Audio | Native iPad speech, paragraph position, speed and interruptions; different from Android cloud TTS |
| Navigation | Main-screen study/paper/Create routes, original home artwork/header/cards/drawer/pill, Snapshot hierarchy, settings/help/storage/performance and recents |
| Optional Firebase | Registered standard/sideload clients, strict configuration validation, Google account flow and authenticated online downloads; no production rule changes |

## Local import

142 Word packages (including one template), 3,112 headings, 549 Snapshots, 458 flashcard decks, 439 unique Qbank sets. All original study files are copied privately; duplicate display records are collapsed. Two empty flashcard files are reported; two unique Qbank questions lacking valid answer keys remain readable and unscored.

The private content lives only under ignored `build/OfflineLibrary` and in a locally enriched unsigned IPA. It must be added before device signing. Raw study files use short hashed paths and an original-path manifest so Windows signing stays below its path limit. Cloud/public build artifacts contain no user-supplied document or study payloads.

## Required acceptance and remaining parity

- Physical iPad visual/interaction acceptance of notes, font controls, study navigation, notebook drawing/export and audio. The latest 21 automated tests passed.
- Enter a personal Gemini key in the app and validate an actual generation request; automated tests use a fake transport and no real key.
- Android/iOS screenshots and interactions at equivalent widths; complete visual parity is still unverified.
- Cloud study sync, complete revision-state parity and cross-platform state migration. The local interval progression and Again requeue behavior now follow the Android implementation.
- Exact Android slide layout, cloud TTS/audiobook behavior and media-control parity. Native AI slide creation/navigation/PDF export are implemented.
- Full Android annotation anchors, movable notebook image layers, export quotas/formats and shared/personal data round trips. Native PDF writing copies do not modify the source DOCX.
- Distribution signing and TestFlight/App Store setup. The original CORTEX app icon is now configured for iPhone/iPad.

Imported notes must be preserved by replacing the existing installation using the same sideload identity. Do not uninstall the existing app during update testing.

## Validation history

Run [40422791574](https://github.com/nayanby/Cortex-IOS/actions/runs/40422791574) successfully built the earlier physical-device IPA and passed its 11 tests. That installation was opened on the user's iPad, but its online notes were unavailable because the signer changed the bundle identifier. The current workflow uses a matching registered sideload client. Offline bundles independently permit local-file testing without an account.

Run [40488001731](https://github.com/nayanby/Cortex-IOS/actions/runs/40488001731) passed both device/simulator compilation and all 21 automated tests. Checks include Consumer Snapshot colours, nested lists/tables, escaped text, PDF export, exact pen palette and PDF markup-mode routing, in addition to the account/reader/study tests. The tested source differs from the installed app code only in the PencilKit floating-point assertion tolerance.

The user confirmed manual installation of `Cortex-iPad-Offline-Updated.ipa` through iPASide. Both previously imported Word files were verified byte-for-byte against their local backups after the update. The final private package contains all 142 Word packages and 1,207 original study files, has the original CORTEX app icon, and limits its longest internal path to 128 characters. Main sections now use navigation destinations; Snapshot browsing follows subject → chapter → heading and uses the original Consumer stylesheet with safe structured rendering. Physical visual review is ongoing; complete parity and live OAuth/AI acceptance are not claimed.


The study-selection update at `fe2e4cc` adds subject → chapter → heading cards and multiple selection for Flashcards/Qbank, canonical flashcard review identities across combined decks, and a one-question Qbank flow with a saved position. Notes and Snapshots now change font size in 1 pt increments. The device and simulator builds and integration-test step passed in [run 40493241405](https://github.com/nayanby/Cortex-IOS/actions/runs/40493241405). The private `Cortex-iPad-Offline-Study.ipa` was verified against all 142 source Word packages and 1,207 original study files, with AppIcon present and a longest internal path of 128 characters. Installation and physical visual acceptance of this update remain pending.


The Consumer UI/ink update at `e2f61d5` passed simulator and device compilation, the integration-test step, and rendered-screen export in [run 40719789320](https://github.com/nayanby/Cortex-IOS/actions/runs/40719789320). Home, study panels, subject/topic tick pickers, review cards, Create and paper libraries use the Consumer layout measurements and original artwork. Phone (390 pt) and iPad (744 pt) render captures were inspected. Snapshot washes use an SVG multiply layer; PDF/notebook annotations and exports use vector paths with a once-composited multiply wash. Pen samples are coalesced and uniform-width, and underliners stay horizontal. Tests verify black text under repeated wash strokes, preservation of erased ranges, horizontal geometry and clear/undo/redo. Existing drawing storage stays in PKDrawing format. Physical Apple Pencil feel and complete screen-by-screen parity remain subject to iPad acceptance.

The private replacement is `Cortex-iPad-Consumer-UI.ipa` (SHA-256 `33197347f8746605ffb4cf392740f92e97a4e55719068d9b9357a496ddc5dc42`). All 142 Word packages and 1,207 original study files were checked byte-for-byte; the original icon and sideload identifier are retained, and the longest internal path is 128 characters. Packaging skips Word temporary lock files (`~$...docx`), with a regression fixture. No installation of this update has been claimed.


The iPad crash reports retrieved on 30 October show a main-thread SwiftUI `NavigationColumnState.boundPathChange` assertion. Deep Dive previously created a nested NavigationStack under the root’s bound path; the fix makes it inherit the main stack. A regression host repeatedly opens and returns from Deep Dive using the same bound-path structure. The original device reports remain in ignored local diagnostics.

The subject/topic selector is now a larger centered popup. Picking a subject immediately advances to its topics, with Back to subjects and Done/Use selection controls. Notes and Snapshots share top Aa/pen/highlighter/underliner/cursor/overflow controls. Notes place Snapshots at the bottom left and Outline at the bottom right; Snapshots place Deep Dive at the bottom right. Notes now store direct pen strokes privately in ReaderInk using the existing PKDrawing/vector rendering contract. Existing bookmarks, text highlights and paper-copy annotations are retained.


Both device/simulator compilation and the integration-test step passed for `a5c9cef` in [run 40939444696](https://github.com/nayanby/Cortex-IOS/actions/runs/40939444696). The regression confirmed three Deep Dive open/return cycles and successful reopening of saved blended ink in Notes. Rendered large-popup and viewer-control captures were inspected. Physical iPad acceptance remains pending.

The replacement is `Cortex-iPad-Navigation-Fix-Complete.ipa`, SHA-256 `defb491e648d321f8c5e3a4b94956678aae2b349b4e2a5b1d75c5f03854b79ce`. It preserves 142 Word packages, 3,112 headings and all 1,207 original study files. The Windows source now has 136 Word packages; six missing paths were retained byte-for-byte from the previously verified offline package rather than removed during this UI fix. The original app icon and sideload identity are unchanged; the longest internal path remains 128 characters. The iPad crash reports were read successfully; a later backup attempt found no connected device, so no new import backup was claimed. Earlier private backups remain available.


The writing/Qbank update adds a directly visible eraser immediately after the highlighter in both inline and paper toolbars. New pen and wash input uses a speed-adaptive jitter filter, with bounded tip displacement and an exact final endpoint. Existing stored strokes are not rewritten; straight underlining and erasing bypass the filter.

Qbank topic selection includes 10, 20, 30, 50 or all questions. Limits apply to combined selections and individual saved Qbanks, with separate attempt identities for shortened sessions. Subject/topic/count choices persist so reopening a paused session uses the same scope. Back from an unfinished quiz offers Pause, Exit without saving and Continue solving; Pause stores the current question, checked answers and pending selection, while discard removes only that attempt and retains completed history. The active quiz blocks edge-swipe navigation so the confirmation cannot be bypassed by that gesture.


The app source is `1f8f3a9`. [Run 40944713711](https://github.com/nayanby/Cortex-IOS/actions/runs/40944713711) at `0dc5b93` passed simulator/device builds and the integration-test step; its only difference is simplified construction of a synthetic smoothing fixture that the Swift compiler previously could not type-check. Checks cover jitter reduction, bounded tip displacement, endpoints, question limits, pause/pending-answer persistence, discard/history retention, and the existing navigation/reader/paper checks. Rendered eraser placement and all five question-count buttons were inspected. Physical writing feel remains pending iPad acceptance.

The private replacement is `Cortex-iPad-Smooth-Qbank.ipa`, SHA-256 `e69ca5ad78d4034897437e06bc164f6863fa627175133d6eb0ac1390d9aea1fd`. It preserves 142 Word packages (six retained from the previous verified bundle), 1,207 original study files, the original icon and sideload bundle identity. ZIP integrity and file bytes were checked; the longest internal path remains 128 characters. Installation has not been claimed.
