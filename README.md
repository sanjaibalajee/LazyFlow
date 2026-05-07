# lazyflow

native macos dictation app. hold right ⌥ to speak, release to paste cleaned text wherever your cursor is.

uses groq whisper for transcription and an llm to clean up the output — fixing punctuation, removing filler words, preserving code identifiers, whatever the app you're typing into needs.

## setup

1. get a free api key at [groq.com](https://groq.com)
2. open lazyflow → settings → paste your key
3. grant accessibility permission when prompted (required for the global hotkey)
4. grant microphone permission when prompted

## usage

| action | result |
|---|---|
| hold right ⌥ | record — releases transcribe and paste |
| click mic in menu bar | same thing with a button |
| click ✏️ on any transcript | correct it — lazyflow learns from your edit |

## app profiles

lazyflow creates a profile for each app you dictate in. profiles control how the output is cleaned.

**tone presets**

- **technical** — preserves flags, paths, identifiers. for terminals and docs.
- **casual** — contractions, natural pauses, no filler words. for slack, imessage.
- **formal** — complete sentences, proper grammar. for email and reports.
- **code** — never touches camelCase, snake_case, or function names.
- **minimal** — skips llm entirely. raw whisper output, no cleanup.

**per-profile options**

- formatting toggles: bulletize, stronger punctuation, preserve line breaks, lowercase, keep filler words
- protected terms: words or phrases whisper must preserve exactly (names, product names, jargon)
- correction pairs: what whisper hears → what it should be. added manually or learned automatically when you correct a transcript
- custom instructions: anything else, layered on top of the tone

## corrections

when whisper consistently mishears something (a name, a technical term), you can teach lazyflow to fix it:

1. click ✏️ on the wrong transcript
2. type the correct version
3. save — lazyflow extracts the changed words and stores the pair

next time whisper makes the same mistake, lazyflow fixes it automatically. high-confidence corrections (applied 2+ times) are substituted directly in swift before the llm even sees the text.

the vocabulary hint is also passed to whisper's prompt field so it tries to spell names correctly from the start.

## history

the history view shows every transcript, grouped by date, searchable, filterable by app. your history is stored locally in a sqlite database and persists across relaunches.

## requirements

- macos 14+
- apple silicon or intel
- groq api key (free tier works fine)
- accessibility permission (for the global hotkey event tap)
- microphone permission

## privacy

- audio is sent to groq for transcription (their api, their privacy policy)
- transcript text is sent to groq's llm for cleanup
- nothing is logged to disk or sent anywhere else
- your api key is stored in the system keychain
- all history and corrections are stored locally in `~/Library/Application Support/LazyFlow/`
