# Meeting summaries

Cornetta can create a summary from a transcript and editable meeting information.
Summaries are generated only when the user presses **Generate**.

## Summary settings

Open **Summary settings…** from the menu bar menu. The window has two tabs.

### LLM providers

Each provider is an OpenAI-compatible chat-completions endpoint:

- name;
- base URL, for example `https://api.example.com/v1`;
- default model;
- optional API key in the macOS Keychain;
- one provider can be marked as the default.

If the base URL has no path, Cornetta assumes `/v1`. It accepts both a base URL
such as `http://host:8081` and the complete
`http://host:8081/v1/chat/completions` endpoint. **Check service** sends
`GET /v1/models` (or the matching path) with the draft API key and never sends
the transcript.

**Default model** loads a dropdown from the provider's `/v1/models` list. Choose
the model and press **Save**; the summary window preselects it for this provider
while still allowing a one-off model. If the list is unavailable, the same row
shows a manual field, the saved model and a **Load models** button.

### Prompt templates

Prompt templates are reusable instructions. Exactly one template is the
default. A template can use:

- `{{topic}}`
- `{{participants}}`
- `{{date}}`
- `{{time}}`
- `{{notes}}`
- `{{transcript}}`
- `{{language}}`

If a custom template omits `{{transcript}}`, Cornetta appends the transcript.
The built-in default template is created in the current interface language.
Changing the default prompt does not change existing summaries.

## Meeting information

Meeting information is stored separately from the audio and the transcript:

`~/Library/Application Support/Cornetta/Incontri/<recording-name>.json`

Fields:

- topic;
- participants;
- start date and time;
- user notes.

The first opening pre-fills topic from the recording title, participants from
the audio Artist tag and the start date from the recording date. The user can
edit all fields. The file is created or updated only when the user saves the
information or generates a summary.

The fields can be opened independently from the Summary tab with **Edit
information**, without opening or starting a summary. Participants and notes use
multi-line editors with at least five visible lines and internal scrolling.

## Summary window and view

In **Recordings and transcripts**, a segmented control under the recording
header switches between **Transcript** and **Summary**.

Press **Generate summary** to open the summary window. The window contains the
editable meeting information and three selectors:

- provider;
- one model selector;
- prompt.

The provider and prompt defaults are preselected. Switching the provider loads
its model list once, with a refresh button. If a provider does not expose a model
list, Cornetta says so and leaves a manual model field instead of showing two
competing selectors.
Per-run selections do not change the defaults in Summary settings.

The generated summary is shown in the Summary tab with the model, prompt name
and provider used. The same snapshot is saved in the summary files:

- `Riassunti/<recording-name>.json`
- `Riassunti/<recording-name>.md`

The summary record includes `providerID`, `providerName`, `model`, `promptID`,
`promptName`, `createdAt` and `language`. Prompt and provider names are snapshots,
so renaming a prompt later does not rewrite old summaries.

The Summary tab opens in **Read** mode, which formats headings, paragraphs,
lists, quotes, code blocks and tables as an article. Switch to **Code** to see
and select the original Markdown. **Copy summary** puts the raw Markdown on the
clipboard.

## Privacy boundary

- A summary request starts only from **Generate**.
- The selected provider receives the transcript, the meeting information and
  the prompt. No other recording or contact data is sent.
- The API key stays in the macOS Keychain and is sent only to that provider.
- Check service sends no transcript and no audio.
- There is no background request, no automatic summary and no telemetry.
- The provider URL, name, model and key are user settings and are not committed
  to the repository or release metadata.

Long transcripts are sent whole in the current version. If a model has a smaller
context window, the provider returns its own error. Chunked map-reduce summaries
are a possible later extension.
