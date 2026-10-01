# Bulut — personal iOS client for Ollama Cloud

SwiftUI + SwiftData iOS app (iOS 27.0+, Swift 5 language mode) that talks **directly** to Ollama Cloud
(`https://ollama.com/api`) with the user's API key. Cloud models only, no local Ollama, no backend.
UI strings are Turkish.

## Layout
- `Bulut.xcodeproj` — hand-written, objectVersion 77, uses a **file-system synchronized folder**
  (Xcode 16+): any file added under `Bulut/` is compiled automatically, no pbxproj edits needed.
  Bundle id `app.bulut.ollama`, `DEVELOPMENT_TEAM = 3V5WCZ8D9T` (paid account, automatic signing).
  No explicit App ID is registered; device builds use the wildcard "iOS Team Provisioning Profile: *"
  (expires 2027-07-17). TestFlight would need an explicit App ID (`-allowProvisioningUpdates`).
- `Bulut/Networking/` — `OllamaClient` (listModels, showModel, verifyKey, complete, streamChat NDJSON
  via `URLSession.bytes`), `OllamaTypes` (`ThinkSetting` bool-or-level, `/api/show` → `ModelDetails`),
  `OllamaError` (401/403/404/429 mapping, `{"error": ...}` bodies, mid-stream errors).
- `Bulut/Storage/` — `KeychainStore` (API key, `AfterFirstUnlockThisDeviceOnly`), `ImagePreparer`
  (ImageIO only: 1536 px JPEG for the model + 360 px thumbnail, EXIF orientation, no upscaling).
- `Bulut/Models/` — SwiftData `Conversation` (per-chat think / temperature / context length),
  `ChatMessage`, `MessageImage` (external storage), `Persona` (+ `PersonaSeeder`, 4 built-ins seeded
  once), `ConversationTitle` (first-message title, cleaning of model-written titles). Optional
  to-many + defaults everywhere, CloudKit-ready.
- `Bulut/App/` — `BulutApp` + `RootView`, `AppModel` (key, model list cache, `/api/show` details cache),
  `ChatEngine` (app-wide streaming, stop, regenerate, edit & resend, cancellable auto-title task,
  50 ms flush throttle, background task).
- `Bulut/Markdown/` — dependency-free block parser + SwiftUI renderer (headings, lists, quotes, tables, code).
- `Bulut/Views/` — Onboarding (key verify), ConversationList (long-press new chat → persona), Chat
  (model, persona, settings and edit sheets), Composer (photo picker for vision models, max 4),
  MessageRow (thinking disclosure, copy, regenerate, edit, image grid + viewer), ModelSettingsSheet,
  PersonaViews, Settings (personas, auto-title toggle).
- `Bulut/Previews/PreviewData.swift` — `#if DEBUG` in-memory store and keyless `AppModel` for `#Preview`s.
- `BulutTests/` — Swift Testing target hosted by Bulut.app (synchronized folder; shared `Bulut` scheme
  runs it serially). `StubServer` fakes `https://bulut.test` through `URLProtocol` on
  `URLSession.shared`; `AppModel(apiKey:defaults:baseURL:)` points the app at it. Run:
  `xcodebuild test -project Bulut.xcodeproj -scheme Bulut -destination 'platform=iOS Simulator,name=Bulut iPhone 17 Pro Max'`.

## iOS 27 (deployment target 27.0, so no `#available` gates)
- 27.0, not 27.0.1: the only simulator runtime here is iOS 27.0 (24A434) and the SDK allows up to
  27.0.99; the iPhone runs 27.0.1. The iPad Pro (iOS 26.6) can no longer install the app.
- Chat: `ToolbarOverflowMenu` for model settings / persona / system prompt / share,
  `toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)`, `swipeActionsContainer()` so the
  message rows' `swipeActions` (copy, edit, regenerate) work outside a `List`, and
  `onScrollGeometryChange` to follow a streaming reply only while you are at the bottom.
- List: new-chat button at `.topBarPinnedTrailing`; delete asks first via `confirmationDialog(_:item:)`.
- The SDK 27.0 name is `toolbarMinimizationBehavior` / `ToolbarMinimizationBehavior`; the bundled
  swiftui-whats-new-27 skill says `toolbarMinimizeBehavior`, which does not compile.
- Never confirm inside `.onDelete`: List removes the row at once and SwiftUI throws
  `NSInternalInconsistencyException` (invalid number of items) when the data is still there. Use a
  per-row `swipeActions` button without the destructive role, then delete.

## API facts verified on 2026-10-01
- `GET /api/tags` is public: it returns 200 even with an invalid key, so the key is verified with a
  1-token non-streaming `/api/chat` call (`options.num_predict = 1`).
- Invalid key on `/api/chat` → HTTP 401 `{"error":"Unauthorized"}`.
- `POST /api/show {"model": ...}` works without auth and returns `capabilities`
  (e.g. `["completion","tools","thinking"]`, `vision`), `thinking: {"values": [...], "default": ...}`
  (values mix bools and levels: gpt-oss `low/medium/high`, deepseek `false/low/high/max`,
  nemotron `false/true`; minimax-m3 has `thinking: null`) and `model_info.*.context_length`.
- Thinking text arrives in `message.thinking`. `think` is honored (measured in the simulator with a
  real key): kimi-k2.7-code `false` → 0 thinking chars vs 20k+ by default; gpt-oss:120b same prompt
  `low` 109 chars / 78 tokens, `medium` 128 / 107, `high` 1870 / 520 (n=1 each).
- Cloud replies carry `eval_count` but no usable `eval_duration` for gpt-oss/kimi, so tok/s is empty
  for them. Whether `temperature` / `num_ctx` are applied is NOT verified.
- Retired models answer `/api/show` with `{"error": "... was retired at ..."}` (qwen3-vl, gemma3).

## Status
- DONE + tested on Linux (Swift 6.4, also clean in Swift 6 strict mode): Networking + MarkdownParser.
  25 checks passed against live ollama.com (fake key) and a local NDJSON mock server.
- pbxproj parsed and all object references resolve; asset catalog JSON valid; 1024px app icon present.
- 2026-10-01 on the Mac (Xcode 27.0, iOS SDK 27.0): the whole app compiles with **no source changes**.
  `generic/platform=iOS Simulator` and `generic/platform=iOS` builds succeed, 0 Swift warnings, also
  0 warnings with `SWIFT_STRICT_CONCURRENCY=complete`. Installed and launched on the user's iPhone
  15 Pro Max via `xcrun devicectl` (process stayed alive).
- Phase 1 on the iPhone: real-key onboarding, model list, reply, thinking disclosure, Markdown.
- Phase 2 (PR #1, merged into `main` as `d2d298d`) verified in the iOS 27 simulator "Bulut iPhone 17
  Pro Max" with a real key: think control (above), stop keeps partial thinking without an error,
  regenerate, personas, edit & resend (also image-only), 2-photo attachment on kimi-k2.7-code (the
  model read "BULUT 42" from the test image), auto title.
- Phase 2 installed on the iPhone from `6a5e80a`: the Phase 1 store migrated in place (1 conversation,
  6 messages; role/content/thinking identical by sha before vs after), `ZPERSONA` and `ZMESSAGEIMAGE`
  created, 4 personas seeded, key kept. Back up first with
  `xcrun devicectl device copy from --domain-type appDataContainer --domain-identifier app.bulut.ollama
  --source "Library/Application Support"` (fails with CoreDeviceError 4016 while the phone is locked).
- NOT yet verified: the title language fix (needs typed input).
- iOS 27 hardening (branch `feature/ios27-hardening`): 24 tests pass in the iOS 27 simulator. Builds
  clean (0 Swift warnings) in Debug with `SWIFT_STRICT_CONCURRENCY=complete`, in Release, and with
  `SWIFT_VERSION=6` (the target still uses Swift 5 mode). The overflow menu, minimizing bar, message
  swipe actions and delete confirmation were checked by hand in the simulator. `AppModel.verify(key:)`
  uses the injected server too (a test caught it reaching ollama.com). Before the fixes, tests showed a stop before the first token and an
  empty server reply both left an invisible reply, and `stopAll` did not cancel a title request.
  Deleting a conversation mid-stream did NOT crash (simulator, in-memory store); the new
  `ChatEngine.delete` waits for the reply and title tasks before deleting anyway.

## Simulator testing notes
- The simulator pasteboard stays empty (`simctl pbcopy` and the panel's text action both fail), so text
  cannot be typed by Claude; drive everything else with taps and read results from the SwiftData store:
  `xcrun simctl get_app_container <udid> app.bulut.ollama data` → `Library/Application Support/default.store`.
- UI transitions lag the screenshot; wait ~1.5 s after a tap before capturing.
- Another session may run `BulutTests` on the same simulator; XCTest reinstalls and quits Bulut
  (`PlugIns/BulutTests.xctest` in the bundle, `testmanagerd` closes an `XCTestSession`). That is not a crash.

## Next
Phase 3: App Intent / Shortcuts, share extension, Markdown/JSON export.
Open ideas: smaller JPEGs (a detailed 1536 px photo is ~840 KB and is resent with every turn, and
the history is base64-encoded on the main actor on every send), strip Markdown in the conversation
list preview, the code-block edge fade kept in `stash@{0}` (based on Phase 1).
Follow-ups: switch to Swift 6 mode after a device pass over photo attach and background expiry
(it compiles clean; the runtime isolation checks are what is untested); profile streaming with the
Instruments SwiftUI template before caching Markdown blocks or changing `MessageRow` closures;
add a `VersionedSchema` before the first non-lightweight model change.
