# LazyFlow for iOS

LazyFlow for iOS is a native companion app plus a focused custom keyboard. It is intentionally not a replacement typing keyboard: switch to LazyFlow to dictate, and switch back to Apple's keyboard to type.

## Product architecture

1. The containing app starts a time-limited **voice session** and owns `AVAudioSession` / `AVAudioEngine`.
2. The keyboard writes tiny start, stop, tone, and session commands to the shared App Group.
3. The app records an utterance, transcribes it on device with `SpeechAnalyzer`, and optionally cleans up its tone with `FoundationModels`.
4. The keyboard reads the finished text and inserts it at the current cursor with `textDocumentProxy`.

The keyboard never requests or receives microphone input. Full Access is needed only for the App Group bridge. While a voice session is active, the app keeps the microphone session alive and iOS displays its orange privacy indicator. Sessions expire after 30 minutes and can be ended from either surface.

## Requirements

- Xcode 27 beta or newer
- iOS 26 or newer
- An iPhone that supports Apple's on-device Foundation Models for tone cleanup
- App Group capability: `group.com.fanpit.LazyFlow`

Transcription remains available when Foundation Models is unavailable; LazyFlow falls back to deterministic cleanup. No API key or account is used.

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
