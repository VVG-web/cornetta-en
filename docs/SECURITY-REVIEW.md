# macOS Intel security review

## Scope

This review covers the native macOS app in `Sources/` and the DMG installation path. It checks:

- privilege escalation and privileged helpers;
- kernel extensions, DriverKit and system extensions;
- launch daemons, launch agents and login items;
- audio-driver installation and default-device changes;
- filesystem writes and installer receipts;
- resource cleanup after recording;
- architecture and minimum-version guards;
- safe removal of the app.

It does not cover the Windows build, third-party apps already installed on the Mac, or the macOS
kernel itself.

## Tested machine

- MacBook Pro `MacBookPro16,2`, Intel Core i5-1038NG7, 16 GB RAM, `x86_64`
- macOS 15.8.1, build `24H32`
- System Integrity Protection enabled
- Existing third-party system extensions were present before the test and were unchanged afterward.
  Cornetta did not add any.

## Code audit

- No `SMJobBless`, `AuthorizationExecuteWithPrivileges`, privileged helper, `sudo`, `NSTask` or
  `osascript`.
- No kernel extension, DriverKit extension, system extension, launch daemon or launch agent.
- No `.pkg` installer and no installer receipt. The DMG is drag-and-drop.
- The only entitlement is `com.apple.security.device.audio-input`.
- The bundle contains one executable, its icon and localization files. It links only Apple system
  frameworks. There is no `Speech.framework`: transcription is an HTTP client built on `URLSession`.
- The transcription client uses an ephemeral `URLSession`, accepts no cookies, has explicit request and
  resource timeouts, and contacts only the endpoint stored in preferences. The default is loopback.
  App Transport Security allows local networking only, not arbitrary HTTP loads.
- The only optional persistence is `SMAppService.mainApp`, used by “Open at login”. It has both
  `register()` and `unregister()` paths and is not a background daemon.
- The app is universal (`x86_64` and `arm64`) with minimum macOS 14.4.
- Audio capture uses a private Core Audio aggregate device. It is created with
  `kAudioAggregateDeviceIsPrivateKey: true` and `kAudioAggregateDeviceTapAutoStartKey: false`, and is
  destroyed in `teardownCapture()` and `deinit`.
- The app never sets the system default input or output device. It reads the current defaults and
  listens for changes.
- File writes are limited to user data locations: `~/Music/Cornetta`, `~/Movies/Cornetta`,
  `~/Library/Application Support/Cornetta`, `~/Library/Logs/Cornetta`, application preferences and
  temporary files.
- `AppMover` copies the app to `/Applications` only after the user confirms, using normal user
  permissions. It never invokes an authorization prompt or writes to `/System` or `/Library`.

## Real Intel test

Executed on the machine above:

```text
Cornetta.app --probe /tmp/probe.txt
Cornetta.app --record 10 --out /tmp/security.m4a --debug-tracks /tmp/tracks
```

Results:

- Microphone probe worked: 142 callbacks, aggregate device running.
- Ten-second recording produced a valid `.m4a`.
- Default input remained the same USB microphone.
- Default output and system output remained the same Bluetooth headset.
- No `Cornetta` aggregate device remained after exit.
- No Cornetta process remained.
- No new third-party kext.
- No new system extension.
- No new package receipt.
- No new launch agent or daemon.
- No Cornetta file under `/Library`.
- No new Cornetta file under `~/Library` beyond the files that already existed from previous runs.
- A copied app was launched from a temporary directory, removed, and left no process or system item.
- The HTTP transcription client was exercised against a local mock Whisper server: `verbose_json`
  segments, the `json` fallback, a plain-text response, an HTTP 500 error, and two separate speaker
  tracks all behaved as documented. No remote transcription service was contacted.
- `codesign --verify --deep --strict` passed. `spctl` rejects the ad-hoc signature, as expected:
  first launch requires **Open Anyway**.
- The bundle binary has `minos 14.4` for both `x86_64` and `arm64`.

## macOS version matrix

| Version | Intel status | Notes |
|---|---|---|
| macOS 14.4 Sonoma | supported by code, not executed here | Core Audio process taps are available from 14.2. Screen recording with microphone is hidden because it requires macOS 15. HTTP transcription is available when a service is configured. |
| macOS 15 Sequoia | executed on 15.8.1 Intel | Recording and probe passed. Screen recording with microphone is available. The HTTP transcription client passed against a local mock. |
| macOS 26 Tahoe | supported by code, not executed on an Intel host | Uses the same recording and HTTP transcription paths; there is no OS-specific speech API to guard. |

The app does not have a separate Apple Silicon path that bypasses guards. The Intel `x86_64` slice was
built and exercised directly.

## Uninstall

The app has no system-level component to remove.

1. Quit Cornetta from its menu.
2. If “Open at login” is enabled, turn it off first.
3. Move `Cornetta.app` from Applications to the Trash.
4. If a stale login item remains, remove Cornetta in **System Settings › General › Login Items &
   Extensions**.
5. Optional: delete user data separately. This deletes recordings and transcripts:
   - `~/Music/Cornetta`
   - `~/Movies/Cornetta`
   - `~/Library/Application Support/Cornetta`
   - `~/Library/Logs/Cornetta`

No kext, system extension, launch daemon, package receipt or driver remains after step 3.

## Residual risks

- The build is ad-hoc signed and not notarized. The user must use **Open Anyway** and should verify the
  SHA-256 in the signed update feed or GitHub release notes.
- The app is not sandboxed. It can access files with the user's normal permissions by design. The code
  reviewed here does not use that access to modify system locations.
- Transcription was not exercised against a third-party remote service. The client and its failure
  paths were tested with a local mock; a remote endpoint is the user's configuration and trust choice.
- If the user configures a remote endpoint, the audio file, its filename and the model/language fields
  leave the Mac. The privacy pages and `docs/TRANSCRIPTION.md` state this explicitly.
- A user who forces the app to crash during capture may leave a working audio file; macOS cleans up the
  private aggregate device when the process exits. No driver or system setting is involved.

## Tooling

No additional MCP server or third-party security skill was needed. The review used built-in macOS tools:
`sw_vers`, `system_profiler`, `pkgutil`, `systemextensionsctl`, `kmutil`, `launchctl`, `codesign`,
`otool`, `vtool`, `spctl`, and the app's own `--probe` and `--record` modes. A static regression test is
in `scripts/tests/test_security_guard.py`.
