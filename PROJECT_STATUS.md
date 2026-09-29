# Kitten AI — Project Status

## Project

- **Project name:** kitten
- **Framework:** Flutter 3.47.5 (stable channel)
- **Target platform:** Android (primary), with iOS/Web/Windows/macOS/Linux scaffolding present
- **Version control:** Git repository. Baseline `492be59`, Task 003 closure `4ed421c`.
- **Current development stage:** Floating Kitten overlay and opt-in background assistant implemented; device verification covers build, install, permissions, and app startup. The overlay now also greets the user, comments on the app they open, and starts the conversation when tapped; that loop is verified on the Pixel 7 through the overlay window's own geometry.

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
**Task 008 — Screen Understanding with Explicit Permission**
Status: **COMPLETED**

8. **Task 008 — Screen Understanding** — on-demand screenshot capture with explicit consent, answered by a vision model, described below.
9. **Task 010 — Phone Capabilities** — user-confirmed dialer, SMS composer, alarm, timer, and app-launch actions through Android system intents.
10. **Floating Kitten Overlay** — explicit Android overlay permission, native draggable avatar service, Settings controls, and Flutter platform controller.
11. **Background Assistant** — opt-in microphone foreground service with “Hey Kitty”/“Kitty” wake detection, safe command handoff, and unlock/reboot restoration.
12. **Floating Overlay Conversation Loop** — Kitten's lines shown in a speech bubble, a microphone-free foreground-app watch owned by the overlay, and a tap that opens the conversation already knowing which app the user came from, described below.

### Floating Overlay Conversation Loop

Status: **VERIFIED on device**

Turned the overlay from a cat that opens the app into the one that starts the
conversation:

```
Phone unlocked
  -> Kitten appears
  -> "Hey! What are you doing today?"
  -> user opens an app
  -> Kitten: "Instagram? What are we doing here?"
  -> user taps the cat
  -> the conversation opens already knowing the app
```

- **Speech bubble (selected behaviour):** the overlay window is no longer a
  fixed square. It is exactly as large as it needs to be — the cat alone, or the
  cat plus a rounded bubble with a tail pointing at it — and the cat is the
  anchor, so the cat never moves when a line appears. The bubble goes on
  whichever side has room, wrapping to at most four lines.
- **Greeting on arrival (selected behaviour):** the service shows
  "Hey! What are you doing today?" the moment the overlay starts, which includes
  the unlock and reboot restart `BackgroundAssistantReceiver` already performs.
- **App watching without the microphone (selected behaviour):** the overlay
  itself polls Android's usage events (`MOVE_TO_FOREGROUND`, every 2.5 seconds
  over a 20-second window) and says a line the first time a *different* app
  appears. It needs only the `GET_USAGE_STATS` app-op: no audio foreground
  service, no `RECORD_AUDIO`, no notification. Kitten never comments on an app
  the user left more than 20 seconds ago, and never reports itself.
- **Kitten's line, in Kitten's words:** `Instagram? What are we doing here?`,
  `WhatsApp? Who are we texting?`, `YouTube? Study or entertainment?`,
  `Chrome? What are we looking for?`, `Spotify? What are we listening to?`, and
  `"<App>? What are we doing here?"` for anything else.
- **Tap starts the conversation (selected behaviour):** tapping the cat hands
  the package, label, and *the same line the bubble showed* to `MainActivity`.
  The chat seeds that line as Kitten's own opening message — locally, with no
  model request — focuses the input field, and the reply that follows is written
  with the app in view through the existing awareness prompt context.
- **A cold tap is not lost:** tapping the cat usually cold-starts the activity,
  where a pushed channel call would arrive before Flutter has a handler. The
  native side stashes the hand-off, Dart takes it on start and on resume, and
  acknowledges it so a warm start is not delivered twice. `ChatService` also
  ignores a repeat of the line it just seeded, covering the race between the two.
- **One voice for app lines:** `BackgroundAssistantService` no longer announces
  the foreground app. That line belongs to the overlay now, which shows it
  whether or not the microphone is on, so the two can never both say it. The
  wake-word service keeps the microphone, its acknowledgement lines, and the
  hand-off of a spoken command to the app.

#### Conversation loop verification

- `flutter analyze`: **0 issues**.
- `flutter test`: **166 of 166 pass**. (An earlier note recorded one failure
  here; it was the stale system-prompt assertion described under Known
  Problems, and it is fixed.)
- Whole device suite on the Pixel 7 — **8 of 8 pass**:
  `app_awareness_test.dart` 3/3, `floating_overlay_test.dart` 1/1,
  `screen_understanding_test.dart` 4/4, the last including a real vision
  round-trip. See Testing for the per-file run recipe the app-ops require.
- Two tests were hardened after failing on a freshly booted device. The overlay
  test had assumed it started stopped, but a boot or unlock restores the
  floating Kitten when it was enabled before, so it now clears anything already
  running. The awareness test asserted a bare `find.text('Granted')`, which
  matched twice once the new *Overlay permission* row also read "Granted"; that
  finder is now scoped to the Usage Access tile. Both were test assumptions that
  the overlay work invalidated, not app defects.
- New tests: 6 in `test/core/overlay/floating_overlay_controller_test.dart`
  (push, acknowledgement, one-shot take, disposal, payload parsing) and 3 in
  `test/features/home/overlay_handoff_test.dart` (cold-start tap, live hand-off,
  duplicate hand-off), plus 4 `ChatService` seeding tests.
- `flutter build apk --debug`: succeeded, which is what compiles the Kotlin.
- `integration_test/floating_overlay_test.dart` on the Pixel 7
  (Android 17 / API 37): **1 of 1 passed**, including the new hand-off channel
  call. Reproduce with:

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell appops set com.example.kitten SYSTEM_ALERT_WINDOW allow
adb shell appops set com.example.kitten GET_USAGE_STATS allow
flutter test integration_test/floating_overlay_test.dart -d emulator-5554
```

##### What the device run actually proved

The overlay window's geometry was read from `dumpsys window windows` while the
service ran, because the bubble is a native window that no Flutter test can
observe. The numbers below are real frames, at 420 dpi where the 76 dp cat is
200 px:

| Moment | Overlay window | Cat on screen |
|--------|----------------|---------------|
| Greeting showing | `frame=[301,1236][1038,1436]` (737x200) | `x 838..1038`, `y 1236..1436` |
| After 6.5 s, bubble hidden | `frame=[838,1236][1038,1436]` (200x200) | `x 838..1038`, `y 1236..1436` |
| Chrome opened | `Requested w=781 h=200` | same place |

- **The greeting appears:** the service's window is 737x200 — 200 px of cat plus
  a bubble — as soon as it starts, and the window's `mAttrs` confirm
  `ty=APPLICATION_OVERLAY` and `fl=NOT_FOCUSABLE`.
- **The cat does not move.** The window grows to the *left* of the cat, so the
  cat's own rect is byte-identical in both states. That was the point of
  anchoring the layout on the cat instead of the window.
- **The bubble is sized to its text:** 737 px for
  "Hey! What are you doing today?" and 781 px for the longer
  "Chrome? What are we looking for?".
- **It hides itself:** after 6.5 seconds the window collapses back to 200x200
  with no leftover space.
- **The watch fires from the overlay alone:** with only the two app-ops granted
  and *no* background listening, launching Chrome made the overlay show its
  Chrome line within about a second, then hide again. It then stayed quiet — one
  line per app, not a repeat every poll.
- **The tap hands over:** `adb shell input tap` on the cat (938,1336, computed
  from the window frame) brought `com.example.kitten/.MainActivity` to the front
  as the resumed activity, and `dumpsys input_method` then reported
  `mInputShown=true` on the Flutter view — that is the seeded hand-off focusing
  the chat input, which is the only place that requests focus on arrival.
- **No crashes:** no `FATAL EXCEPTION` in logcat and nothing for the app in
  `logcat -b crash`.
- **Not verified:** what the bubble *looks* like to a human (a geometry dump
  proves size and position, not that the drawing is attractive), and
  `uiautomator dump` returns an empty tree for Flutter here, so the seeded
  sentence was confirmed indirectly through input focus rather than by reading
  it off the screen.

### Background Assistant

Status: **PARTIALLY VERIFIED**

- Added an explicit Settings toggle for background listening. Android shows a persistent
  notification while it is enabled.
- Added a native microphone foreground service using Android `SpeechRecognizer`; it listens for
  “Hey Kitty” or “Kitty” and hands the remainder to the existing Flutter chat/tool system.
- Commands are not executed silently in the service. The main Kitten app receives the command,
  so existing confirmation-safe phone and alarm tools remain in charge.
- Added app-name-only prompts for WhatsApp, Instagram, YouTube, Chrome, and other foreground apps
  when Usage Access is already granted. Kitten does not read app contents, messages, or
  notifications. *(Superseded by the Floating Overlay Conversation Loop, where these became the
  overlay's speech bubble so they appear whether or not the microphone is on.)*
- Added reboot/unlock restoration for explicitly enabled background listening and the explicitly
  enabled Floating Kitten overlay.
- Added `FOREGROUND_SERVICE_MICROPHONE` and `RECEIVE_BOOT_COMPLETED`; no AccessibilityService,
  notification-reading permission, or new dependency was added.

#### Background Assistant verification

- Focused controller and overlay tests: **7 of 7 passed**.
- `flutter analyze`: exits successfully; only 3 existing informational lints remain in the
  earlier Task 010 phone-capability files.
- Android debug APK: built successfully.
- Pixel 7: APK installed, microphone and overlay app-ops granted, manifest service/receiver
  entries present, and Kitten remained alive after launch.
- **Not yet manually verified:** a real spoken wake phrase, an app-switch prompt, or a complete
  alarm/call command on the emulator. The emulator has no reliable microphone input, and the
  Flutter integration runner previously reported `No tests were found` for the overlay test.

### Floating Kitten Overlay

Status: **PARTIALLY VERIFIED**

- Added a Flutter `FloatingOverlayController` and platform interface for support, permission,
  settings, start, stop, and native running-state checks.
- Added the Android `FloatingKittenService`, a non-exported foreground service using
  `TYPE_APPLICATION_OVERLAY`. It draws a compact procedural kitten, clamps dragging to the
  display bounds, and opens the existing Kitten activity when tapped.
- Extended by the Floating Overlay Conversation Loop: the same service now draws Kitten's lines
  in a bubble, watches which app the user opens without needing the microphone, and tells the
  activity which app the tap came from.
- Added explicit `SYSTEM_ALERT_WINDOW` permission and a real Settings section. The overlay is
  off by default, never starts merely because permission is granted, and Settings only shows
  running after the native service confirms it.
- The overlay does not capture the screen, read notifications, use the microphone, listen for
  wake words, or inspect other apps.

#### Floating Kitten verification

- `flutter pub get`: completed.
- Overlay controller tests: **4 of 4 passed**.
- `flutter analyze`: exits successfully with 3 pre-existing informational lints in the Task 010
  phone-capability files; no overlay diagnostics.
- `flutter build apk --debug`: succeeded.
- Pixel 7 (`emulator-5554`): APK installed, `SYSTEM_ALERT_WINDOW` app-op was granted, and the
  normal Kitten activity launched. The Flutter integration runner built the APK but then reported
  `No tests were found` for `integration_test/floating_overlay_test.dart`, so drag, tap-to-open,
  app-switch persistence, and Settings navigation were **not** claimed as manually verified.
- The test setup now pumps `KittenApp` before invoking the platform channel; a rerun is still
  needed when the integration runner can discover the test reliably.
- **Crash fix:** Android 14+ requires the runtime foreground-service type to match the manifest;
  `FloatingKittenService` now calls `startForeground` with
  `FOREGROUND_SERVICE_TYPE_SPECIAL_USE` and catches startup failures instead of terminating the
  app.

### Task 010 — Phone Capabilities

Status: **COMPLETED**

- Added five AI tools: `open_dialer`, `compose_message`, `set_alarm`, `set_timer`, and `open_app`.
- Calls and messages open the native composer only; Kitten never places a call or sends an SMS automatically.
- Alarms and timers open the system Clock UI for review and confirmation. No alarm permission or background service is used.
- App launching accepts an Android package name and reports clearly when the app is not installed.
- The Android method channel fails soft on unsupported platforms or when no handler exists.
- Registered the existing time and current-app tools alongside the new phone tools in production.

#### Task 010 verification

- Focused unit tests passed: **22 of 22** (`chat_service_test.dart` and `phone_action_tools_test.dart`).
- Android debug APK compiled successfully after the native channel was added.
- No new runtime permissions or third-party dependencies were required.

## Previous task

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

- **A human look at the speech bubble.** Its geometry, text-driven sizing, and
  auto-hide are verified from the window dump; nobody has judged how it looks.
- Task 009 (assistant tool/function system) was built in practice — the tool
  registry, the built-in time/app tools, and the Task 010 phone tools all exist —
  but it has never been formally closed out in this document.

## Features Planned

The following are planned but **NOT yet implemented**:

- Usage-history analysis beyond the single most recent app
- Richer app-aware conversation than the one fixed line Kitten says in its bubble
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
| `lib/core/overlay/services/floating_overlay_service.dart` | Floating Overlay | Platform contract for overlay permission and lifecycle |
| `lib/core/overlay/services/method_channel_floating_overlay_service.dart` | Floating Overlay | Android method-channel implementation |
| `lib/core/overlay/services/floating_overlay_controller.dart` | Floating Overlay | Flutter state controller for permission and running state |
| `test/core/overlay/floating_overlay_controller_test.dart` | Floating Overlay | Controller state, denial, and failure tests |
| `integration_test/floating_overlay_test.dart` | Floating Overlay | Pixel 7 overlay lifecycle test |
| `android/app/src/main/kotlin/com/example/kitten/FloatingKittenService.kt` | Floating Overlay | Native draggable overlay foreground service |
| `lib/core/background/services/background_assistant_service.dart` | Background Assistant | Platform contract for opt-in background listening |
| `lib/core/background/services/method_channel_background_assistant_service.dart` | Background Assistant | Method-channel implementation |
| `lib/core/background/services/background_assistant_controller.dart` | Background Assistant | Flutter state and command stream controller |
| `test/core/background/background_assistant_controller_test.dart` | Background Assistant | Enable, disable, and failure tests |
| `android/app/src/main/kotlin/com/example/kitten/BackgroundAssistantService.kt` | Background Assistant | Native wake-phrase and app-context foreground service |
| `android/app/src/main/kotlin/com/example/kitten/BackgroundAssistantReceiver.kt` | Background Assistant | Unlock/reboot restoration receiver |
| `lib/core/overlay/models/overlay_app_context.dart` | Conversation Loop | The app the overlay hands to the chat, with display-name and line fallbacks |
| `test/features/home/overlay_handoff_test.dart` | Conversation Loop | Cold-start, live, and duplicate hand-off into the conversation |
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
| `android/app/src/main/AndroidManifest.xml` | Floating Overlay | Added `SYSTEM_ALERT_WINDOW` and the non-exported overlay service |
| `android/app/src/main/kotlin/com/example/kitten/MainActivity.kt` | Floating Overlay | Added overlay permission and lifecycle method channel |
| `lib/features/home/presentation/pages/home_page.dart` | Floating Overlay | Shares the overlay controller with Settings |
| `lib/features/settings/presentation/pages/settings_page.dart` | Floating Overlay | Added Floating Kitten permission and start/stop controls |
| `lib/features/home/presentation/pages/home_page.dart` | Background Assistant | Routes native wake commands into chat |
| `lib/features/settings/presentation/pages/settings_page.dart` | Background Assistant | Added opt-in background listening toggle |
| `android/app/src/main/kotlin/com/example/kitten/MainActivity.kt` | Background Assistant | Added service controls and command handoff |
| `android/app/src/main/AndroidManifest.xml` | Background Assistant | Added microphone service, receiver, and permissions |
| `android/app/src/main/kotlin/com/example/kitten/FloatingKittenService.kt` | Conversation Loop | Speech bubble, a microphone-free foreground-app watch, and the tap hand-off |
| `android/app/src/main/kotlin/com/example/kitten/MainActivity.kt` | Conversation Loop | Stashes the handed-over app and answers `takeAppContext`/`acknowledgeAppContext` |
| `android/app/src/main/kotlin/com/example/kitten/BackgroundAssistantService.kt` | Conversation Loop | Dropped the spoken app announcements, which are the overlay's job now |
| `lib/core/overlay/services/floating_overlay_service.dart` | Conversation Loop | Hand-off contract: push, take, and acknowledge |
| `lib/core/overlay/services/method_channel_floating_overlay_service.dart` | Conversation Loop | Listens for pushed hand-offs and takes the stashed one |
| `lib/core/overlay/services/floating_overlay_controller.dart` | Conversation Loop | Exposes hand-offs as a stream plus a one-shot take |
| `lib/core/ai/services/chat_service.dart` | Conversation Loop | `seedAssistantMessage` opens a conversation Kitten started itself |
| `lib/features/home/presentation/pages/home_page.dart` | Conversation Loop | Seeds and focuses the input when the overlay hands an app over |
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
| `android.permission.SYSTEM_ALERT_WINDOW` | Floating Overlay | User-granted permission to draw Kitten above other apps |
| `android.permission.FOREGROUND_SERVICE_MICROPHONE` | Background Assistant | Required for the visible microphone foreground service |
| `android.permission.RECEIVE_BOOT_COMPLETED` | Background Assistant | Restores explicitly enabled services after reboot/unlock |

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
| Conversation Loop | **0 issues** | **166/166 passed** + **8/8 on-device** |

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

On-device suites, all 8 tests passing on the Pixel 7 emulator:

- `app_awareness_test.dart` — 3 tests, requires Usage Access
- `floating_overlay_test.dart` — 1 test, requires the `SYSTEM_ALERT_WINDOW` app-op
- `screen_understanding_test.dart` — 4 tests, requires the `PROJECT_MEDIA` app-op

Two things about running them are easy to get wrong:

- **Run one file per invocation, and grant the app-op just before each one.**
  `flutter test integration_test/...` reinstalls the app between files, which resets its
granted app-ops. Passing the whole directory in one command therefore only leaves the
  *first* file with working permissions; the rest fail as if the user had never granted
  anything. The reliable recipe is install → grant → run, once per file:

  ```bash
  adb install -r build/app/outputs/flutter-apk/app-debug.apk
  adb shell appops set com.example.kitten SYSTEM_ALERT_WINDOW allow
  adb shell appops set com.example.kitten GET_USAGE_STATS allow
  adb shell appops set com.example.kitten PROJECT_MEDIA allow
  flutter test integration_test/<file>_test.dart -d emulator-5554
  ```

- **The vision round-trip needs a key, and it can be passed at run time** rather than typed
  onto the device, so no secret is written to disk or committed:

  ```bash
  flutter test integration_test/screen_understanding_test.dart -d emulator-5554 \
    --dart-define=GROQ_API_KEY=gsk_...
  ```

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
- **The vision model has now been seen answering for real.** A 28,770-byte screenshot of the
  emulator reached `qwen/qwen3.8-27b` and came back with a reply that correctly described what
  was on screen ("That little screen is just the Kitten app loading up…"). This closes the gap
  that had been open since Task 008, whose on-device result was recorded as PASS with the live
  answer still pending a configured key. The round-trip still needs a key to run at all, and it
  is exercised by passing one at run time (`--dart-define=GROQ_API_KEY=...`) rather than typing
  a secret into the device.
- **Consent is asked every single time.** That is deliberate for privacy, but it means the
  feature never becomes one-tap in practice; Android's own "remember this decision" option is
  the only shortcut.
- **`POST_NOTIFICATIONS` is declared but never requested**, so on Android 13+ the capture
  notice may not be visible even though the foreground service is running.
- **A screenshot stays in the conversation.** Only the newest one is re-sent to the model, but
  older screenshots remain in memory and in the visible chat until the conversation is cleared.
- **No OCR or accessibility fallback:** if the vision model cannot read something (small text,
  handwriting), Kitten has no second path to the screen's content.
- **The overlay watches on Usage Access alone.** Its app bubble runs whenever the special
  `GET_USAGE_STATS` app-op is granted and the floating Kitten is on, independently of the App
  Awareness switch in Settings. That matches the background assistant, which polled the same
  app-op, but the Settings switch is therefore not the only thing that decides whether apps are
  noticed.
- **Bubble lines are fixed flavour.** Five named apps get a tailored question and everything else
  gets "`<App>? What are we doing here?`". No model is involved and nothing is learned.
- **The bubble is transient.** It auto-hides after 6.5 seconds, cannot be tapped or scrolled on
  its own, and only reappears for a *different* app.
- **Only the tap is wired up.** Dragging the cat leaves the bubble where it is, and there is no
  way to ask Kitten to repeat what it just said.
- **The bubble's looks are unverified by eye.** The device run proved the window's size,
  position, and lifecycle, but nobody has looked at the drawing itself on a screen.
- **Only Chrome was exercised for the app watch.** The watch itself is app-agnostic, but only
  one real app switch has been observed.
- **The seeded sentence was confirmed indirectly.** `uiautomator dump` yields an empty tree for
  a Flutter app here, so the hand-off was proven through the input focus it triggers rather than
  by reading the line off the screen.
- **The prompt test was brought up to date.** `ai_models_test.dart`'s assertion still expected
  the old wording that *forbade* phone features, which stopped being true once the registered
  hand-offs landed. It now asserts both halves of the real contract: that the dialer, SMS
  composer, and alarms/timers are advertised, and that nothing acts without the user confirming
  it. The full suite is green again (166 passing).
- **Debug builds do not render on the Pixel_7 emulator unless Impeller is off.** The engine loads,
  the Dart VM starts, and the activity reports RESUMED, but `firstWindowDrawn=false` with **0 frames
  rendered**, so the Android splash screen stays up indefinitely. The app is not at fault: the same
  `main.dart` renders 40 frames with Impeller off, and the **release** build renders correctly with
  Impeller on, which is why this only ever broke the development loop and never a real phone. The
  opt-out lives in `android/app/src/debug/AndroidManifest.xml` so release keeps Impeller; if debug
  builds ever go blank again, that file is the first thing to check.
- **The emulator crash-loops the UWB HAL, which can stall SystemUI.** `vendor.uwb_hal` aborts with
  `failed to open the serial device: No such device or address` because `/dev/vport8p2` is never
  created, and init restarts it roughly every 1.5 seconds (800+ tombstones, measured). That steady
  tombstone load is enough to trigger a "System UI isn't responding" dialog. It cannot be stopped
  from the guest: `setprop ctl.stop` is SELinux-denied and `adb root` is refused on this Play-store
  image, and emulator 37.1.11 has no `Uwb` feature flag to disable. A non-Play-store `google_apis`
  image is the likely fix. Confirm it is the emulator, not the app, by checking `dumpsys cpuinfo`:
  `com.example.kitten` sits at 0% while `system_server`, Play services, and the sensors HAL dominate.
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
- **Floating overlay:** an explicit `SYSTEM_ALERT_WINDOW` grant starts a non-exported Android
  foreground service with a compact draggable avatar. The service owns the overlay window and
  tapping it brings `MainActivity` forward; no AccessibilityService or screen inspection is used.
- **App lines belong to the overlay:** the comment on the app the user opens is drawn as a
  bubble by `FloatingKittenService` rather than spoken by the microphone service, so it works
  silently and without an audio foreground service. Only one of the two can ever say it.
- **The overlay owns the wording:** the hand-off carries the exact line the bubble showed, so the
  conversation opens in the same words instead of inventing a second version on the Dart side.
- **Seeding is local:** Kitten's opening line is added to the conversation without a model
  request; the app itself reaches the next reply through the existing awareness prompt context.
- **Hand-offs survive a cold start:** the native side stashes the app it handed over, Dart takes
  it on start and on resume, and acknowledges it so a warm hand-off is not delivered twice.
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

**Richer app-aware conversation:** the overlay says one fixed line per app, so
replacing the hardcoded bubble text with a model-written opener — and letting
Kitten follow up on the app once the chat opens — is the natural next step.
The pending Task 009 close-out is still outstanding.

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
- **Result:** PASS (the live vision answer was still pending a configured key at the time;
  it has since been confirmed against a real model — see the Conversation Loop task above)
