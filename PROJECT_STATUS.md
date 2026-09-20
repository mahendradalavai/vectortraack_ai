# Kitten AI — Project Status

## Project

- **Project name:** kitten
- **Framework:** Flutter 3.47.5 (stable channel)
- **Target platform:** Android (primary), with iOS/Web/Windows/macOS/Linux scaffolding present
- **Version control:** Git repository. Baseline `492be59`, Task 003 closure `4ed421c`.
- **Current development stage:** Task 008 complete — Kitten can now look at your screen on demand: one press, Android's consent prompt, one screenshot, and an answer from a vision model that streams into the same conversation.

## Environment

- **Flutter version:** 3.47.5 (stable) — revision 6a19cca564 (2026-09-17)
- **Dart version:** 3.13.4 (stable) — windows_x64
- **DevTools version:** 2.60.0
- **Android configuration:**
  - Namespace / Application ID: `com.example.kitten`
  - compileSdk: Flutter default (`flutter.compileSdkVersion`)
  - minSdk: `24`
  - targetSdk: Flutter default (`flutter.targetSdkVersion`)
  - Java compatibility: 17
  - Kotlin JVM target: 17
  - Build system: Gradle (Kotlin DSL)
  - AndroidX: enabled
  - Signing: debug keys only (no release signing configured)
- **Verified emulator:** Pixel_7 AVD — Android 17 (API 37), `android-x64`, 1080x2400 @ 420dpi
- **Other relevant environment information:**
  - OS: Windows (x64)
  - Analysis: `flutter_lints` v6.0.0 with platform directories excluded
  - Note: building with plugins on Windows may require Developer Mode for symlink support

## Completed Tasks

1. **Task 001 — Project Initialization & Status System** — project inspection, status doc, clean baseline.
2. **Task 002 — Create the Kitten App Foundation** — feature-based architecture, home screen, animated avatar, `AssistantState` model, settings placeholder, Material 3 dark mode.
3. **Task 003 — Groq AI Provider Foundation** — pluggable `AiProvider`, isolated `GroqProvider`, encrypted key storage with masking, personality prompt, streaming text conversation UI, settings with connection testing. Closed out with Git init, doc fixes, typed errors, SSE token streaming, and disposal cleanups.
4. **Task 004 — Voice Input / Output** — hands-free voice conversation, spoken replies, and graceful degradation to text-only mode.
5. **Task 005 — "Hey Kitten" Activation** — opt-in, foreground-only wake-word listening with remainder-as-command.
6. **Task 006 — Kitten Animation / Personality System** — procedural animated character and an evolving mood described below.
7. **Task 007 — Android App-Awareness** — Android usage-stat tracking behind an explicit permission, surfaced in the UI and in Kitten's prompt, described below.
8. **Task 008 — Screen Understanding** — on-demand screenshot capture with explicit consent, answered by a vision model, described below.

## Current Task

**Task 008 — Screen Understanding with Explicit Permission**
Status: **COMPLETED**

### What was built (Task 008)

- **On-demand capture (selected behaviour):** `ScreenUnderstandingController` takes exactly one
  screenshot per press of the new button, and only after Android's own projection consent
  dialog. Nothing is captured in the background, and there is no always-on screen reading.
- **MediaProjection + foreground service (selected behaviour):** a Kotlin
  `ScreenCaptureService` takes the shot. Android 14+ refuses to project unless a foreground
  service of the `mediaProjection` type is already running, so the service lives for the
  second the capture takes, shows the system's "Kitten is reading your screen" notice, and
  stops itself immediately afterwards.
- **The image goes to a vision model (selected behaviour):** the screenshot is attached to the
  user's turn as an OpenAI-compatible `image_url` part carrying an inline base64 data URL, and
  that turn is routed to `qwen/qwen3.8-27b` — Groq's multimodal model — because the everyday
  text model cannot read pictures. `ChatRequest.withModel` makes that a one-line reroute.
- **A vision turn is a normal conversation turn:** it streams, cancels, and lands in the same
  chat history as any other message, and the bubble carries a small "Screenshot" label so it is
  unmistakable that a picture went with it.
- **Token discipline:** replaying history resends only the *newest* screenshot. Older image
  turns fall back to their text, so a long conversation does not re-upload a picture every turn.
- **Privacy notice (once):** before the first capture the app explains exactly what will happen
  — one screenshot, sent to Groq, consent asked every time, nothing in the background — and
  remembers that it explained. Cancelling captures nothing.
- **Fails soft:** every platform failure is mapped to a typed `ScreenCaptureException` and a
  plain-English message. A cancelled consent is reported as *cancelled*, not as an error, so
  saying no stays quiet.

### On-device verification (Pixel 7, Android 17 / API 37)

Verified with a real device integration test (`integration_test/screen_understanding_test.dart`).
Reproduce with:

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell appops set com.example.kitten PROJECT_MEDIA allow
flutter test integration_test/screen_understanding_test.dart -d emulator-5554
```

- **3 of 3 runnable tests passed, 1 skipped.** A real screenshot was captured and returned as a
  valid JPEG: **31,740 bytes at 1080x2400**, verified by decoding it and checking the JPEG
  start-of-image marker.
- The one-time privacy note appeared before the first read, and Cancel captured nothing.
- The vision turn was confirmed to ask for `qwen/qwen3.8-27b` rather than the text model.
- **Skipped on this emulator:** the live vision round-trip, because no Groq API key is
  configured on it. The test skips itself with a clear message instead of pretending to pass.
- **Not verified on device:** the vision model's actual description of a real screen (needs an
  API key), and the consent dialog being *declined* by a human, which is covered by unit tests.

### Bugs found and fixed while verifying (Task 008)

On-device testing earned its keep here. Five real defects surfaced, four of them invisible to
unit tests:

1. **The app died on the first capture.** `createVirtualDisplay` threw
   `IllegalStateException: Must register a callback before starting capture`, and because the
   service's work was not wrapped, an uncaught exception on the main thread killed the whole
   process. Fixed by registering a `MediaProjection.Callback`, *and* by wrapping the capture so
   a failure now returns "could not capture" instead of taking the app down.
2. **`Virtual display density must be positive`.** The screen-metrics helper filled width and
   height from the window metrics but never set `densityDpi`, so the projection refused to
   start. Density now comes from resources, which is always populated.
3. **The first image callback was treated as the frame.** `acquireLatestImage` can return
   nothing before a frame is readable; giving up on the first miss made the capture fail. It
   now waits for the next callback, with a real timeout behind it.
4. **A rewrite silently dropped imports** the app-awareness code depended on. Caught by the
   Kotlin compiler, not by analysis.
5. **The platform sends bytes, Dart asked for a string.** `invokeMethod<String>` on a `byte[]`
   threw a cast error; the JPEG is now received as `Uint8List` and base64-encoded on the Dart
   side, where the data URL is built anyway.

---

### Previous task — Task 007 — Android App-Awareness
Status: **COMPLETED**

### What was built (Task 007)

- **Native channel** (`kitten/app_awareness` in `MainActivity.kt`) — Android's usage APIs need the
  `GET_USAGE_STATS` app-op, which has no plugin-visible equivalent, so the handful of platform
  lines sit beside the app's own activity instead of adding another dependency. Kotlin-only code
  is deliberately optional: every method fails soft, so a `MissingPluginException` or platform
  error degrades to "no awareness" rather than crashing.
- **`AppAwarenessService` contract** — `isSupported`, `hasUsageAccess`, `openUsageAccessSettings`,
  and `foregroundApp`, with `MethodChannelAppAwarenessService` as the only implementation, so the
  polling and permission logic is testable without Android.
- **`AppAwarenessController`** — a `ChangeNotifier` that gates everything on the permission, polls
  the foreground app every 5 seconds, and contributes prompt context.
- **Explicit permission only (selected behaviour):** Usage Access is a *special* permission that
  cannot be granted by a normal dialog, so the app never claims to work without it: enabling
  while it is missing reverts the switch, explains why, and deep-links to the system screen.
  Returning to the app finishes the enable the user asked for.
- **Shown to the user (selected behaviour):** the home screen shows a "Last app: Chrome" hint,
  and Settings has a real App Awareness switch, a Usage Access status row with a Grant action,
  and a "Last app seen" row with the package id.
- **Used by Kitten (selected behaviour):** `ChatService` accepts a `contextProvider` callback and
  appends its output to the system prompt beneath the persona and mood, so a reply can refer to
  the app naturally. The text explicitly states Kitten *cannot see the contents* of the screen.
- **No `QUERY_ALL_PACKAGES` (selected behaviour):** only `PACKAGE_USAGE_STATS` is declared. When
  Android withholds an app's label, `ForegroundApp.displayName` derives a readable name from the
  package id (skipping meaningless segments such as `android`/`apps`).
- **Never reports itself:** the last *other* app is reported, both because Kitten is usually the
  foreground app while it asks and because that is the app the user actually cares about. The
  query is bounded to a 10-minute window so the answer stays plausibly recent.
- **Privacy hygiene:** the microphone distinction applies here too — polling stops whenever the
  app leaves the foreground, and if the permission is revoked while away, awareness turns itself
  off rather than reporting a stale app.

### On-device verification (Pixel 7, Android 17 / API 37)

Verified with a real device integration test (`integration_test/app_awareness_test.dart`), which
requires no screen-coordinate guessing because it can find widgets and read the platform channel
directly. Reproduce with:

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell appops set com.example.kitten GET_USAGE_STATS allow
adb shell monkey -p com.android.chrome -c android.intent.category.LAUNCHER 1
flutter test integration_test/app_awareness_test.dart -d emulator-5554
```

- The channel reported `hasUsageAccess() == true` and detected a real foreground app:
  **`com.android.chrome`, shown as "Chrome"**.
- The controller turned that into prompt context containing the app's display name.
- The Settings screen showed `Granted` *before* the user touched anything, the switch enabled
  awareness when tapped, and the "Last app seen" row appeared.
- All three integration tests passed; the Kotlin compiled cleanly.
- **Not verified on device:** a *second* app other than Chrome, and behaviour when the user
  revokes Usage Access mid-session (covered by unit tests).

---

### Previous task — Task 006 — Kitten Animation / Personality System
Status: **COMPLETED**

### What was built (Task 006)

- **Procedural avatar** — `KittenAvatar` no longer draws an emoji in a circle. A `CustomPainter`
  draws Kitten from primitives: head, ears with pink inners, eyes with highlights, nose, mouth,
  whiskers, blush, and a tail. No image assets are involved, so it scales crisply to any size
  and stays diffable in version control.
- **Idle life (selected behaviour):** breathing, randomised blinking, occasional ear twitches,
  and a continuously swaying tail. When the mood goes sleepy Kitten closes its eyes, settles
  slightly lower, and slows its breathing.
- **Evolving mood (selected behaviour):** `PersonalityService` derives a `KittenMood` from the
  conversation with simple, deterministic rules — affectionate words warm Kitten up, playful
  words or exclamations lift it, questions make it curious, plain statements settle it, and a
  failed turn makes it concerned. Rapport grows with every exchange.
- **Mood feeds the prompt:** the mood is appended to the system prompt, so tone and expression
  always agree. Scope constraints are deliberately kept *above* the mood section so the
  character's feelings can never override them.
- **Doze-off ticker:** `HomePage` ages the mood every 15 seconds; after 90 quiet seconds Kitten
  falls asleep, and any new message wakes it.
- **Accessibility:** the avatar exposes a spoken description such as
  "Kitten is listening, feeling affectionate".

### Visual verification (web preview)

- Confirmed the drawing renders correctly as a cat, not a blob, and caught a real bug in the
  process: the whisker geometry mixed raw pixels with head-radius units, so two of the three
  whiskers per side stretched hundreds of pixels down the screen.
- Confirmed the **sleepy** mood visually — closed eyes and a desaturated tint appeared after the
  idle threshold, proving the whole `personality -> ChatService -> VoiceController -> HomePage`
  notification chain works.

---

### Previous task — Task 005 — "Hey Kitten" Activation
Status: **COMPLETED**

### What was built (Task 005)

- **Wake-word matcher** (`wake_word_matcher.dart`) — a pure function that scans a transcript
  for the wake phrase, tolerating casing, punctuation, and spacing. It returns any text spoken
  *after* the phrase as a usable question.
- **Wake mode in `VoiceController`** — an explicit `VoiceMode` state machine
  (`idle` / `watchingForWakeWord` / `conversation`). There is only one recogniser on the
  device, so the wake watch and the conversation loop are coordinated in one place instead of
  competing for the microphone.
- **Remainder-as-command (selected behaviour):** "Hey Kitten, what's the weather?" is
  answered immediately; a bare "Hey Kitten" just opens the microphone for a separate question.
- **Opt-in and foreground-only (selected behaviours):** wake listening is off by default, and
  `suspend()`/`resume()` close and re-arm the microphone as the app leaves and returns to the
  foreground. True background listening remains Task 012.
- **Listen modes:** the STT contract gained a vendor-neutral `SpeechListenMode`, so wake
  spotting uses the command-tuned engine while conversations use dictation.
- **Settings:** the Wake Word and Speak Replies placeholders are now real, persisted switches.
  If speech is unavailable the Wake Word switch refuses to claim it is listening and reverts.
- **Persistence:** preferences are stored through `SecureStorageService` (no second storage
  dependency) and re-applied at startup by `restorePreferences()`.

### On-device verification (Pixel 7, Android 17 / API 37)

- Wake listening is **off at startup** — zero recognition windows while idle.
- Toggling the Wake Word switch on started recognition immediately, cycling on the wake pause.
- After a full app restart the saved preference **re-armed listening automatically**.
- Toggling it off stopped recognition, and it stayed off across a further restart.
- No Flutter exceptions at any point.
- **Not verified on device:** recognising an actual spoken wake phrase (the emulator has no
  microphone input). Phrase matching is covered by unit tests instead.

---

### Previous task — Task 004 — Voice Input / Output
Status: **COMPLETED**

### What was built (Task 004)

- **Voice layer** under `lib/core/voice/`, mirroring the existing AI layer design:
  - `SpeechService` / `TtsService` abstract contracts so the conversation loop is
    testable without a microphone or speaker.
  - `DeviceSpeechService` wrapping `speech_to_text` and `FlutterTtsService` wrapping
    `flutter_tts`. Initialization never throws — an unsupported platform or denied
    permission degrades to text-only mode.
  - `VoiceController`, a `ChangeNotifier` that owns the voice services and composes the
    existing `ChatService`, driving `idle -> listening -> thinking -> speaking -> listening`.
- **Hands-free loop (selected behaviour):** the microphone reopens automatically after
  Kitten finishes speaking, so a conversation continues without touching the phone.
- **Spoken replies (selected behaviour):** Kitten reads each reply aloud automatically.
  `cleanTextForSpeech` strips stage directions such as `*purrs*` and decorative emoji so
  they are not read as literal characters.
- **Graceful degradation:** "no speech detected" is treated as normal in a continuous loop
  (quietly retries), while a denied permission ends the session with a clear message.
- **Home page:** the Talk button now drives the voice session (label flips to Stop), the
  status chip reflects voice states, and the microphone is released whenever the app leaves
  the foreground.
- **Android:** `RECORD_AUDIO` declared, plus Android 11+ `<queries>` visibility for
  `android.speech.RecognitionService` and `android.intent.action.TTS_SERVICE`.

### On-device verification (Pixel 7, Android 17 / API 37)

- App builds, installs, and runs; no Flutter exceptions.
- Both plugins registered natively (`SpeechToTextPlugin`, `FlutterTtsPlugin`).
- Tapping Talk requested and received `RECORD_AUDIO`.
- The system recognizer opened and the no-speech path retried automatically, confirming the
  hands-free loop on real platform APIs.
- At idle startup the microphone is not opened at all.
- **Not verified on device:** actual spoken input and audible output. The emulator has no
  microphone input, so real speech recognition and playback still need a physical device.

## Pending Tasks

Awaiting instructions for Task 009 (assistant tool/function system).

## Features Planned

The following are planned but **NOT yet implemented**:

- Floating kitten overlay
- Background listening / service
- Usage-history analysis beyond the single most recent app
- Context-aware questions driven by the app (the context is now available; richer prompts are not)
- Continuous or automatic screen watching (capture is deliberately one-shot and on demand)
- Phone assistant commands (device settings, volume, etc.)
- Alarm & timer commands
- Calling contacts & SMS
- Persistent conversation memory across sessions

## Files Created

| File | Task | Purpose |
|------|------|---------|
| `PROJECT_STATUS.md` | 001 | Single source of truth for project status |
| `lib/main.dart` | 002 | Minimal entry point launching `KittenApp` |
| `lib/app/app.dart` | 002 | Root `KittenApp` MaterialApp widget |
| `lib/app/theme/app_theme.dart` | 002 | Material 3 light/dark theme definitions |
| `lib/core/constants/app_constants.dart` | 002 | Centralized app-wide string constants |
| `lib/core/models/assistant_state.dart` | 002 | `AssistantState` enum (idle, listening, thinking, speaking) |
| `lib/features/home/presentation/pages/home_page.dart` | 002 | Main home screen: avatar, status, voice + text chat |
| `lib/features/kitten/presentation/widgets/kitten_avatar.dart` | 002 | Animated kitten avatar reacting to `AssistantState` |
| `lib/features/settings/presentation/pages/settings_page.dart` | 002 | Settings screen with AI configuration |
| `lib/shared/widgets/assistant_status_indicator.dart` | 002 | Status chip displaying current `AssistantState` |
| `lib/core/ai/models/ai_exception.dart` | 003 | User-safe error model with typed error categories |
| `lib/core/ai/models/chat_message.dart` | 003 | Conversation message model (system, user, assistant) |
| `lib/core/ai/models/chat_request.dart` | 003 | Provider-agnostic request payload (supports `stream`) |
| `lib/core/ai/models/chat_response.dart` | 003 | Provider-agnostic completion response model |
| `lib/core/ai/providers/ai_provider.dart` | 003 | Abstract AI provider interface |
| `lib/core/ai/providers/groq_provider.dart` | 003 | Groq HTTP provider with SSE streaming |
| `lib/core/ai/config/ai_config.dart` | 003 | Model identifiers, endpoints, and timeouts |
| `lib/core/ai/prompts/kitten_system_prompt.dart` | 003 | Personality prompt with scope constraints |
| `lib/core/ai/services/chat_service.dart` | 003 | Conversation coordinator: history, streaming, state |
| `lib/core/services/secure_storage_service.dart` | 003 | Encrypted storage wrapper with API key masking |
| `lib/features/home/presentation/widgets/chat_bubble.dart` | 003 | Conversation bubble widget |
| `lib/core/voice/config/voice_config.dart` | 004 | Voice locale, timings, and speech character |
| `lib/core/voice/services/speech_service.dart` | 004 | Abstract speech-to-text contract + `SpeechIssue` |
| `lib/core/voice/services/tts_service.dart` | 004 | Abstract text-to-speech contract |
| `lib/core/voice/services/device_speech_service.dart` | 004 | `speech_to_text` implementation |
| `lib/core/voice/services/flutter_tts_service.dart` | 004 | `flutter_tts` implementation |
| `lib/core/voice/services/voice_controller.dart` | 004 | Hands-free listen -> chat -> speak loop |
| `lib/core/voice/util/voice_text_cleaner.dart` | 004 | Strips stage directions/emoji before speaking |
| `lib/core/voice/util/wake_word_matcher.dart` | 005 | Pure wake-phrase matcher with remainder extraction |
| `lib/core/screen/config/screen_config.dart` | 008 | Default question, capture timeout, and the privacy-note key |
| `lib/core/screen/services/screen_capture_service.dart` | 008 | Abstract capture contract + typed `ScreenCaptureException` |
| `lib/core/screen/services/method_channel_screen_capture_service.dart` | 008 | Native-channel capture implementation |
| `lib/core/screen/services/screen_understanding_controller.dart` | 008 | Consent flow, one-shot capture, and the vision turn |
| `test/core/screen/screen_understanding_controller_test.dart` | 008 | Consent, failure, sizing, intro, and busy-state tests |
| `integration_test/screen_understanding_test.dart` | 008 | On-device capture and privacy-note verification |
| `android/app/src/main/kotlin/com/example/kitten/ScreenCaptureService.kt` | 008 | One-shot MediaProjection capture foreground service |
| `lib/core/awareness/models/foreground_app.dart` | 007 | Foreground app model with package-name fallback naming |
| `lib/core/awareness/services/app_awareness_service.dart` | 007 | Abstract app-awareness contract |
| `lib/core/awareness/services/method_channel_app_awareness_service.dart` | 007 | Native-channel implementation |
| `lib/core/awareness/services/app_awareness_controller.dart` | 007 | Permission gating, polling, and prompt context |
| `test/core/awareness/foreground_app_test.dart` | 007 | Display-name derivation and equality tests |
| `test/core/awareness/app_awareness_controller_test.dart` | 007 | Permission, polling, persistence, and context tests |
| `integration_test/app_awareness_test.dart` | 007 | On-device verification of the channel and the Settings flow |
| `lib/core/personality/models/kitten_mood.dart` | 006 | Mood enum carrying label and prompt fragment |
| `lib/core/personality/services/personality_service.dart` | 006 | Rule-based mood and rapport tracker |
| `test/core/personality/personality_service_test.dart` | 006 | Mood rules, idling, and prompt integration tests |
| `test/features/kitten/kitten_avatar_test.dart` | 006 | Paints every state/mood combination without error |
| `test/core/ai/ai_models_test.dart` | 003 | AI models, exceptions, prompts, config tests |
| `test/core/ai/groq_provider_test.dart` | 003 | Provider HTTP + SSE streaming tests |
| `test/core/ai/chat_service_test.dart` | 003 | Chat streaming, cancellation, error classification |
| `test/core/services/secure_storage_service_test.dart` | 003 | Key masking and storage abstraction tests |
| `test/core/voice/voice_controller_test.dart` | 004 | Hands-free loop, degradation, and lifecycle tests |
| `test/core/voice/voice_text_cleaner_test.dart` | 004 | Speech text cleaning tests |
| `test/core/voice/wake_word_matcher_test.dart` | 005 | Wake-phrase matching and remainder tests |

## Files Modified

| File | Task | Change |
|------|------|--------|
| `pubspec.yaml` | 003, 004 | Added `http`, `flutter_secure_storage`; then `speech_to_text`, `flutter_tts` |
| `android/app/build.gradle.kts` | 003 | Set `minSdk = 24` for modern encryption support |
| `lib/core/ai/config/ai_config.dart` | 003 closure | Added models endpoint and connection-test timeout |
| `lib/core/ai/models/chat_request.dart` | 003 closure | Added `stream` flag to `toJson` |
| `lib/core/ai/providers/ai_provider.dart` | 003 closure | Added `streamMessage` and `dispose` |
| `lib/core/ai/providers/groq_provider.dart` | 003 closure | Added SSE streaming, shared error mapping, `dispose` |
| `lib/core/ai/services/chat_service.dart` | 003 closure | Streaming, cancellation, typed error state, `dispose` |
| `lib/features/home/presentation/pages/home_page.dart` | 003, 004 | Streaming UI, stop control, typed-error action; now hosts `VoiceController`, Talk/Stop toggle, lifecycle mic release |
| `lib/features/settings/presentation/pages/settings_page.dart` | 003, 005 | Disposes the provider it creates; real persisted Wake Word and Speak Replies switches |
| `lib/core/voice/config/voice_config.dart` | 005 | Added wake phrases, wake timings, and the opt-in default |
| `lib/core/voice/services/speech_service.dart` | 005 | Added vendor-neutral `SpeechListenMode` |
| `lib/core/voice/services/device_speech_service.dart` | 005 | Maps listen mode to the command/dictation engines |
| `lib/core/voice/services/voice_controller.dart` | 005 | Added the `VoiceMode` wake-watch state machine, suspend/resume, and preference restore |
| `lib/core/services/secure_storage_service.dart` | 005 | Persists the Wake Word and Speak Replies preferences |
| `lib/features/kitten/presentation/widgets/kitten_avatar.dart` | 006 | Replaced the emoji circle with a mood-aware procedural cat |
| `lib/core/ai/prompts/kitten_system_prompt.dart` | 006 | Added `build()` to append the live mood below the scope constraints |
| `lib/core/ai/services/chat_service.dart` | 006 | Owns `PersonalityService`, feeds it each turn, and uses its prompt |
| `lib/features/home/presentation/pages/home_page.dart` | 006 | Passes the mood to the avatar and ages it on a ticker |
| `lib/core/ai/models/chat_message.dart` | 008 | Carries an optional image and emits multimodal content parts |
| `lib/core/ai/models/chat_request.dart` | 008 | Added `withModel` so a turn can be rerouted to the vision model |
| `lib/core/ai/services/chat_service.dart` | 008 | `sendMessageWithImage` streams a vision turn and trims old screenshots |
| `lib/core/ai/config/ai_config.dart` | 008 | Added the vision model id and the image size guard |
| `lib/features/home/presentation/pages/home_page.dart` | 008 | "Read my screen" button and the one-time privacy dialog |
| `lib/features/home/presentation/widgets/chat_bubble.dart` | 008 | Marks messages that carried a screenshot |
| `lib/core/services/secure_storage_service.dart` | 008 | Persists the privacy-note flag |
| `android/app/src/main/kotlin/com/example/kitten/MainActivity.kt` | 008 | Added the `kitten/screen_capture` channel and consent hand-off |
| `lib/core/ai/services/chat_service.dart` | 007 | Accepts a `contextProvider` and appends it to the system prompt |
| `lib/features/home/presentation/pages/home_page.dart` | 007 | Owns the awareness controller, shows the last-app hint, suspends polling on background |
| `lib/features/settings/presentation/pages/settings_page.dart` | 007 | Real App Awareness switch, Usage Access status, and last-app row |
| `lib/core/services/secure_storage_service.dart` | 007 | Persists the app-awareness preference |
| `android/app/src/main/kotlin/com/example/kitten/MainActivity.kt` | 007 | Hosts the `kitten/app_awareness` method channel |
| `test/widget_test.dart` | 007 | Mocks the awareness channel so Settings does not hang waiting on it |
| `android/app/src/main/AndroidManifest.xml` | 004, 007 | Added `RECORD_AUDIO` and speech/TTS `<queries>` visibility; then `PACKAGE_USAGE_STATS` |
| `test/widget_test.dart` | 002, 003 | Covers chat input, settings navigation, AI settings section |

## Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| `flutter` (SDK) | 3.47.5 | Core framework |
| `cupertino_icons` | ^1.0.8 | iOS-style icons |
| `http` | ^1.6.0 | Groq HTTP client including streamed/SSE responses |
| `flutter_secure_storage` | ^11.2.0 | Encrypted local API key storage |
| `speech_to_text` | ^7.5.0 | On-device speech recognition for voice input |
| `flutter_tts` | ^4.2.5 | Speech synthesis for spoken replies |
| `flutter_test` (dev) | SDK | Widget & unit testing |
| `integration_test` (dev) | SDK | Drives the app on a real device to verify platform behaviour |
| `flutter_lints` (dev) | ^6.0.0 | Static analysis rules |

## Permissions

**Declared Android permissions:**

| Permission | Task | Purpose |
|------------|------|---------|
| `android.permission.RECORD_AUDIO` | 004 | Capturing the user's voice for speech recognition |
| `android.permission.PACKAGE_USAGE_STATS` | 007 | Reading which app the user was last using |
| `android.permission.FOREGROUND_SERVICE` | 008 | Hosting the short-lived capture service |
| `android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION` | 008 | Required on Android 14+ to project the screen at all |
| `android.permission.POST_NOTIFICATIONS` | 008 | Declared for the capture notice; not requested at runtime yet |

`RECORD_AUDIO` is requested at runtime when the user first taps Talk; denied or unavailable
speech input degrades the app to text-only mode rather than failing.

`PACKAGE_USAGE_STATS` is a **special** permission: it cannot be granted by a runtime dialog. The
user must enable it in Settings -> Special app access -> Usage access, so the app deep-links
there and never pretends to work without it. `QUERY_ALL_PACKAGES` is deliberately **not**
requested.

## Testing

| Stage | `flutter analyze` | `flutter test` |
|-------|-------------------|----------------|
| Task 001 | 0 issues | — |
| Task 002 | 0 issues | 1/1 passed |
| Task 003 (original) | 0 issues | 26/26 passed |
| Task 003 (closure) | 0 issues | 42/42 passed |
| Task 004 | 0 issues | 61/61 passed |
| Task 005 | 0 issues | 81/81 passed |
| Task 006 | 0 issues | 98/98 passed |
| Task 007 | 0 issues | 123/123 passed (+ 3/3 on-device) |
| Task 008 | **0 issues** | **143/143 passed** (+ 3/3 on-device, 1 skipped) |

Task 008 suite breakdown (13 suites total):

- `ai_models_test.dart`: 7
- `chat_service_test.dart`: 13
- `groq_provider_test.dart`: 17
- `secure_storage_service_test.dart`: 5
- `voice_controller_test.dart`: 22
- `voice_text_cleaner_test.dart`: 7
- `wake_word_matcher_test.dart`: 10
- `personality_service_test.dart`: 13
- `kitten_avatar_test.dart`: 3
- `foreground_app_test.dart`: 6
- `app_awareness_controller_test.dart`: 17
- `screen_understanding_controller_test.dart`: 13
- `widget_test.dart`: 1

Plus on-device suites: `integration_test/app_awareness_test.dart` (3 tests, requires Usage
Access) and `integration_test/screen_understanding_test.dart` (4 tests, requires the
`PROJECT_MEDIA` app-op; the live vision round-trip skips without a Groq API key).
Note that `flutter test integration_test/...` **uninstalls** the app when it finishes, which also
clears the granted app-op — so install and grant immediately before each run.

## Security Review Result

- No hardcoded secrets found; keys live only in encrypted storage and are masked in the UI.
- Keys are never logged in `debugPrint`, `print`, or exception tracebacks.
- Streaming and voice error paths route through the same sanitized `AiException` messages,
  so no raw provider payload or credential reaches the user.
- The microphone is opened only when the user starts a voice session, and is released when
  the session stops or the app leaves the foreground.
- App awareness reads only *which* app is in the foreground (a package id), never its contents,
  and only while the user has explicitly granted Usage Access and Kitten is on screen.

## Known Problems & Limitations

- **Real voice I/O is unverified.** The emulator has no microphone, so spoken input and
  audible output still need testing on a physical Android device.
- **ChatService lifecycle:** still owned by `HomePage` (now via `VoiceController`), so
  conversation history is lost if the home page state is rebuilt. Should be hoisted to an
  app-scoped instance when background features arrive.
- **Session memory:** conversation is in-memory only; no persistence across restarts.
- **Wake-word accuracy:** matching is text-based on the recogniser's transcript, so it only
  fires once the engine returns the phrase. It trades some latency and battery for needing no
  third-party account, and can mis-hear close phrases.
- **No background wake word:** listening stops when the app leaves the foreground; Task 012
  covers a foreground service and persistent notification.
- **`handsFree` is not exposed in Settings** — it is configurable on `VoiceController` only.
- **Avatar visual verification is limited to the web preview.** Every state/mood combination is
  asserted to paint without error, but only the curious and sleepy moods have been looked at.
  There are no golden-image tests, so pixel-level regressions would not be caught.
- **Mood is session-only:** it is derived from the live conversation and is not persisted, so
  Kitten always starts curious.
- **App awareness is coarse:** it reports only the single most recently used *other* app within
  a 10-minute window, and only on Android. It cannot tell what the user is doing *inside* that
  app — that is Task 008, and it explicitly does not claim otherwise.
- **App labels depend on Android's package visibility.** Without `QUERY_ALL_PACKAGES`, many
  labels are withheld, so names fall back to a readable derivation of the package id
  (`com.spotify.music` shows as "Music").
- **No awareness while backgrounded:** polling stops when the app leaves the foreground, so
  awareness resumes with whatever it last saw rather than tracking continuously.
- **The vision model is only exercised on a machine with an API key.** On this emulator the
  capture path is fully verified, but nothing has yet confirmed what `qwen/qwen3.8-27b` says
  about a real screenshot.
- **Consent is asked every single time.** That is deliberate for privacy, but it means the
  feature never becomes one-tap in practice; Android's own "remember this decision" option is
  the only shortcut.
- **`POST_NOTIFICATIONS` is declared but never requested**, so on Android 13+ the capture
  notice may not be visible even though the foreground service is running.
- **A screenshot stays in the conversation.** Only the newest one is re-sent to the model, but
  older screenshots remain in memory and in the visible chat until the conversation is cleared.
- **No OCR or accessibility fallback:** if the vision model cannot read something (small text,
  handwriting), Kitten has no second path to the screen's content.
- **Application ID & Signing:** still `com.example.kitten` with debug signing.

## Decisions

- **Architecture:** decoupled `AiProvider`, `SpeechService`, and `TtsService` interfaces keep
  vendor plugins out of business and presentation logic.
- **Default Model:** `openai/gpt-oss-20b`, with `openai/gpt-oss-safeguard-20b` selectable.
- **Vendor independence:** vendor-specific request/response shapes (e.g. `fromGroqJson`) are
  named for the vendor rather than implying a universal format.
- **Storage:** `flutter_secure_storage` v11 with Android Keystore encryption, `minSdk = 24`.
- **System Prompt:** explicitly bounds Kitten's persona to avoid hallucinating unbuilt
  capabilities.
- **Streaming:** responses stream via SSE by default; `sendMessage` remains a fallback.
- **Error Handling:** UI decisions read the typed `AiErrorType`, never message text.
- **Voice loop:** hands-free by default — the microphone reopens after each reply, with
  "no speech" treated as normal and only blocking problems ending the session.
- **Spoken output:** replies are read aloud automatically, with stage directions and emoji
  stripped first so Kitten sounds natural.
- **Wake word:** always-on speech-to-text rather than a bundled wake-word engine — no
  third-party account, at the cost of some battery. Off by default, foreground only, and the
  phrase's remainder is treated as the question when present.
- **Avatar:** drawn procedurally with `CustomPainter` instead of Rive/Lottie assets, so it needs
  no artwork, scales to any size, and stays readable in diffs.
- **Personality:** mood is computed by explicit, testable rules over the conversation rather
  than by asking the model how it feels, and is appended to the system prompt beneath the scope
  constraints.
- **App awareness:** Android `UsageStats` through a small native channel and the special
  `GET_USAGE_STATS` app-op, rather than `QUERY_ALL_PACKAGES`. It reports the most recent *other*
  app, is strictly opt-in, and stops when the permission or the foreground state is lost.
- **Platform verification:** platform-dependent behaviour is verified with on-device
  `integration_test` suites rather than by tapping guessed screen coordinates.
- **Concern separation:** app awareness owns the knowledge, `ChatService` merely accepts a
  context string through a callback, so the AI layer stays unaware of Android.
- **Screen understanding:** MediaProjection behind per-capture consent and a short-lived
  mediaProjection foreground service, rather than an AccessibilityService. It is strictly
  one-shot and user-initiated, and the pixels go to Groq's multimodal model as an inline data
  URL — the trade accepted in exchange for real visual understanding.
- **Vision is a separate model:** `qwen/qwen3.8-27b` handles image turns while the user's
  chosen text model stays on every other turn, so a text model never has to be multimodal.

## Next Task

**Task 009 — Assistant tool/function system.**

## Task History

### Task 001
- **Status:** COMPLETED · **Date:** 2026-09-20
- **Summary:** Inspected the Flutter project, verified toolchain versions, reviewed
  configuration, confirmed a clean template, created `PROJECT_STATUS.md`.
- **Result:** PASS

### Task 002
- **Status:** COMPLETED · **Date:** 2026-09-20
- **Summary:** Replaced the counter demo with the Kitten AI foundation: feature-based
  architecture, home screen, animated avatar, `AssistantState`, settings placeholder,
  Material 3 theming.
- **Result:** PASS

### Task 003
- **Status:** COMPLETED · **Date:** 2026-09-20
- **Summary:** Built the Groq AI provider foundation — `AiProvider` abstraction, isolated
  `GroqProvider`, secure storage with masking, centralized config and personality prompt,
  `ChatService`, chat UI, and a settings screen with connection testing.
- **Testing:** `flutter analyze` — 0 issues; `flutter test` — 26/26 passed
- **Result:** PASS

### Task 003 — Closure
- **Status:** COMPLETED · **Date:** 2026-09-20
- **Summary:** Initialized Git, corrected documentation drift, replaced brittle error
  string-matching with typed error categories, added end-to-end SSE streaming with a stop
  control, and added a proper disposal chain.
- **Testing:** `flutter analyze` — 0 issues; `flutter test` — 42/42 passed
- **Result:** PASS

### Task 004
- **Status:** COMPLETED · **Date:** 2026-09-20
- **Summary:** Implemented hands-free voice input and output. Added abstract
  `SpeechService`/`TtsService` contracts with device implementations, a `VoiceController`
  orchestrating the listen -> chat -> speak loop, speech-safe text cleaning, Android
  microphone permission and package visibility, and Talk/Stop wiring with foreground
  lifecycle handling on the home page.
- **Files created:** 7 (voice config, services, controller, text cleaner) plus 2 test files
- **Files modified:** `pubspec.yaml`, `android/app/src/main/AndroidManifest.xml`,
  `lib/features/home/presentation/pages/home_page.dart`
- **Dependencies added:** `speech_to_text: ^7.5.0`, `flutter_tts: ^4.2.5`
- **Testing:** `flutter analyze` — 0 issues; `flutter test` — 61/61 passed
- **On-device:** verified on Pixel_7 (Android 17 / API 37) — build, install, plugin
  registration, permission grant, recognizer start, and automatic no-speech retry
- **Result:** PASS (real spoken input/output pending a physical device)

### Task 005
- **Status:** COMPLETED · **Date:** 2026-09-20
- **Summary:** Implemented "Hey Kitten" activation. Added a pure wake-phrase matcher with
  remainder extraction, a `VoiceMode` state machine in `VoiceController` coordinating the
  wake watch with the conversation loop, a vendor-neutral listen mode so wake spotting uses
  the command-tuned engine, opt-in persisted Wake Word and Speak Replies switches in
  Settings, and foreground-only suspend/resume of the microphone.
- **Files created:** `wake_word_matcher.dart` plus its test file
- **Files modified:** `voice_config.dart`, `speech_service.dart`, `device_speech_service.dart`,
  `voice_controller.dart`, `secure_storage_service.dart`, `settings_page.dart`, `home_page.dart`
- **Dependencies added:** none (reuses the Task 004 speech plugin)
- **Testing:** `flutter analyze` — 0 issues; `flutter test` — 81/81 passed
- **On-device:** verified on Pixel_7 (Android 17 / API 37) — off by default, switch enables
  recognition, preference survives restart, switch disables it again
- **Result:** PASS (spoken wake phrase pending a physical device)

### Task 006
- **Status:** COMPLETED · **Date:** 2026-09-20
- **Summary:** Replaced the emoji avatar with a procedurally drawn, mood-aware character. Added
  the `KittenMood` model and a rule-based `PersonalityService`, appended the live mood to the
  system prompt beneath the scope constraints, and gave `ChatService` ownership of the
  personality so every turn updates it. Added idle behaviours (breathing, blinking, ear
  twitches, swaying tail) and a doze-off ticker on the home page.
- **Files created:** `kitten_mood.dart`, `personality_service.dart`, plus 2 test files
- **Files modified:** `kitten_avatar.dart`, `kitten_system_prompt.dart`, `chat_service.dart`,
  `home_page.dart`
- **Dependencies added:** none
- **Testing:** `flutter analyze` — 0 issues; `flutter test` — 98/98 passed
- **Visual check:** web preview confirmed the cat renders correctly and that the sleepy mood
  engages after the idle threshold; a whisker geometry bug was found and fixed this way
- **Result:** PASS

### Task 007
- **Status:** COMPLETED · **Date:** 2026-09-20
- **Summary:** Implemented Android app-awareness. Added a native `kitten/app_awareness` method
  channel backed by `UsageStatsManager`, an abstract `AppAwarenessService` with a method-channel
  implementation, and an `AppAwarenessController` that gates everything on the special Usage
  Access permission and polls the foreground app. `ChatService` gained a `contextProvider` so the
  last-used app is folded into the system prompt, and the home screen and Settings both surface
  it with a real switch and a permission action.
- **Files created:** 4 (model, contract, implementation, controller), 2 unit test files, plus an
  on-device integration test
- **Files modified:** `MainActivity.kt`, `AndroidManifest.xml`, `chat_service.dart`,
  `secure_storage_service.dart`, `home_page.dart`, `settings_page.dart`, `widget_test.dart`,
  `pubspec.yaml`
- **Dependencies added:** `integration_test` (dev, SDK)
- **Testing:** `flutter analyze` — 0 issues; `flutter test` — 123/123 passed;
  `flutter test integration_test/...` — 3/3 passed on the emulator
- **On-device:** detected `com.android.chrome` as "Chrome"; the Settings switch enabled
  awareness and the last-app row appeared; the screen showed `Granted` before any interaction
- **Bugs found and fixed during verification:** the controller never checked the permission until
  the switch was flipped, so Settings showed "grant Usage access" even when it was already
  granted; and gating the whole Settings load on that probe made the screen hang in widget
  tests, so the probe now reports in asynchronously
- **Result:** PASS

### Task 008
- **Status:** COMPLETED · **Date:** 2026-09-20
- **Summary:** Implemented on-demand screen understanding. Added a one-shot MediaProjection
  capture service driven by Android's consent dialog, an abstract `ScreenCaptureService` with a
  method-channel implementation, and a `ScreenUnderstandingController` that captures once and
  routes the turn to a vision model. `ChatMessage` gained multimodal content parts and
  `ChatRequest.withModel` the reroute, so a screenshot arrives as an inline data URL, streams
  into the normal conversation, and is only ever replayed while it is the newest image.
- **Files created:** 4 (config, contract, implementation, controller), 1 unit test file, 1
  integration test, 1 Kotlin service
- **Files modified:** `chat_message.dart`, `chat_request.dart`, `chat_service.dart`,
  `ai_config.dart`, `secure_storage_service.dart`, `home_page.dart`, `chat_bubble.dart`,
  `MainActivity.kt`, `AndroidManifest.xml`
- **Dependencies added:** none
- **Testing:** `flutter analyze` — 0 issues; `flutter test` — 143/143 passed;
  `flutter test integration_test/...` — 3/3 passed on the emulator, 1 skipped (no API key)
- **On-device:** captured a real JPEG of 31,740 bytes at 1080x2400; the privacy note appeared
  before the first read and Cancel captured nothing; the turn was confirmed to request the
  vision model rather than the text model
- **Bugs found and fixed during verification:** a missing `MediaProjection.Callback` crashed the
  whole app on the first capture (and the unwrapped capture loop let one exception do it);
  `densityDpi` was left at 0 so the projection refused to start; the first image callback was
  treated as a frame and gave up too early; imports were dropped in a rewrite; and the Dart side
  asked for a `String` where the platform sends bytes
- **Result:** PASS (live vision answer pending a configured API key)
