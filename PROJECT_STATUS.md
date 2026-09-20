# Kitten AI — Project Status

## Project

- **Project name:** kitten
- **Framework:** Flutter 3.47.5 (stable channel)
- **Target platform:** Android (primary), with iOS/Web/Windows/macOS/Linux scaffolding present
- **Version control:** Git repository. Baseline `492be59`, Task 003 closure `4ed421c`.
- **Current development stage:** Task 004 complete — hands-free voice conversation. Kitten listens, answers, and speaks its replies aloud, cycling automatically between turns.

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
4. **Task 004 — Voice Input / Output** — hands-free voice conversation described below.

## Current Task

**Task 004 — Voice Input / Output**
Status: **COMPLETED**

### What was built

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

Awaiting instructions for Task 005.

**Recorded decision for Task 005:** the "Hey Kitten" wake word will use always-on
speech-to-text (reusing this task's `SpeechService`), not an on-device wake-word engine.

## Features Planned

The following are planned but **NOT yet implemented**:

- "Hey Kitten" wake word detection (always-on STT)
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
| `test/core/ai/ai_models_test.dart` | 003 | AI models, exceptions, prompts, config tests |
| `test/core/ai/groq_provider_test.dart` | 003 | Provider HTTP + SSE streaming tests |
| `test/core/ai/chat_service_test.dart` | 003 | Chat streaming, cancellation, error classification |
| `test/core/services/secure_storage_service_test.dart` | 003 | Key masking and storage abstraction tests |
| `test/core/voice/voice_controller_test.dart` | 004 | Hands-free loop, degradation, and lifecycle tests |
| `test/core/voice/voice_text_cleaner_test.dart` | 004 | Speech text cleaning tests |

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
| `lib/features/settings/presentation/pages/settings_page.dart` | 003 closure | Disposes the provider it creates |
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
| Task 004 | **0 issues** | **61/61 passed** |

Task 004 suite breakdown (7 suites total):

- `ai_models_test.dart`: 7
- `chat_service_test.dart`: 12
- `groq_provider_test.dart`: 17
- `secure_storage_service_test.dart`: 5
- `voice_controller_test.dart`: 12
- `voice_text_cleaner_test.dart`: 7
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
- **Voice settings UI:** `handsFree` and `speakReplies` are configurable on
  `VoiceController` but not yet exposed as Settings switches.
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

## Next Task

**Task 005 — "Hey Kitten" activation (always-on speech-to-text).**

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
