# lazyflow

native macos dictation app. hold right ⌥ to speak, release to paste cleaned text wherever your cursor is.

uses whisper for transcription and an llm to clean up the output — fixing punctuation, removing filler words, preserving code identifiers, whatever the app you're typing into needs.

## ios app

the native iOS companion app and voice-only keyboard are under [`LazyFlowMobile`](LazyFlowMobile/README.md). the iOS build uses Apple's on-device speech and language models, requires no API key, and keeps ordinary typing on Apple's keyboard.

## install

download the latest `LazyFlow.dmg` from
[releases](https://github.com/sanjaibalajee/LazyFlow/releases), open it, and drag
LazyFlow to Applications. the build is signed and notarized by Apple, so it opens
without any security prompt.

on first launch macOS asks for **microphone** and **accessibility** — both are
required for dictation, and the setup flow walks you through them.

building from source? see [RELEASING.md](RELEASING.md).

## setup

on first launch a guided setup walks you through the whole thing: add a key, then grant accessibility + microphone. you can re-open it anytime from the menu bar → **Setup & Permissions…**

- **transcription** — groq whisper (free key at [console.groq.com](https://console.groq.com/keys)) by default, or run fully on-device with a local Parakeet/Whisper model (no key).
- **cleanup llm** — groq by default; add an **Anthropic (Claude), OpenAI, or Google** key in settings to use another provider for dictation cleanup. accuracy-first setups should use Claude.

updates ship via sparkle — menu bar → **Check for Updates…** (see [RELEASING.md](RELEASING.md) to configure the feed).

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
- Apple Silicon or Intel
- groq api key (free tier works fine)
- accessibility permission (for the global hotkey event tap)
- microphone permission

## privacy

- audio is sent to groq for transcription and transcript text is sent to groq's llm for cleanup — groq's api terms and privacy policy apply to both
- no telemetry or debug logs are sent or stored anywhere
- your api key is stored in the system keychain, never on disk in plaintext
- history and corrections are stored locally in sqlite at `~/Library/Application Support/LazyFlow/` — they never leave your machine
