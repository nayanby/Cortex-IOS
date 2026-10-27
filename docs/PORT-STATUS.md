# Port status

The user requested a matching iOS Consumer app, then explicitly requested a private offline test build using the Windows library and personal Gemini API settings. The offline build does not require sign-in to read its bundled files. Full Android parity is not claimed.

## Implemented source

| Area | Current behavior |
| --- | --- |
| Catalog | Private catalog generated from actual local DOCX/DOTX files, Roman chapter ordering, headings, stable path identifiers, bundled-file resolution; local catalog takes priority |
| Reader | Android renderer/styles/fonts, images/tables/OMML, persistent position, outline, font/line/paragraph controls, quote-validated highlights, bookmarks |
| Snapshots | Subject/chapter/heading navigation, original Consumer CSS and safe HTML renderer, font controls, drawing and paginated PDF sharing |
| Flashcards | Existing local decks, answer reveal, rating, local schedule and persistence |
| Qbank | Existing local sets, explanations, unscored missing-answer states, saved attempts and completed-quiz history |
| AI | Direct Gemini API with a user-entered Keychain key, editable model, structured/validated Notes/Snapshots/Flashcards/Qbank, cancellation and quota/network errors, local persistence |
| Paper | PDF import, blank/ruled notebooks, pages, PencilKit tools, mark persistence, PDF export and note-to-PDF writing copies |
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
