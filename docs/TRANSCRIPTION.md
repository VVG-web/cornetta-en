# HTTP transcription

Cornetta does not ship a speech model. On macOS it can send a recording to an
HTTP service that implements the OpenAI Whisper transcription endpoint:

```text
POST <scheme>://<host>:<port><path>
Content-Type: multipart/form-data
```

The default is `http://127.0.0.1:8080/v1/audio/transcriptions`, with model
`whisper-1`, automatic language detection, and automatic transcription off.
The Windows build does not transcribe.

## Configuration

Open **Transcription settings…** from the menu bar menu. The window stores these
values in the app preferences:

| Field | Default | Notes |
| --- | --- | --- |
| Protocol | `http` | Use `https` for a service outside the local network. |
| Address | `127.0.0.1` | IPv4, IPv6, `localhost` or a DNS name. |
| Port | `8080` | 1–65535. |
| Path | `/v1/audio/transcriptions` | A leading slash is added if missing. |
| Model | `whisper-1` | Sent only when non-empty. |
| Language | empty (automatic) | Sent only when non-empty; use an ISO-639-1 code such as `it`. |

The **Path** field is the full path after the host and port. For a service whose
OpenAI-compatible base URL is `http://host:9193/v1`, enter
`/v1/audio/transcriptions`, not `/v1`.

The preview under the fields shows the resulting URL and turns red when the
address, port or path is invalid. **Restore defaults** resets every field. No
separate save step is needed.

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
10-minute request timeout and a 15-minute resource timeout. The client does not
send an API key or any other credential; use a local service or an
authenticating reverse proxy when a service requires one.

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

Headless mode uses the same stored configuration:

```bash
build/Cornetta.app/Contents/MacOS/Cornetta --transcribe file.m4a
build/Cornetta.app/Contents/MacOS/Cornetta --transcribe file.m4a --tracks cartella
```

The second form expects `cartella/tu.m4a` and `cartella/altri.m4a` and prints the
merged Markdown.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `not configured` | Address or port is empty/invalid, or the scheme is not `http`/`https`. |
| Connection refused | No service is listening on that address and port. |
| HTTP 404 | The path is wrong; the default is `/v1/audio/transcriptions`. |
| HTTP 400/415/422 | The service rejected `verbose_json`; Cornetta retries with `json`. If it still fails, check the audio format and required fields. |
| HTTP 401/403 | The service requires authentication, which this client does not send. |
| TLS error | A self-signed or otherwise untrusted HTTPS certificate. Use a trusted certificate or a local HTTP service. |
| Plain HTTP to a remote host fails | App Transport Security only allows local networking; use HTTPS. |
