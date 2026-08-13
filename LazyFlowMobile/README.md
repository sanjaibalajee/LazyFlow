# LazyFlow for iOS

LazyFlow for iOS is a native companion app plus a focused custom keyboard. It is intentionally not a replacement typing keyboard: switch to LazyFlow to dictate, and switch back to Apple's keyboard to type.

## Product architecture

1. The containing app starts a time-limited **voice session** and owns `AVAudioSession` / `AVAudioEngine`.
2. The keyboard writes tiny start, stop, tone, and session commands to the shared App Group.
3. The app records an utterance and uses the processing pipeline selected in Settings.
4. The keyboard reads the finished text and inserts it at the current cursor with `textDocumentProxy`.

The keyboard never requests or receives microphone input. Full Access is needed only for the App Group bridge. While a voice session is active, the app keeps the microphone session alive and iOS displays its orange privacy indicator. Sessions expire after 30 minutes and can be ended from either surface.

The keyboard's **Start talking** button writes a session command and makes a best-effort request to open `lazyflow://start`. iOS does not officially guarantee containing-app launches from custom keyboards, so the keyboard also shows a clear manual fallback when that request is declined. No private URL-opening API is used.

## Processing and Groq

Apple On-Device is the default for both stages and requires no API key:

- Speech to text: Apple `SpeechAnalyzer`
- Tone and cleanup: Apple Foundation Models, with deterministic local cleanup as a fallback

Groq is optional and can be selected independently for either stage:

- Speech to text: `whisper-large-v3-turbo` or `whisper-large-v3`
- Tone and cleanup: `openai/gpt-oss-20b` or `openai/gpt-oss-120b`

Add a Groq API key under **LazyFlow > Settings > Groq**. The key is verified before saving and stored in the iPhone Keychain with device-only accessibility. It is never copied into App Group defaults, the keyboard extension, or dictation history.

Finished dictations are available from the History tab. History is stored locally with complete file protection and records the selected tone and processing models.

## Requirements

- Xcode 27 beta or newer
- iOS 26 or newer
- An iPhone that supports Apple's on-device Foundation Models for tone cleanup
- App Group capability: `group.com.fanpit.LazyFlow`

Both the app and keyboard provisioning profiles must include the App Group. Settings shows whether the shared bridge is available so a signing problem does not look like a stuck session.

## Generate and build

The checked-in project is generated with XcodeGen so target settings stay reviewable:

```sh
xcodegen generate --spec LazyFlowMobile/project.yml
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project LazyFlowMobile/LazyFlowMobile.xcodeproj \
  -scheme LazyFlowMobile \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

`ActivityGlyph` is consumed as a Swift Package from its public repository.
