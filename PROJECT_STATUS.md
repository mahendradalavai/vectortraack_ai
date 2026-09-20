# Kitten AI — Project Status

## Project

- **Project name:** kitten
- **Framework:** Flutter 3.47.5 (stable channel)
- **Target platform:** Android (primary), with iOS/Web/Windows/macOS/Linux scaffolding present
- **Version control:** Git repository initialized (Task 003 closure). Baseline import commit `492be59`.
- **Current development stage:** Task 003 complete and closed out — Groq AI provider architecture, secure encrypted key storage, personality prompt, token-streaming text conversation UI, settings screen with connection testing, typed error handling, and 42 passing tests.

## Environment

- **Flutter version:** 3.47.5 (stable) — revision 6a19cca564 (2026-09-17)
- **Dart version:** 3.13.4 (stable) — windows_x64
- **DevTools version:** 2.60.0
- **Android configuration:**
  - Namespace / Application ID: `com.example.kitten`
  - compileSdk: Flutter default (`flutter.compileSdkVersion`)
  - minSdk: `24` (updated for `flutter_secure_storage` v11 modern encryption compatibility)
  - targetSdk: Flutter default (`flutter.targetSdkVersion`)
  - Java compatibility: 17
  - Kotlin JVM target: 17
  - Build system: Gradle (Kotlin DSL)
  - AndroidX: enabled
  - Signing: debug keys only (no release signing configured)
- **Other relevant environment information:**
  - OS: Windows (x64)
  - Analysis: `flutter_lints` v6.0.0 with platform directories excluded
  - All platform targets scaffolded: android, ios, web, windows, macos, linux

## Completed Tasks

1. **Task 001 — Project Initialization & Status System**
   - Inspected full project structure
   - Created `PROJECT_STATUS.md`
   - Verified project baseline with `flutter analyze` (0 issues)

2. **Task 002 — Create the Kitten App Foundation**
   - Replaced default counter demo with Kitten AI architecture
   - Created feature-based folder structure under `lib/`
   - Built home screen, kitten avatar widget, settings placeholder, assistant state model
   - Material 3 with dark mode support
   - All validation passed: `flutter analyze` (0 issues), `flutter test` (1/1 passed)

3. **Task 003 — Groq AI Provider Foundation**
   - Implemented pluggable `AiProvider` abstraction and Groq HTTP provider
   - Added secure encrypted key storage using `flutter_secure_storage` with key masking
   - Centralized model configuration (`openai/gpt-oss-20b` default, `openai/gpt-oss-safeguard-20b` option)
   - Created centralized Kitten personality prompt with strict current-scope constraints
   - Built text conversation UI on home screen synced with `AssistantState` (idle -> thinking -> idle)
   - Expanded Settings screen with API key management, model selection, and connection testing
   - Implemented user-safe error handling and comprehensive mock-based test suite
   - Conducted security review: verified zero hardcoded secrets

## Current Task

**Task 003 — Groq AI Provider Foundation**
Status: **COMPLETED (closed out)**

### Closure work (Task 003 finalization)

The original 003 delivery was complete in scope but had real gaps. These were closed:

1. **Version control baseline** — initialized a Git repository (`git init`) and imported the
   full 001–003 state as the baseline commit. `.freebuff/` tooling state is now ignored.
2. **Documentation drift fixed** — this document previously listed `llama-3.3-70b-versatile`
   and `llama-3.1-8b-instant`, which were never the shipped defaults. The real, code-verified
   models are `openai/gpt-oss-20b` (default) and `openai/gpt-oss-safeguard-20b`.
3. **Structured error handling** — `ChatService` now exposes the typed `AiErrorType`
   (`lastErrorType`, `lastErrorRequiresSettings`) instead of discarding it. `HomePage` no
   longer decides whether to offer the Settings shortcut by string-matching
   `lastError.contains('Settings')`.
4. **Token streaming** — Groq's server-sent-events streaming is now supported end to end:
   `AiProvider.streamMessage`, SSE parsing in `GroqProvider`, incremental accumulation in
   `ChatService`, and a live-updating bubble with a stop control in `HomePage`.
5. **Correctness cleanups** — added `AiConfig.groqModelsEndpoint` and `connectionTestTimeout`
   (removing an inline URL), and introduced a real dispose chain
   (`AiProvider.dispose` -> `GroqProvider.dispose` -> `ChatService.dispose`, plus
   `SettingsPage` disposing the provider it creates) so the HTTP client is closed.

## Pending Tasks

Awaiting project manager instructions for Task 004 (voice input/output).

**Recorded decision for Task 005:** the "Hey Kitten" wake word will be implemented with
always-on speech-to-text (reusing the Task 004 STT plugin), not an on-device wake-word engine.

## Features Planned

The following features are planned but **NOT yet implemented**:

- Voice input / STT (speech-to-text)
- Voice output / TTS (text-to-speech)
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
| `lib/app/app.dart` | 002 | Root `KittenApp` MaterialApp widget |
| `lib/app/theme/app_theme.dart` | 002 | Material 3 light/dark theme definitions |
| `lib/core/constants/app_constants.dart` | 002 | Centralized app-wide string constants |
| `lib/core/models/assistant_state.dart` | 002 | `AssistantState` enum (idle, listening, thinking, speaking) |
| `lib/features/home/presentation/pages/home_page.dart` | 002 | Main home screen with kitten, greeting, mic button, status |
| `lib/features/kitten/presentation/widgets/kitten_avatar.dart` | 002 | Reusable animated kitten avatar placeholder |
| `lib/features/settings/presentation/pages/settings_page.dart` | 002 | Settings screen with placeholder sections |
| `lib/shared/widgets/assistant_status_indicator.dart` | 002 | Status chip displaying current `AssistantState` |
| `lib/core/ai/models/ai_exception.dart` | 003 | User-safe error model with sanitized error categories |
| `lib/core/ai/models/chat_message.dart` | 003 | Conversation message model supporting system, user, and assistant roles |
| `lib/core/ai/models/chat_request.dart` | 003 | Provider-agnostic chat completion request payload (supports `stream`) |
| `lib/core/ai/models/chat_response.dart` | 003 | Provider-agnostic completion response model |
| `lib/core/ai/providers/ai_provider.dart` | 003 | Abstract AI provider interface (`sendMessage`, `streamMessage`, `dispose`) |
| `lib/core/ai/providers/groq_provider.dart` | 003 | Concrete Groq HTTP provider with SSE streaming (isolated networking) |
| `lib/core/ai/config/ai_config.dart` | 003 | Centralized model identifiers, endpoints, and timeouts |
| `lib/core/ai/prompts/kitten_system_prompt.dart` | 003 | Centralized personality prompt with current scope constraints |
| `lib/core/ai/services/chat_service.dart` | 003 | Conversation coordinator: history, system prompt, streaming, state transitions |
| `lib/core/services/secure_storage_service.dart` | 003 | Encrypted storage service wrapper with API key masking |
| `lib/features/home/presentation/widgets/chat_bubble.dart` | 003 | Styled conversation bubble widget for user and Kitten messages |
| `test/core/ai/ai_models_test.dart` | 003 | Unit tests for AI models, exceptions, prompts, and config |
| `test/core/ai/groq_provider_test.dart` | 003 | Unit tests for Groq provider HTTP handling, SSE streaming, auth, error mapping |
| `test/core/ai/chat_service_test.dart` | 003 | Unit tests for ChatService streaming, cancellation, state, and error classification |
| `test/core/services/secure_storage_service_test.dart` | 003 | Unit tests for key masking and storage abstraction |

## Files Modified

| File | Task | Change |
|------|------|--------|
| `lib/main.dart` | 002 | Replaced counter-demo template with minimal entry point that launches `KittenApp` |
| `pubspec.yaml` | 003 | Added `http: ^1.6.0` and `flutter_secure_storage: ^11.2.0` |
| `android/app/build.gradle.kts` | 003 | Set `minSdk = 24` for modern encryption support in `flutter_secure_storage` |
| `lib/core/ai/config/ai_config.dart` | 003 closure | Added `groqModelsEndpoint` and `connectionTestTimeout` |
| `lib/core/ai/models/chat_request.dart` | 003 closure | Added `stream` flag to `toJson` |
| `lib/core/ai/providers/ai_provider.dart` | 003 closure | Added `streamMessage` (with default fallback) and `dispose` |
| `lib/core/ai/providers/groq_provider.dart` | 003 closure | Added SSE streaming, shared error mapping, model/key resolution helpers, `dispose` |
| `lib/core/ai/services/chat_service.dart` | 003 closure | Added streaming path, cancellation, typed error state, settings-action hint, `dispose` |
| `lib/features/home/presentation/pages/home_page.dart` | 003 closure | Streaming bubble, stop control, smarter scroll, typed-error Settings action |
| `lib/features/settings/presentation/pages/settings_page.dart` | 003 closure | Disposes the provider it creates |
| `.gitignore` | 003 closure | Ignores `.freebuff/` tooling state |
| `test/core/ai/groq_provider_test.dart` | 003 closure | Added 8 streaming/SSE tests |
| `test/core/ai/chat_service_test.dart` | 003 closure | Added streaming, cancellation, and error-classification tests |
| `test/widget_test.dart` | 002, 003 | Expanded to test chat text input, settings navigation, and AI settings section |

## Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| `flutter` (SDK) | 3.47.5 | Core framework |
| `cupertino_icons` | ^1.0.8 | iOS-style icons |
| `http` | ^1.6.0 | Isolated HTTP client for Groq (including streamed/SSE responses) |
| `flutter_secure_storage` | ^11.2.0 | Encrypted local key storage on Android (EncryptedSharedPreferences / AES-GCM) |
| `flutter_test` (dev) | SDK | Widget & unit testing |
| `flutter_lints` (dev) | ^6.0.0 | Static analysis rules |

## Permissions

**Currently declared Android permissions:** None added.

Task 003 only requires standard internet access (granted by default in Flutter Android debug builds; no dangerous permissions required). Voice (Task 004) will introduce `RECORD_AUDIO`.

## Testing

### Task 001
- `flutter analyze` — 0 issues found

### Task 002
- `flutter analyze` — 0 issues found
- `flutter test` — 1/1 passed

### Task 003
- `flutter analyze` — **0 issues found** (clean)
- `flutter test` — **26/26 passed** (original delivery)

### Task 003 closure
- `flutter analyze` — **0 issues found** (clean)
- `flutter test` — **42/42 passed** across 5 suites:
  - `ai_models_test.dart`: 7 tests
  - `chat_service_test.dart`: 12 tests (streaming, cancellation, typed error classification)
  - `groq_provider_test.dart`: 17 tests (HTTP handling plus SSE frame parsing, split frames, mid-stream errors)
  - `secure_storage_service_test.dart`: 5 tests
  - `widget_test.dart`: 1 test

## Security Review Result

- Automated ripgrep scan across `lib/` and `test/` for credential patterns (`sk-`, `gsk_`, `api_key`, `Authorization`, `Bearer`):
  - No real API keys or hardcoded secrets found.
  - All occurrences are localized to placeholder UI strings, unit test assertions, storage keys, or dynamic HTTP headers.
- Keys are never logged in `debugPrint`, `print`, or exception tracebacks.
- Keys are securely masked in the UI: `****************abcd` (only last 4 characters visible).
- Streaming error frames are mapped through the same sanitized `AiException` path, so no raw provider payload is surfaced to the user.

## Known Problems & Limitations

- **Voice/Microphone:** Voice input and TTS are not yet implemented (scheduled for future tasks).
- **Session Memory:** Conversation is maintained in-memory for the active session; persistence across app restarts is not yet implemented.
- **ChatService lifecycle:** `ChatService` is owned by `HomePage` state rather than being app-scoped, so conversation history is lost if that widget is rebuilt from scratch. This should be hoisted to an app-level instance when voice/background features need shared access.
- **Application ID & Signing:** Still uses debug configuration (`com.example.kitten`).

## Decisions

- **Architecture:** Decoupled `AiProvider` interface allows swapping Groq for Gemini, OpenAI, or local models without modifying UI logic.
- **Default Model:** `openai/gpt-oss-20b` (verified in `AiConfig`), with `openai/gpt-oss-safeguard-20b` available in settings.
- **Storage:** `flutter_secure_storage` v11 with modern Android Keystore encryption (`AES_GCM_NoPadding`), requiring `minSdk = 24`.
- **System Prompt:** Explicitly bounds Kitten's persona to avoid hallucinating unbuilt capabilities (phone control, alarms, screen observation).
- **State Flow:** User message triggers `AssistantState.thinking` (animating avatar), then reverts to `AssistantState.idle` upon completion or safe error display.
- **Streaming:** Responses are streamed by default via SSE; `sendMessage` is retained as a non-streaming fallback for providers that cannot stream.
- **Error Handling:** Errors are classified by the typed `AiErrorType` enum; UI decisions (such as offering the Settings shortcut) read the type rather than matching message text.

## Next Task

**Task 004 — Voice input/output.**

## Task History

### Task 001
- **Status:** COMPLETED
- **Date:** 2026-09-20
- **Summary:** Inspected the existing Flutter project structure, verified Flutter/Dart versions, reviewed all configuration files, confirmed clean template. Created `PROJECT_STATUS.md`.
- **Result:** PASS

### Task 002
- **Status:** COMPLETED
- **Date:** 2026-09-20
- **Summary:** Replaced default counter demo with Kitten AI app foundation. Created feature-based architecture under `lib/` with root app widget, home screen, animated `KittenAvatar`, `AssistantState` model, and settings screen placeholder.
- **Result:** PASS

### Task 003
- **Status:** COMPLETED
- **Date:** 2026-09-20
- **Summary:** Implemented Groq AI Provider Foundation. Created `AiProvider` abstraction, isolated `GroqProvider`, `ChatRequest`, `ChatResponse`, `AiException`, `SecureStorageService` with key masking, `AiConfig`, `KittenSystemPrompt`, `ChatService`, and `ChatBubble`. Integrated text chat into `HomePage` with thinking animation sync. Expanded `SettingsPage` with Groq API key entry, masked view, key removal, model dropdown, and connection testing.
- **Files created:** 14 new files (AI models, providers, services, prompts, widgets, and tests)
- **Files modified:** `pubspec.yaml`, `android/app/build.gradle.kts`, `lib/features/home/presentation/pages/home_page.dart`, `lib/features/settings/presentation/pages/settings_page.dart`, `test/widget_test.dart`
- **Dependencies added:** `http: ^1.6.0`, `flutter_secure_storage: ^11.2.0`
- **Testing:** `flutter analyze` — 0 issues; `flutter test` — 26/26 passed
- **Result:** PASS

### Task 003 — Closure
- **Status:** COMPLETED
- **Date:** 2026-09-20
- **Summary:** Closed out Task 003 by initializing Git version control, correcting documentation drift, replacing brittle error string-matching with typed error categories, adding end-to-end SSE token streaming with a stop control, and adding a proper resource-disposal chain.
- **Files modified:** `ai_config.dart`, `chat_request.dart`, `ai_provider.dart`, `groq_provider.dart`, `chat_service.dart`, `home_page.dart`, `settings_page.dart`, `.gitignore`, `groq_provider_test.dart`, `chat_service_test.dart`, `PROJECT_STATUS.md`
- **Testing:** `flutter analyze` — 0 issues; `flutter test` — 42/42 passed
- **Result:** PASS
