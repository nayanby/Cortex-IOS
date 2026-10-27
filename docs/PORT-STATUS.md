# Port status

The user requested a matching iOS Consumer app, then explicitly requested a private offline test build using the Windows library and personal Gemini API settings. The offline build does not require sign-in to read its bundled files. Full Android parity is not claimed.

## Implemented source

| Area | Current behavior |
| --- | --- |
| Catalog | Private catalog generated from actual local DOCX/DOTX files, Roman chapter ordering, headings, stable path identifiers, bundled-file resolution; local catalog takes priority |
| Reader | Android renderer/styles/fonts, images/tables/OMML, persistent position, outline, font/line/paragraph controls, quote-validated highlights, bookmarks |
| Snapshots | Existing local payloads, chapter matching, sections/groups/points/numbering/tables, search and font controls |
| Flashcards | Existing local decks, answer reveal, rating, local schedule and persistence |
| Qbank | Existing local sets, explanations, unscored missing-answer states, saved attempts and completed-quiz history |
| AI | Direct Gemini API with a user-entered Keychain key, editable model, structured/validated Notes/Snapshots/Flashcards/Qbank, cancellation and quota/network errors, local persistence |
| Paper | PDF import, blank/ruled notebooks, pages, PencilKit tools, mark persistence, PDF export and note-to-PDF writing copies |
| Audio | Native iPad speech, paragraph position, speed and interruptions; different from Android cloud TTS |
| Navigation | Original home artwork/header/cards/drawer/pill, working study/paper/settings/help/storage/performance routes and recents |
| Optional Firebase | Registered standard/sideload clients, strict configuration validation, Google account flow and authenticated online downloads; no production rule changes |

## Local import

142 Word packages (including one template), 3,112 headings, 549 Snapshots, 458 flashcard decks, 439 unique Qbank sets. All original study files are copied privately; duplicate display records are collapsed. Two empty flashcard files are reported; two unique Qbank questions lacking valid answer keys remain readable and unscored.

The private content lives only under ignored `build/OfflineLibrary` and in a locally enriched unsigned IPA. It must be added before device signing. Cloud/public build artifacts contain no user-supplied document or study payloads.

## Required acceptance and remaining parity

- Compile and XCTest verification of the latest source, followed by physical iPad checks of notes, font controls, study navigation, notebook drawing/export and audio.
- Enter a personal Gemini key in the app and validate an actual generation request; automated tests use a fake transport and no real key.
- Android/iOS screenshots and interactions at equivalent widths; complete visual parity is still unverified.
- Cloud study sync, complete revision-state parity and cross-platform state migration. The local interval progression and Again requeue behavior now follow the Android implementation.
- Exact Android slide layout, cloud TTS/audiobook behavior and media-control parity. Native AI slide creation/navigation/PDF export are implemented.
- Full Android annotation anchors, movable notebook image layers, export quotas/formats and shared/personal data round trips. Native PDF writing copies do not modify the source DOCX.
- App icon assets, distribution signing, TestFlight/App Store setup.

Imported notes must be preserved by replacing the existing installation using the same sideload identity. Do not uninstall the existing app during update testing.

## Validation history

Run [40422791574](https://github.com/nayanby/Cortex-IOS/actions/runs/40422791574) successfully built the earlier physical-device IPA and passed its 11 tests. That installation was opened on the user's iPad, but its online notes were unavailable because the signer changed the bundle identifier. The current workflow uses a matching registered sideload client. Offline bundles independently permit local-file testing without an account.

Latest feature validation is in progress; compilation is not equivalent to complete parity or live OAuth/AI acceptance.
