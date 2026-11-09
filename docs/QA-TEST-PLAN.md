# QA test plan

This plan records every product requirement and reported bug that must be checked before a release.
A release is allowed only after every automated test case (TC) passes and every manual test scenario
(TS) has been executed on the named platform.

The release rule is in `CLAUDE.md`. The machine gate is:

```bash
./scripts/check.sh
QA_MANUAL_SIGNOFF=all ./scripts/qa-release.sh
```

`QA_MANUAL_SIGNOFF` is deliberately explicit. Do not set it until every TS below has passed. If only a
subset is relevant, set it to the completed IDs instead of `all`; the script rejects an incomplete list.

## Automated test cases

| ID | Requirement or reported bug | Automated check |
|---|---|---|
| TC-01 | No telemetry, analytics, cookies, feedback server or automatic updater | `scripts/tests/test_privacy_guard.py` |
| TC-02 | No privileged helper, kext, system extension, launch daemon or installer receipt | `scripts/tests/test_security_guard.py` |
| TC-03 | Every interface message has Italian and English text, and no Swift window bypasses the catalog | `scripts/tests/test_localization.py`, `Tests/CornettaCoreTests/LocalizationTests.swift` |
| TC-04 | English is the default when no language choice is saved; an explicit choice wins | `Tests/CornettaCoreTests/LocalizationTests.swift`, Windows selftest |
| TC-05 | The menu auto-transcription control uses its own observable storage and shows On/Off text | `scripts/tests/test_localization.py` |
| TC-06 | Transcription endpoint validation accepts OpenAI-compatible base URLs, rejects injected paths, credentials, queries and invalid ports. The optional API key is a Bearer token stored only in the Keychain | `Tests/CornettaCoreTests/TranscriptionConfigTests.swift`, `scripts/tests/test_security_guard.py` |
| TC-07 | Automatic transcription requires a fresh opt-in after the switch from Apple Speech to HTTP | `Tests/CornettaCoreTests/TranscriptionConfigTests.swift` |
| TC-08 | The update feed signature, release URL allowlist and version comparison are correct | `Tests/CornettaCoreTests/UpdateFeedSignatureTests.swift`, `scripts/tests/test_sign_feed.py`, `scripts/tests/test_update_feed.py` |
| TC-09 | A signed feed and the published asset hashes agree | `scripts/tests/test_update_feed.py`, `scripts/test_site.py` |
| TC-10 | The static site has no analytics, no visit counting and no download API | `scripts/tests/test_privacy_guard.py`, `scripts/test_site.py` |
| TC-11 | The Windows app has no transcription and defaults to English without a saved choice | Windows tests and `scripts/tests/test_localization.py` |
| TC-12 | The public history contains no private VVG email and no credential files | `scripts/tests/test_history_guard.py` |
| TC-13 | The macOS app bundles no speech model or telemetry, allows only local HTTP through ATS by default, and weak-links `Speech.framework` only for the optional macOS 26 Apple engine | `scripts/tests/test_security_guard.py`, release DMG inspection |
| TC-14 | Full macOS build, tests, universal DMG, .NET, Python and browser scenarios | `./scripts/check.sh` |
| TC-15 | Release metadata and assets are internally consistent | `scripts/qa-release.sh` |
| TC-16 | Call detection normalizes G-Space and Yandex Telemost helpers and ignores system microphone users | `Tests/CornettaCoreTests/CallDetectorTests.swift` |
| TC-17 | Multiple HTTP providers persist, switch and delete independently; the selected provider is remembered; Apple is a separate provider option | `Tests/CornettaCoreTests/TranscriptionProvidersTests.swift` |
| TC-18 | The five recording tags are read and written in the .m4a, empty tags can be removed, and the audio remains readable after the atomic replacement | `Tests/CornettaCoreTests/RecordingTagsTests.swift` |
| TC-19 | Floating recording, suggestion and notice panels size themselves to their SwiftUI content, including the Feedback button and long update messages | manual TS-19, release screenshots |

## Manual test scenarios

Execute the scenarios in order. Record the build identifier and the result for each scenario. A failure
blocks the release until it is fixed and all affected scenarios are repeated.

### TS-01: English is the default on a fresh install

1. Remove the saved `appLanguage` preference in a disposable user account or test container.
2. Launch the app on a non-English macOS.
3. Open the menu, Welcome, Recordings, Transcription settings, a recording notice and the screen
   recording panel.
4. Expected: every visible word is English. No Italian label appears in any window.

### TS-02: Complete Italian and English switching

1. Switch to Italiano from the menu.
2. Open every window and notice again.
3. Expected: every message is Italian, including menu items, library empty/detail/failure states,
   settings, welcome, alerts, overlays and screen recording controls.
4. Relaunch. Expected: Italiano is still selected.
5. Switch back to English and repeat the window sweep. Expected: no Italian text remains.

### TS-03: Auto-transcription menu state and persistence

1. Start with auto-transcription off.
2. Open the menu. Expected: the item reads `Transcribe immediately after recording: Off`.
3. Click it. Expected: the text changes to `On` and a checkmark appears.
4. Open Transcription settings. Expected: the switch is on.
5. Turn it off in settings and reopen the menu. Expected: the item reads `Off` and the checkmark is gone.
6. Turn it on, quit and relaunch. Expected: it is still on.
7. Repeat in Italian. Expected: `Attiva`/`Disattivata` and the same mark behavior.

### TS-04: Live transcription service

1. Paste the OpenAI-compatible base URL, for example `https://api.example.com/v1`, then the model
   and language. Press **Check service**: expected `Connection OK. Model ... is available.`
   No audio may be sent by this check.
2. Transcribe a short synthetic recording with known speech.
3. Expected: the transcript contains the spoken words and the service receives one multipart request.
   With a paid provider, paste the API key, press Save, and confirm the request carries
   `Authorization: Bearer` without the key appearing in the app log.
4. Configure two-track audio (`tu.m4a`, `altri.m4a`) and transcribe again.
5. Expected: two requests are sent and the transcript labels `You`/`Tu` and `Others`/`Altri`.

### TS-05: Service failure remains contained

1. Stop the transcription service or point the app at a closed port.
2. Press Transcribe on an existing recording.
3. Expected: the library shows a failed state in the selected language, offers Try again and
   Transcription settings, and the audio file is unchanged.
4. Start the service and press Try again. Expected: transcription succeeds.

### TS-06: No background network traffic

1. Launch the app and leave it idle for at least ten minutes without opening the update check or a
   transcription.
2. Observe the process with `nettop`, Little Snitch or an equivalent local monitor.
3. Expected: no transcription or update request. No connection to a remote host.
4. Open the menu and settings. Expected: still no network request.

### TS-07: Remote plain HTTP is blocked, local HTTP works

1. Configure a local HTTP service on loopback or the local network. Transcribe synthetic audio.
2. Expected: request succeeds.
3. Configure a public hostname over plain HTTP.
4. Expected: the system blocks the request through App Transport Security. No audio is delivered.
5. Use HTTPS for a reachable trusted remote service. Expected: request succeeds.

### TS-08: Signed update feed rejects tampering

1. Open Check for updates with the live signed feed. Expected: the current version is recognized.
2. In a disposable copy, change one byte in `feed.json` while keeping the signature.
3. Expected: the app reports no valid update and never opens the release page.
4. Restore the signed feed. Expected: the check works again.

### TS-09: Library states and actions

1. Check the empty library, no selection, no results, queued, transcribing, failed, no speech and
   not-yet-transcribed states.
2. Check Copy, Export, Show in Finder, Delete, confirmation dialog, Try again and Transcription
   settings.
3. Expected: every label, message, dialog and tooltip is in the selected language. Delete moves audio
   and Markdown to the Trash and removes internal tracks and JSON.

### TS-10: Settings window layout and validation

1. Open Transcription settings.
2. Check the provider picker, Add provider button, name, base URL, model, language, API key,
   endpoint preview, automatic toggle, privacy note, Check service, Delete provider and Save.
3. Enter an empty URL, an `ftp://` URL, a URL with `?`, and a URL with credentials.
4. Expected: the preview turns red and the invalid message appears. A new provider starts from
   `http://127.0.0.1:8080/v1` and can be saved with a name.
5. Confirm the window is readable at the default size and every control has an accessibility label.

### TS-11: Welcome, permission and notice screens

1. Open the first-run Welcome window. Check both permissions, instructions, login toggle and Start.
2. Trigger the call-ended suggestion, stopped recording, recovery, update, transcription-ready and
   error notices.
3. Expected: every message is in the selected language, every panel has a non-zero size, no text is
   clipped, and the primary/secondary buttons match.

### TS-12: Screen recording controls

1. Open the screen recording submenu and panel.
2. Check microphone, Mac audio, overlay, folder and stop controls.
3. Expected: all labels and help text are in the selected language.

### TS-13: Windows package and language

1. Run the Windows CI for the release version.
2. Expected: build, tests, selftest, poisoned selftest, panel rendering, tray smoke and silent
   per-user installation pass.
3. Launch on a Windows machine with no saved language. Expected: English interface.
4. Confirm the Windows app has no transcription entry and does not send recordings anywhere.

### TS-14: macOS release package

1. Run `VERSION=<version> ./scripts/check.sh`.
2. Mount the DMG. Expected: bundle identifier `com.stellakamikaze.cornetta`, correct version,
   `arm64` and `x86_64`, valid signature, both localization files, and `Speech.framework` present as a
   weak (optional) link for the macOS 26 Apple engine.
3. Confirm the app runs on Intel macOS 15 with no privileged helper, kext, system extension, launch
   agent, package receipt or leftover aggregate device.

### TS-15: Public privacy and site boundary

1. Open the Italian and English home pages and privacy pages.
2. Expected: the pages say that recordings stay on the computer, HTTP audio goes only to the selected
   provider when the user starts a transcription, Apple Speech stays on the Mac, and no analytics or
   cookies exist.
3. Check that the site CSP still forbids connections and that `llms.txt` matches the same boundary.

### TS-16: History and credential hygiene

1. Run `git log --format='%ae <%ae>'` over every branch and tag.
2. Expected: the VVG-web commits use `VVG-web@users.noreply.github.com`. No address on the private
   `gnivc.ru` domain remains. Upstream authors keep their original attribution.
3. Search the tree for `.env`, `*.pem`, API keys and private keys. Expected: none tracked.
4. Confirm the update-feed private key is outside the repository and mode `600`.

### TS-17: Provider selector, multiple HTTP providers and Apple option

1. Open Transcription settings. Add a second HTTP provider with a name, base URL, model, language and
   key. Expected: it appears in the provider picker and is selected.
2. Switch between the two HTTP providers. Expected: each keeps its own URL, model, language and key;
   Check service uses the selected provider's draft values.
3. Transcribe a test recording with each provider. Expected: the transcript metadata names the selected
   engine and the request goes only to that provider.
4. Delete one provider. Expected: it disappears from the picker, the other remains selected, its key is
   removed, and recordings are untouched.
5. Select Apple Speech. On macOS 26 expected: native transcription works locally; macOS may download the
   language asset once, but Cornetta sends no audio. On macOS 15 expected: the warning appears and no HTTP
   request is made.
6. Record the macOS version used for this scenario. The macOS 26 native path must be reported separately
   when the release host is older; a missing host is a written release exception, not an unrecorded skip.

### TS-18: Recording audio tags

1. Open a disposable recording in **Recordings and transcripts**, press the tag button, and set Title,
   Artist / author, Album / project, Date and Comment / topic.
2. Save and reopen the editor. Expected: all five values are present. Check the file with an audio metadata
   reader; the fields must be in the .m4a, not only in Cornetta preferences.
3. Expected: the custom Title replaces the generated call date in the list and detail header, and the
   other tag values appear in the detail summary. Search for the Artist, Album, Date and Comment text.
4. Edit the key fields, clear all five, save, and reopen. Expected: the tags are gone, the audio still
   plays, and a transcript Markdown file is regenerated with the new title when it exists.
5. Cancel an edit. Expected: the file and the cached tags are unchanged.

### TS-19: Floating panel sizes

1. Run `--demo` with old autosaved panel frames and inspect the recording overlay, call-ended suggestion
   and update notice.
2. Expected: each panel fits its content at every detail level. The Feedback button is fully visible, the
   level labels do not wrap, and no text is clipped at the left, right, top or bottom edge.
3. Trigger a notice with a long message and a call suggestion at the same time. Expected: both windows grow
   to fit and remain inside the screen.
4. Quit and relaunch the app. Expected: the old saved frame is replaced by the content-sized frame.

## Sign-off

Record the release version, source commit and result for every TC and TS in the release checklist. The
release is blocked if any item is failed, skipped without a written reason, or not executed on the
required platform.
