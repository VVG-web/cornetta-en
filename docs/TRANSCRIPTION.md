# Transcription providers

Cornetta has two kinds of providers:

- **Apple Speech on this Mac** uses macOS 26 speech recognition and keeps audio local.
- **HTTP providers** implement the OpenAI Whisper transcription endpoint. You can
  save more than one and choose the active provider in settings.

```text
POST <scheme>://<host>:<port><path>
Content-Type: multipart/form-data
```

The default HTTP provider is `http://127.0.0.1:8080/v1` with model `whisper-1`,
automatic language detection, and automatic transcription off. The Windows build
does not transcribe.

## Configuration

Open **Transcription settings…** from the menu bar menu. The **Provider** picker
contains Apple Speech and every saved HTTP provider. The **+** button opens a
new-provider form. A custom provider can be renamed, edited or deleted.

Apple Speech has no base URL or key. It shows a warning on macOS versions before
26 and never sends audio to the network. On first use macOS may download the
speech language asset; that download contains no recording.

Each HTTP provider stores these values independently:

| Field | Default | Notes |
| --- | --- | --- |
| Base URL | `http://127.0.0.1:8080/v1` | Full OpenAI-compatible base URL. Cornetta appends `/audio/transcriptions`. Use `https` outside the local network. |
| Model | `whisper-1` | Sent only when non-empty. |
| Language | empty (automatic) | Sent only when non-empty; use an ISO-639-1 code such as `ru`. |
| API key | empty | Optional. Stored per provider in the macOS Keychain, sent only as that provider's Bearer token. |

The base URL is the value an OpenAI SDK calls `base_url`, for example
`https://api.example.com/v1`. Cornetta builds the transcription endpoint by
appending `/audio/transcriptions`, and the model-list endpoint by appending
`/models`. No separate port is required: `https` uses 443 and `http` uses 80
unless the URL contains an explicit port.

**Check service** sends a `GET` to `<baseURL>/models` with the draft API key. It
never sends audio and never saves the draft. A 401/403 means the key is missing
or invalid. A 200 with the configured model in the list means the model is
available. A 404/405/501 means the provider does not expose a model list;
transcription may still work.

The preview under the fields shows the resulting URL and turns red when the
base URL is invalid. Provider changes are saved only when you press **Save**.

The toggle **Transcribe immediately after each recording** is the same option
as the menu item. It is off by default. With it off, a recording is transcribed
only when you press **Transcribe** in the Recordings window.

## Request

Cornetta sends one multipart form per audio file:

| Part | Value |
| --- | --- |
| `file` | The audio file, with its filename and MIME type. |
| `model` | The configured model, omitted when empty. |
| `language` | The configured language, omitted when empty. |
| `response_format` | `verbose_json` first, then `json` if the service rejects it. |

The request has `Accept: application/json` and a User-Agent of
`Cornetta/<version>`. The session is ephemeral, accepts no cookies, and has a
10-minute request timeout and a 15-minute resource timeout. If an API key is
saved, the request adds `Authorization: Bearer <key>`.

Each key is a separate generic-password item in the macOS Keychain, never in
`UserDefaults`, a source file or a log. To remove a key, clear the field and press
**Save**; leaving the key field untouched preserves the stored key, even when the
Keychain could not be read. The settings window keeps edits in a draft and writes
them only when you press **Save**. Switching the provider in the picker takes
effect immediately; provider fields still require Save.

If `verbose_json` returns HTTP 400, 415 or 422, Cornetta retries the same file
once with `response_format=json`. Other HTTP errors, connection failures and
unreadable files become a failed transcription; the audio is never modified.

## Response

With `verbose_json`, Cornetta reads the optional `segments` array:

```json
{
  "text": "Ciao a tutti.",
  "segments": [
    {"start": 0.1, "end": 0.8, "text": " Ciao"},
    {"start": 1.0, "end": 1.8, "text": " a tutti."}
  ]
}
```

Missing or blank segment text is skipped. Missing times fall back to zero and
the audio duration. If there are no usable segments, Cornetta uses `text` (or
`result`) as one segment covering the whole file. A plain-text response is
accepted too.

## Speaker labels

For a new recording, Cornetta stores two tracks:

- `tu.m4a` from the microphone, labelled **Tu** / **You**;
- `altri.m4a` from system audio, labelled **Altri** / **Others**.

When both are available, Cornetta sends them as two separate requests and merges
the timestamped results. Recordings made without tracks are sent as one mixed
file and labelled **Voce** / **Unattributed voice**. Speaker separation is
therefore a property of the recording, not of the transcription model.

## Privacy boundary

- The app makes no transcription request at launch and does not poll a service.
- A request starts only from **Transcribe**, **Transcribe again**, or the
  automatic option after a recording finishes.
- The configured endpoint receives the audio file, its filename, the model and
  language fields, and the response-format field. It does not receive the
  transcript, other recordings, device names, contacts, or application logs.
- The default endpoint is loopback. If the service runs on the same Mac, audio
  does not leave the computer. A remote service is the user's choice and should
  use HTTPS.
- macOS App Transport Security is configured for local networking only
  (`NSAllowsLocalNetworking`), not arbitrary HTTP loads. A public host reached
  over plain HTTP is blocked by the system; use HTTPS.
- Recordings, JSON transcripts and Markdown files remain in the user's folders.

## Local test

Any Whisper-compatible server works. A minimal request check with `curl`:

```bash
curl -f http://127.0.0.1:8080/v1/audio/transcriptions \
  -F file=@Chiamata.m4a \
  -F model=whisper-1 \
  -F response_format=verbose_json
```

Headless mode uses the selected provider from the same stored configuration:

```bash
build/Cornetta.app/Contents/MacOS/Cornetta --transcribe file.m4a
build/Cornetta.app/Contents/MacOS/Cornetta --transcribe file.m4a --tracks cartella
```

The second form expects `cartella/tu.m4a` and `cartella/altri.m4a` and prints the
merged Markdown.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `not configured` | Base URL is empty or invalid. It must be an `http`/`https` URL with a host and no query or credentials. |
| Connection refused | No service is listening on the host and port in the base URL. |
| HTTP 404 | The base path is wrong; Cornetta appends `/audio/transcriptions`. |
| HTTP 400/415/422 | The service rejected `verbose_json`; Cornetta retries with `json`. If it still fails, check the audio format and required fields. |
| HTTP 401/403 | The API key is missing, invalid or not allowed to use this model. |
| TLS error | A self-signed or otherwise untrusted HTTPS certificate. Use a trusted certificate or a local HTTP service. |
| Plain HTTP to a remote host fails | App Transport Security only allows local networking; use HTTPS. |
