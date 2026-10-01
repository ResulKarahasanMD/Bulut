# Bulut — personal iOS client for Ollama Cloud

SwiftUI + SwiftData iOS app (iOS 17+, Swift 5 language mode) that talks **directly** to Ollama Cloud
(`https://ollama.com/api`) with the user's API key. Cloud models only, no local Ollama, no backend.
UI strings are Turkish.

## Layout
- `Bulut.xcodeproj` — hand-written, objectVersion 77, uses a **file-system synchronized folder**
  (Xcode 16+): any file added under `Bulut/` is compiled automatically, no pbxproj edits needed.
  Bundle id `app.bulut.ollama`, `DEVELOPMENT_TEAM = 3V5WCZ8D9T` (paid account, automatic signing).
  No explicit App ID is registered; device builds use the wildcard "iOS Team Provisioning Profile: *"
  (expires 2027-07-17). TestFlight would need an explicit App ID (`-allowProvisioningUpdates`).
- `Bulut/Networking/` — `OllamaClient` (listModels, verifyKey, streamChat NDJSON via `URLSession.bytes`),
  `OllamaTypes`, `OllamaError` (401/403/404/429 mapping, `{"error": ...}` bodies, mid-stream errors).
- `Bulut/Storage/KeychainStore.swift` — API key, `AfterFirstUnlockThisDeviceOnly`.
- `Bulut/Models/Conversation.swift` — SwiftData `Conversation` / `ChatMessage` (optional to-many + defaults, CloudKit-ready).
- `Bulut/App/` — `BulutApp` + `RootView`, `AppModel` (key, model list cache, default model),
  `ChatEngine` (app-wide streaming, stop, regenerate, 50 ms flush throttle, background task).
- `Bulut/Markdown/` — dependency-free block parser + SwiftUI renderer (headings, lists, quotes, tables, code).
- `Bulut/Views/` — Onboarding (key verify), ConversationList, Chat, Composer, MessageRow (thinking
  disclosure, copy, regenerate, select-text sheet), Settings.

## API facts verified on 2026-10-01
- `GET /api/tags` is public: it returns 200 even with an invalid key, so the key is verified with a
  1-token non-streaming `/api/chat` call (`options.num_predict = 1`).
- Invalid key on `/api/chat` → HTTP 401 `{"error":"Unauthorized"}`.
- `POST /api/show {"model": ...}` works without auth and returns `capabilities`
  (e.g. `["completion","tools","thinking"]`, `vision`) — use it for Phase 2 (images, think toggle).
- Thinking text arrives in `message.thinking`; the app does not send `think` yet.

## Status
- DONE + tested on Linux (Swift 6.4, also clean in Swift 6 strict mode): Networking + MarkdownParser.
  25 checks passed against live ollama.com (fake key) and a local NDJSON mock server.
- pbxproj parsed and all object references resolve; asset catalog JSON valid; 1024px app icon present.
- 2026-10-01 on the Mac (Xcode 27.0, iOS SDK 27.0): the whole app compiles with **no source changes**.
  `generic/platform=iOS Simulator` and `generic/platform=iOS` builds succeed, 0 Swift warnings, also
  0 warnings with `SWIFT_STRICT_CONCURRENCY=complete`. Installed and launched on the user's iPhone
  15 Pro Max via `xcrun devicectl` (process stayed alive).
- No iOS simulator runtime is installed on this Mac; test on the iPhone instead.
- **NOT YET VERIFIED:** onboarding with a real key, streaming, stop/regenerate, Markdown rendering
  on device. The user enters the key themselves.

## Next (Phase 2)
System-prompt personas, temperature/context options, `think` toggle per model (via `/api/show`),
edit & resend user message, image attachments for vision models, auto title via the model.
Phase 3: App Intent / Shortcuts, share extension, Markdown/JSON export.
