# CORTEX for iOS

Native iPhone/iPad port of Cortex Consumer, targeting iOS 17 and later. The Android design is the reference; complete visual and behavioral parity has not been established.

## Offline test build

The user-supplied Windows library can be packaged privately into the unsigned device IPA. When this bundle is present, the app uses its local catalog before cached online catalogs and opens without sign-in. Production Firebase rules and permissions are unchanged.

The current local import contains 141 DOCX notes and one Word template, 3,112 headings, 549 Snapshots, 458 flashcard decks (12,075 cards), and 439 unique Qbank sets (6,335 questions). Duplicate records are removed from the displayed catalog. Original study files are retained under short hashed filenames, with their original paths recorded in `source-files.json`, including two empty flashcard files reported in `import-warnings.json`. Two unique questions have no valid answer key and are excluded from scoring.

Personal documents, study content, Firebase configuration and API keys are excluded from Git. The public repository contains source, artwork, the original metadata catalog and synthetic tests.

```sh
python3 scripts/package-offline.py --source "PATH/TO/Cortex Windows/data" \
  --ipa device-package/Cortex-iPad-Unsigned.ipa \
  --output-ipa device-package/Cortex-iPad-Offline.ipa
```

Run this after downloading the latest device artifact. Injecting resources must happen before iPASide signs the IPA. Install the replacement using the same Apple account and bundle identifier; do not uninstall the existing app if its imported documents must be retained. A simulator app cannot be installed on an iPad.

## Features

- Original CORTEX app icon for iPhone and iPad.
- Local catalog, subject/chapter navigation, heading search, Word imports and original Android DOCX rendering with tables, formulas and embedded images.
- Notes/Snapshots use Consumer’s top Aa and marking tools, with floating Snapshot/Outline/Deep Dive buttons. Direct note pen strokes persist locally. Font controls change by exactly 1 pt per step. Reader line spacing, paragraph spacing, outline, bookmarks, text highlights, and saved reading position.
- Primary sections open in the main navigation stack with the Consumer header and floating navigation pill. Home category order, subject/topic tick pickers, study panels, flashcard review card, Create form and paper libraries follow the original Consumer layouts. Snapshots retain the Consumer HTML/CSS and bundled fonts.
- Snapshot/PDF/notebook drawing uses coalesced stylus samples, adaptive stroke smoothing, uniform widths, a horizontal underliner, an eraser beside the highlighter, original pen artwork, and compact colour/width controls. Snapshot SVG ink and PDF vector annotations multiply the wash layer into the page; black text stays dark and overlapping strokes keep the same pastel. Existing PencilKit drawing files remain readable, including erased ranges.
- Flashcards and Qbank browse by subject, chapter and heading, with multiple selections and combined study sessions. Flashcard ratings retain each original card's review history. Qbank offers 10/20/30/50/all questions, one question at a time, answer checks, explanations, saved position, scoring and history. Leaving an unfinished quiz offers Pause, Exit without saving or Continue solving.
- Create with AI for Notes, Snapshots, Flashcards and Qbank, from a topic, pasted source or selected/open note text. Generated content is validated and saved locally.
- Sidebar AI settings for a personal Google Gemini key and model. Keys use device-only Keychain storage and the API-key header; they are never written to bundled resources or source control. Generation sends only explicitly submitted text directly to Google, requires internet and uses the user's quota. The default model matches the current Android source, `gemini-3.8-flash`.
- PDF import, blank/8 mm ruled notebooks, additional notebook pages, PencilKit pen/highlighter/eraser, undo/redo, persistent marks and annotated PDF export. A note can be copied to PDF for handwriting.
- AI-created slide decks with page navigation and PDF export; long sections flow across continuation pages. Notebook images can be added as an image page.
- Built-in iPad read-aloud with paragraph navigation, pause/resume, speed, saved position and audio-interruption handling. This uses Apple's voice rather than the Android cloud TTS backend.
- Home reading/Snapshot recents, local storage information, and in-app help.

These native implementations still require real-iPad interaction and visual acceptance. Android cloud study sync, full revision-state parity, cloud audiobook behavior, export quotas and all cross-platform saved-data round trips are not complete. See [port status](docs/PORT-STATUS.md).

## Cloud builds and tests

GitHub Actions builds simulator and physical-device apps on a hosted Mac, then runs XCTest against synthetic documents and localhost Firebase emulators. Tests cover account/trial/cache behavior, document rendering, typography changes, highlights, study parsing/validation, stubbed Gemini transport, local study persistence and pen marks in exported PDFs. Packaging has a separate Python regression test. No production credentials or real Gemini calls are used by these tests.

```sh
python3 scripts/test-package-offline.py
node scripts/validate-catalog.cjs
python3 scripts/prepare-firebase.py
xcodegen generate
```

The first two commands run on Windows. Xcode compilation requires macOS and is performed by the workflow. Normal apps target iOS 17; the separate hosted simulator test build uses iOS 18.4 to avoid the runner's documented WebKit runtime issue.

## Optional online account mode

A standard Firebase Apple client and a separate client matching the Windows sideload identifier are registered. Their configurations are supplied through private GitHub Actions secrets. The workflow selects the device client only for the device build and restores the standard client before simulator tests. Configuration is validated against both project and actual built bundle identifier.

Without a local content bundle, authenticated online browsing uses Google sign-in, atomic first-login trial creation, Keychain profile caching and authenticated/cancellable shared-note downloads. Live OAuth acceptance remains separate from emulator validation. See [Firebase setup](docs/FIREBASE-IOS-SETUP.md).

TestFlight/App Store distribution still requires Apple membership and signing setup. No Apple account credentials or distribution certificates are stored in this repository.

## References

Android source: `../Cortex Consumer 2`, currently audited at 1.0.23 for access policy and AI model. Extracted reader assets retain their recorded provenance in `Reference/`.

- [Gemini structured output](https://ai.google.dev/gemini-api/docs/generate-content/structured-output)
- [Gemini generateContent API](https://ai.google.dev/api/generate-content)
- [Apple PDF page overlays](https://developer.apple.com/documentation/pdfkit/pdfpageoverlayviewprovider)
