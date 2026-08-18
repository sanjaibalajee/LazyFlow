# lazyflow

native macos dictation.

hold right ⌥, speak, release. lazyflow transcribes, applies the active app profile, and pastes at the cursor.

## requirements

- macos 14+
- microphone and accessibility permissions
- an api key for the selected cloud provider

## setup

1. open settings
2. add the api key
3. grant microphone and accessibility access

## controls

| input | action |
|---|---|
| hold right ⌥ | record; release to transcribe and paste |
| menu bar mic | toggle recording |
| transcript edit | save correction data |
| ⌘q | hide windows; keep lazyflow running |
| menu bar → quit | terminate |

## pipeline

`audio → transcription → corrections → app profile → paste`

app profiles define tone, formatting, protected terms, correction pairs, and custom instructions. `minimal` bypasses llm cleanup.

## storage

- api keys: keychain
- transcripts and corrections: sqlite in `~/Library/Application Support/LazyFlow/`
- profiles: user defaults
- telemetry: none
- cloud transcription sends audio to the selected groq, openai, or elevenlabs provider
- cloud cleanup sends text to the selected llm provider

## release

1. increment `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`
2. archive with developer id, notarize, and staple `LazyFlow.app`
3. run `scripts/publish-update.sh /path/to/LazyFlow.app v<version>`

the script rejects invalid release signatures, generates the sparkle signature and `appcast.xml`, then publishes both assets to github. installed builds follow the latest appcast through sparkle.
