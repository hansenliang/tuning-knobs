# WatchGPT: native watchOS client (prototype)

A standalone (watch-only) Apple Watch app for the WatchGPT gateway. It speaks the protocol in
[`../docs/API.md`](../docs/API.md) and follows the constraints in
[`../research/02-watchos-platform.md`](../research/02-watchos-platform.md). The screens match
[`../mockups/index.html`](../mockups/index.html): A1–A4 Ask, B1–B4 Live, C1–C4 edges, D1–D4 entry points.

> **Status:** written without a compiler. The code was authored on Linux without Xcode.
> The only automated check was a tree-sitter Swift *syntax* parse (all 40 files parse). Nothing
> has been type-checked, built, or run. Expect a round of compile fixes. The list at the bottom
> names every API whose exact watchOS 26 signature or behavior I couldn't confirm.

## Generate and run

```sh
brew install xcodegen
cd watchgpt/watchos
xcodegen generate          # writes WatchGPT.xcodeproj, Config/*.plist, Config/*.entitlements
open WatchGPT.xcodeproj
```

1. Set your team in project.yml (`DEVELOPMENT_TEAM`) or in Xcode's Signing & Capabilities.
   The App Group `group.app.watchgpt` must exist for your team, or rename it in project.yml
   and `SharedStore.swift`.
2. Start the gateway in another terminal:
   ```sh
   cd ../server && npm install && npm start     # http://localhost:8787, mock providers with no API keys
   ```
3. Run the **WatchGPT** scheme on a watchOS 26 simulator. The watch simulator shares the Mac's
   network stack, so `http://localhost:8787` (the Debug `GATEWAY_URL`) reaches the gateway directly.
   ATS allows plain HTTP to `localhost` only.
4. StoreKit: the scheme uses `WatchGPT.storekit` (one auto-renewable `app.watchgpt.pro.monthly`,
   $9.99, 7-day free trial). Manage test transactions from Debug › StoreKit › Manage Transactions.
   The gateway's `/v1/entitlements/apple` is a stub that accepts any `signed_transaction`.
5. To hit the paywall fast, the trial allows 30 turns/day and 5 Live min/day (server/src/config.ts).

**On a device**, `localhost` is the watch itself. Point `GATEWAY_URL` (project.yml, per config) at
an HTTPS tunnel (ngrok, Cloudflare Tunnel) or a deployed gateway. Don't put URLs in an `.xcconfig`,
because `//` starts a comment there.

## Layout

```
project.yml                  XcodeGen: watch-only app + WidgetKit extension, watchOS 26, scheme with StoreKit config
WatchGPT.storekit            local StoreKit test configuration
Resources/Assets.xcassets    AccentColor #FFB547, AppIcon placeholder (add a 1024 px icon)
Sources/
  App/        WatchGPTApp (scene, RootView, deep links), AppState (routing + services), TurnController (turn pipeline)
  Models/     TurnEvent, LiveEvent (server/client frames, close codes), APIModels, Conversation
  Services/   APIClient, Keychain, AudioSessionController (+Permissions), Recorder, SegmentPlayer,
              LiveSession (orchestrator + FrameSink), LiveSocket (NWConnection WebSocket), LiveAudioIO (AVAudioEngine),
              OfflineQueue, Store (StoreKit 2), Haptics
  Views/      Theme, Components, Consent, Home, Listening, Answer, Live (+summary), Paywall, Offline, Type
  Intents/    StartListeningIntent, StartLiveIntent (shared with the extension), AppShortcuts (app only)
  Shared/     AppConfig, LaunchRouter, SharedStore (App Group), Log (compiled into both targets)
Widgets/      complications (circular/corner/inline), Smart Stack (rectangular), TalkControl (ControlWidget)
```

## How it maps to the protocol

| Flow | Transport | Code |
|---|---|---|
| Register | `POST /v1/devices` → token in the Keychain. On a 401, delete it, re-register once, and retry | `APIClient.register/json/openTurn` |
| Turn (voice) | `POST /v1/turns?reply=voice&model=…&conversation_id=…`, `Content-Type: audio/mp4`, body = .m4a | `Recorder` → `APIClient.streamTurn(audioFile:)` |
| Turn (typed/dictated) | `POST /v1/turns` JSON `{text, reply:"text"}` | `TypeView` → `streamTurn(text:)` |
| Streaming | `URLSession.bytes(for:)` → `.lines` → `TurnEvent` | `APIClient.turnStream` |
| Spoken reply | `audio.segment` played in `seq` order, one `AVAudioPlayer` at a time. `audio.error` skips that seq | `SegmentPlayer` |
| HTTP errors | 401 re-register · 402 paywall (`resets_at`) · 413 "under a minute" · 429 `retry_after` · offline → queue | `APIClient.error(for:)`, `TurnController.run` |
| Live | `ws(s)://…/v1/live?token=…`, `session.start` first, PCM16 24 kHz 100 ms binary frames up and down | `LiveSession`, `LiveSocket`, `LiveAudioIO` |
| Barge-in | `speech.started` → flush the `AVAudioPlayerNode` now. Tapping the orb sends `response.cancel` | `LiveSession.handleServer`, `interruptReply` |
| Resume | an unexpected close → re-activate audio, reconnect at 0 / 250 ms / 500 ms / 1 s (then every 1 s until `resume_window_s`), `session.start{resume_session_id}` | `LiveSession.scheduleReconnect` |
| Close codes | 4001 re-register once then end · 4002 quota · 4003 max length · 4500 upstream · 1000 end · anything else resume | `LiveSession.socketClosed` |
| Purchase | StoreKit 2 → `POST /v1/entitlements/apple {signed_transaction: jwsRepresentation}`, finish only after the server accepts | `Store` |

The prototype gateway implements resume (`server/src/live.ts`, covered by `npm test`). It keeps a dropped
session for 15 s and buffers up to 10 s of reply audio. The client still tolerates a missing
`resumed`/`resume_window_s` (it treats them as `false` and 15 s) so older gateways work.

## VERIFY ON DEVICE

The simulator always allows low-level networking (TN3135), so none of this can be tested there.
You need a cellular watch, plus an iPhone with Wi-Fi *and* Bluetooth off (Settings, not Control Center).

1. **The ~36 s grant revocation (FB24377808).** Start Live and talk for 3 minutes or more, on
   watch Wi-Fi, the iPhone proxy, and cellular. Expected: `LiveSession.startKeepAlive` re-activates
   every 30 s and the socket never drops. Check the `live` log category for "Socket closed". Then
   set `keepAliveInterval` to 60 s and confirm the drop *does* happen around 36 s, which proves the
   workaround is what's doing the work. Confirm resume brings audio back in under 1.5 s. Re-test on watchOS 27.
2. **Network.framework WebSocket on cellular, iPhone off.** `NWConnection` should reach `.ready`
   only after `activate()` completes, never before. Confirm that without the audio session it sits in
   `.waiting(ENETDOWN)`, and that `LiveSocket` gives up after 2 s so the reconnect path redials.
   Try `wss://` through a real TLS endpoint (not the simulator's `ws://localhost`).
3. **Echo cancellation on the watch speaker.** With no AirPods, let the assistant talk and
   stay silent. Does the server fire `speech.started` on the model's own voice? If
   `setVoiceProcessingEnabled(true)` doesn't cancel it (check the "Voice processing unavailable"
   log), fall back to half-duplex on the speaker: skip `sink.push` while `phase == .speaking`
   and barge in only by tapping the orb. Also check that voice processing doesn't change the input
   format mid-session (the converter downmixes).
4. **URLSession.bytes time-to-first-byte and buffering.** watchOS runs URLSession out of process. Measure
   the time from Send to `transcript`, the first `text.delta`, and the first `audio.segment`, on each radio.
   If lines arrive in bursts (daemon buffering), try a smaller response (`reply=text`) to see whether
   buffering is size-based. The web simulator (server/public/index.html) shows the same latency
   numbers for comparison.
5. **Control → open into listening.** Add "Ask WatchGPT" in Control Center and on the Ultra
   Action button. Does the press foreground the app, and does `StartListeningIntent.perform()` run
   in the app (not the extension), so `LaunchRouter` delivers `.listen`? Can the mic start
   immediately, or does the app need to be `.active` first? `ListeningView` ignores the first second
   of inactive state for this reason. Also try a cold launch vs. a resumed app.
6. Background audio key: confirm that `UIBackgroundModes: audio` or `WKBackgroundModes: audio`
   (project.yml declares both) keeps Live running wrist-down and shows the return glyph. Delete the one
   that isn't needed.
7. Interruptions: take a phone call and invoke Siri during Live and during a push-to-talk recording.
   Live should show "Paused. Tap the orb to resume" and recover. Recording should cancel cleanly.
8. `NWPathMonitor` for the offline queue: TN3135 says it can stay `.unsatisfied` outside an audio
   session. The queue also retries on a 15 s→5 min backoff and when the app becomes active. Verify
   that a queued recording sends after airplane mode goes off.
9. AirPods: connect/disconnect during Live (`AVAudioEngineConfigurationChange` → `LiveAudioIO.restart`).

## APIs I'm not 100% sure of (verify signatures and behavior on the watchOS 26 SDK)

Build tooling
- XcodeGen single-target watch app: `type: application` + `platform: watchOS` (not the legacy
  `application.watchapp2` + `watchkit2-extension`). Also `embed: true` for the widget extension into the
  watch app's PlugIns, and the scheme key `run.storeKitConfiguration`.
- `WatchGPT.storekit` is hand-written JSON (format version 4). If Xcode rejects it, recreate it with
  File › New › StoreKit Configuration using the same product ID, price and 1-week free trial.
- Info.plist: `WKBackgroundModes: [audio]` (the brief asked for it; research cites `UIBackgroundModes`) and `WKWatchOnly`.

AVFoundation
- `AVAudioSession.activate(options:) async throws -> Bool`. I assumed this is the Swift import of
  `activateWithOptions:completionHandler:` and that it returns `Bool`.
- `AVAudioSession.CategoryOptions.allowBluetoothHFP` on watchOS (the older name is `.allowBluetooth`).
- `setCategory(.playAndRecord, mode: .voiceChat, policy: .default, options:)` on watchOS without a route picker.
- `AVAudioInputNode.setVoiceProcessingEnabled(_:)`: it exists (watchOS 6+), but whether it's
  effective on the watch speaker, and whether it changes the input channel count, is unknown.
- `AVAudioConverter.downmix` and the streaming `convert(to:error:withInputFrom:)` pattern with `.noDataNow`.
- `AVAudioApplication.shared.recordPermission` and the class method `AVAudioApplication.requestRecordPermission(completionHandler:)`.
- `AVAudioPlayer(data:fileTypeHint:)` with `"public.aac-audio"` for `format: "aac"` segments.
- Whether `AVAudioConverterInputBlock` and `AVAudioNodeTapBlock` are `@Sendable` in the SDK. The code
  avoids captured `var` mutation in case they are.

Network.framework
- `NWEndpoint.url(_:)` with `ws://`/`wss://` URLs: does NWProtocolWebSocket take the path and query
  (`/v1/live?token=…`) from it for the upgrade request? If not, send the token with
  `NWProtocolWebSocket.Options.setAdditionalHeaders([("Authorization", "Bearer …")])` (the gateway accepts both).
- `NWParameters(tls:tcp:)` initializer.
- `NWProtocolWebSocket.Metadata.closeCode` reporting 4001–4500 as `.privateCode(UInt16)`. The mapper
  accepts `.applicationCode` too.
- `NWConnection.viabilityUpdateHandler` behavior at grant revocation.

Swift / concurrency
- `OSAllocatedUnfairLock(uncheckedState:)` / `withLockUnchecked`, and `withLock`'s `@Sendable` closure
  requirement under strict concurrency (the FrameSink sends on the socket inside the lock).
- `@Observable` on `NSObject` subclasses (`Recorder`, `SegmentPlayer`, which are delegate objects).
- `MainActor.assumeIsolated` inside a `queue: .main` NotificationCenter block.

SwiftUI / WatchKit
- `.handGestureShortcut(.primaryAction)` on buttons inside NavigationStack destinations (one per screen).
- `ToolbarItem(placement: .topBarTrailing)` sitting beside the system clock (the Live minutes-left and the Listening timer).
- `.containerBackground(Color.black, for: .navigation)` for true black.
- `TextFieldLink(prompt:label:onSubmit:)` trailing-closure form.
- `Text("\(Text(…))\(Text(…).foregroundStyle(…))")` interpolation for the streaming cursor.
- `Link` on watchOS for the Terms/Privacy links (App Review needs them. Does it open anything useful on the watch?).
- `WKApplication.shared().applicationState`.
- `Date.RelativeFormatStyle` `.narrow` output (for the "2m ago" peek).
- `presentTextInputController(withSuggestions: nil, allowedInputMode: .plain)` (straight to dictation)
  is **not** used. SwiftUI apps have no visible interface controller. `TextFieldLink` is the substitute.

App Intents / WidgetKit
- `ControlWidget` / `StaticControlConfiguration` / `ControlWidgetButton(action:)` on watchOS 26, and a
  ControlWidget living in the same `WidgetBundle` as accessory widgets.
- `static let openAppWhenRun = true` (may be deprecated in favor of `supportedModes: IntentModes = .foreground`).
  Also whether a Control's `perform()` runs in the app process.
- `static let description = IntentDescription(…)` satisfying the protocol's optional `description` requirement.
- `.widgetLabel(_:)` with a String on `accessoryCorner`. Whether `.containerBackground(_:for: .widget)` is
  required for accessory complications on watchOS 26.

StoreKit
- `Product.purchase()` on watchOS 26 with no `confirmIn:` scene/window parameter.

## Known gaps / next steps

- Opus uplink (research §3) isn't implemented. PCM16 is about 48 KB/s up while talking.
- Smart Stack relevance (`RelevanceConfiguration`, watchOS 26) is a TODO in `SmartStackWidget.swift`.
- The paywall copy ("60 min of Live per month") matches the server's monthly Live metering (`config.limits`).
- Consent "Details" must list exactly the providers the gateway is configured with. The default is Anthropic direct; OpenRouter is named only if `LLM_PROVIDER=openrouter`. Legal should confirm the wording.
- Live mute ends the session after 60 s (B3). The Live session cap is enforced by the server (4003).
