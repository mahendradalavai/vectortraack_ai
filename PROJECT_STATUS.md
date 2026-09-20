# Kitten AI — Project Status

## Project

- **Project name:** kitten
- **Framework:** Flutter 3.47.5 (stable channel)
- **Target platform:** Android (primary), with iOS/Web/Windows/macOS/Linux scaffolding present
- **Version control:** Git repository. Baseline `492be59`, Task 003 closure `4ed421c`.
- **Current development stage:** Task 006 complete — Kitten is now a procedurally drawn character with an evolving mood that colours both its expression and its replies, plus idle behaviours (breathing, blinking, ear twitches, a swaying tail) and dozing off when left alone.

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

## Current Task

**Task 006 — Kitten Animation / Personality System**
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

Awaiting instructions for Task 007 (Android app-awareness).

## Features Planned

The following are planned but **NOT yet implemented**:

- Floating kitten overlay
- Background listening / service
- App detection / awareness
- Context-aware questions
- Screen capture / understanding
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
| `android/app/src/main/AndroidManifest.xml` | 004 | Added `RECORD_AUDIO` and speech/TTS `<queries>` visibility |
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
| `flutter_lints` (dev) | ^6.0.0 | Static analysis rules |

## Permissions

**Declared Android permissions:**

| Permission | Task | Purpose |
|------------|------|---------|
| `android.permission.RECORD_AUDIO` | 004 | Capturing the user's voice for speech recognition |

Requested at runtime when the user first taps Talk; denied or unavailable speech input
degrades the app to text-only mode rather than failing.

## Testing

| Stage | `flutter analyze` | `flutter test` |
|-------|-------------------|----------------|
| Task 001 | 0 issues | — |
| Task 002 | 0 issues | 1/1 passed |
| Task 003 (original) | 0 issues | 26/26 passed |
| Task 003 (closure) | 0 issues | 42/42 passed |
| Task 004 | 0 issues | 61/61 passed |
| Task 005 | 0 issues | 81/81 passed |
| Task 006 | **0 issues** | **98/98 passed** |

Task 006 suite breakdown (10 suites total):

- `ai_models_test.dart`: 7
- `chat_service_test.dart`: 13
- `groq_provider_test.dart`: 17
- `secure_storage_service_test.dart`: 5
- `voice_controller_test.dart`: 22
- `voice_text_cleaner_test.dart`: 7
- `wake_word_matcher_test.dart`: 10
- `personality_service_test.dart`: 13
- `kitten_avatar_test.dart`: 3
- `widget_test.dart`: 1

## Security Review Result

- No hardcoded secrets found; keys live only in encrypted storage and are masked in the UI.
- Keys are never logged in `debugPrint`, `print`, or exception tracebacks.
- Streaming and voice error paths route through the same sanitized `AiException` messages,
  so no raw provider payload or credential reaches the user.
- The microphone is opened only when the user starts a voice session, and is released when
  the session stops or the app leaves the foreground.

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

## Next Task

**Task 007 — Android app-awareness.**

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
