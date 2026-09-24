# 02: watchOS platform feasibility for WatchGPT

*Researched 2026-09-24. Current release: **watchOS 27** (public Sept 14, 2026; runs on Series 9 and later, Ultra 2 and later, and SE 3, [MacRumors](https://www.macrumors.com/2026/09/14/apple-releases-watchos-27/)). **watchOS 26** still covers Series 6–8 and Ultra 1. Anything marked **(unverified)** needs a device test.*

---

## TL;DR

- **Plain HTTPS through `URLSession` works for every app, on Wi-Fi, cellular and the iPhone proxy.** That includes streamed responses (SSE through `bytes(for:)`). Dictation and push-to-talk mode need no special permissions.
- **WebSocket, TCP and UDP count as "low-level networking".** watchOS allows them in only two cases: while an *audio-streaming app has an active audio session*, or during a *CallKit VoIP call*. `URLSessionWebSocketTask` is denied in practice, even with an audio session. Use **Network.framework `NWConnection` + `NWProtocolWebSocket`**, opened after the **async** `AVAudioSession.activate(options:)`.
- **Newly found blocker (Aug 2026 forum thread):** the audio-session grant is **revoked about 36 s after each `activate()`**. A documented workaround doesn't exist yet. Re-calling `activate()` every ~30 s held a socket for 11+ minutes. Apple is tracking it as FB24377808, with no fix date.
- **WebRTC has no supported path.** LiveKit closed watchOS support as *wontfix*. Google WebRTC, Daily and Agora don't ship for watchOS.
- **The Speech framework doesn't exist on watchOS** (neither `SFSpeechRecognizer` nor `SpeechAnalyzer`/`SpeechTranscriber`). The only on-watch speech-to-text is **system dictation**, and it returns text only after the user taps **Done**.
- **Recording keeps going with the wrist down** if it starts in the foreground with the audio background mode. But **interruptions (calls, Siri) can't be recovered from in the background.**

---

## 1. Networking (TN3135)

**Source:** [TN3135 Low-level networking on watchOS](https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos). The latest revision (2026-07-16) only fixed a link; the rules haven't changed since watchOS 9.

Quoted rules:

> "High-level networking. This includes the HTTP and HTTPS support in URLSession, and any code layered on top of that."
> "Low-level networking. This includes Network framework, Stream, and any other API that runs a TCP connection or UDP session directly. That includes the low-level aspects of URLSession, namely URLSessionStreamTask and URLSessionWebSocketTask."
> "watchOS allows all apps to use high-level networking equally. However, it only allows an app to use low-level networking under specific circumstances:
> – It allows an audio streaming app to use low-level networking while actively streaming audio. (watchOS 6)
> – It allows a VoIP app to use low-level networking while running a call using CallKit. (watchOS 9)
> – [DeviceDiscoveryUI tvOS listener] (watchOS 9)"
> "if a normal app attempts to start an NWConnection, that connection will stay in the .waiting(_:) state with an error of ENETDOWN… NWPathMonitor will remain in the .unsatisfied state."
> "The BSD sockets API doesn't work for networking on watchOS under any circumstances."
> "the simulator always allows low-level networking." (**Only trust tests on a real device.**)

| API | Allowed? | Conditions / notes |
|---|---|---|
| `URLSession` data/upload/download over HTTPS | ✅ always | Works over Wi-Fi, cellular and the iPhone proxy. Runs **out of process** ("on watchOS every session is kinda like a background session", Quinn, [forum 773362](https://developer.apple.com/forums/thread/773362)), which adds latency. |
| `URLSession.bytes(for:)` / SSE / chunked responses | ✅ (high-level HTTP) | Shipping OSS example: [gemini-watch](https://github.com/cyroz1/gemini-watch) streams Gemini SSE with `URLSession.shared.bytes(for:)` + `.lines`. How promptly tokens arrive through the out-of-process path is **(unverified)**; measure it. |
| `uploadTask(withStreamedRequest:)` (streamed request body) | ✅ in principle (HTTP) | Could stream mic audio up during push-to-talk. Behavior on watch is **(unverified)**. |
| HTTP/2, HTTP/3 in `URLSession` | ✅ in principle | TN3151 says URLSession supports both. Watch-specific behavior **(unverified)**. |
| `URLSessionWebSocketTask` | ⚠️ low-level | Allowed on paper during an audio session, but **denied in practice**: the grant goes to the app process, and URLSession runs elsewhere ([luke PR #704](https://github.com/ReviewStage/luke/pull/704), [forum 773362](https://developer.apple.com/forums/thread/773362)). Quinn: "you should specifically avoid it on watchOS." |
| `NWConnection` + `NWProtocolWebSocket` | ⚠️ low-level | **Works during an audio session.** Confirmed on watchOS 26.x devices: [leptos-null demo](https://github.com/leptos-null/watchos-websocket), luke, [forum 841590](https://developer.apple.com/forums/thread/841590). |
| `NWConnection` UDP / QUIC | ⚠️ low-level | Same audio/CallKit gate. |
| BSD sockets | ❌ never | |

### What "active audio session" means in practice
- Enable **Background Modes → Audio** (`UIBackgroundModes: audio`).
- Call **`activate(options:completionHandler:)`, the async version**. The synchronous `setActive(true)` returns no error on the watch but grants nothing (confirmed on watchOS 26.6, S7 and S10, [forum 773362](https://developer.apple.com/forums/thread/773362)).
- The category can be `.playback` (Apple DTS test code: `.playback` / `.default` / `.longFormAudio`, [forum 779017](https://developer.apple.com/forums/thread/779017)) or **`.playAndRecord`** (luke; forum 841590 used `.playAndRecord` / `.spokenAudio`). `.longFormAudio` is **not required** for the grant, and it forces a Bluetooth route picker.
- **Quinn:** "There's no supported way to implement WebSocket on watchOS except in the context streaming audio" ([forum 714796](https://developer.apple.com/forums/thread/714796)).

### ⚠️ The ~36-second revocation ([forum 841590](https://developer.apple.com/forums/thread/841590), Aug–Sep 2026)
- Test setup: S10, watchOS 26.5, `.playAndRecord`/`.spokenAudio`, NWConnection WebSocket. Each `activate()` produces a network path that goes `.unsatisfied` **33–37 s later**. It **never recovers by itself** (observed for 8m50s). The socket fails with POSIX 50/9.
- Wi-Fi direct, the iPhone `ipsec1` proxy and cellular all show the same cycle. Running the audio engine, live mic and continuous playback don't change it.
- **Workaround (undocumented):** call `activate()` again **every ~30 s without deactivating**. Each call pushes the deadline back. Result: one WebSocket held **11m30s with zero reconnects** in a production app with a live mic.
- Quinn called redundant-activate handling "definitely misbehaviour" and tracks it as **FB24377808**. He gave no answer on whether the time limit is intentional.
- **Unknown:** whether `.playback`+`.longFormAudio` sessions, CallKit calls or watchOS 27 behave differently. **Test this in week 1.**

### CallKit VoIP path (watchOS 9+)
- `CXProvider` is on watchOS 9.0+ and PushKit on watchOS 6+. TN3135 explicitly allows low-level networking during a CallKit call.
- Precedent: Webex runs VoIP on the watch ([MacRumors](https://www.macrumors.com/2022/06/07/apple-watch-voip-calling-watchos-9/)).
- `.playAndRecord` without `.longFormAudio` works under CallKit. A seed-1 bug that blocked this was fixed in watchOS 9 beta 2 ([forum 708897](https://developer.apple.com/forums/thread/708897)).
- Risks:
  - App Review may object to CallKit for something that isn't a person-to-person call **(unverified)**.
  - CallKit is restricted in China.
  - Whether the 36 s revocation applies here is **(unverified)**.
- Upside: the system call UI survives wrist-down and handles interruptions better.

---

## 2. WebRTC

| Option | watchOS status |
|---|---|
| Google WebRTC (`WebRTC.framework`) | No official watchOS build ([discuss-webrtc](https://groups.google.com/g/discuss-webrtc/c/NByvfnw5LZ8)). BSD sockets are banned and all UDP falls under the TN3135 gate. |
| **LiveKit Swift SDK** | **Not supported.** Issue [#288](https://github.com/livekit/client-sdk-swift/issues/288) closed as *wontfix*. The README lists iOS/macOS/tvOS/visionOS only. |
| Daily, Agora | No watchOS SDKs found. |
| Custom stack | [openclaw PR #135808](https://github.com/openclaw/openclaw/pull/135808) (merged 2026-09-05) hand-built WebRTC: str0m for ICE/DTLS/SRTP, `NWConnection` UDP, native Opus. The PR itself says "**no connected physical Watch is available**", so it's **unproven on hardware**. It's still subject to the TN3135 gate. |

**Verdict:** skip WebRTC. Use our own relay server that bridges a watch WebSocket to the provider's Realtime/Live WebSocket or WebRTC (this matches 03-inference-voice-stack).

---

## 3. Audio capture & playback

**Availability (Apple doc JSON):**
- `AVAudioEngine` watchOS 2+, `AVAudioRecorder` 4+, `AVAudioConverter` 2+.
- `.playAndRecord` 2+, `.voiceChat` mode 2+, `setCategory(_:mode:policy:options:)` 5+.
- `AVAudioIONode.setVoiceProcessingEnabled(_:)` **watchOS 6+**.
- `.allowBluetoothHFP` watchOS 11+.
- `AVAudioApplication.requestRecordPermission` watchOS 10+.
- `kAudioFormatOpus` constant watchOS 4+.
- **Not on watchOS:** `.defaultToSpeaker` and `setPrefersEchoCancelledInput`.

**Full duplex (mic + speaker at once):**
- `.playAndRecord` + AVAudioEngine is the natural setup. Luke and forum 841590 run a live mic with playback in a production app.
- Whether echo cancellation works on the **watch speaker** via voice processing is **(unverified)**: the API exists, but nobody has published results. Apple's own Phone and Walkie-Talkie apps do full-duplex speakerphone.
- Plan server-side barge-in protection anyway (see risks).

**Speaker vs AirPods:**
- For **background long-form** playback, the doc says: "watchOS requires a Bluetooth audio route for long-form audio… the system presents an audio route picker" ([Playing background audio](https://developer.apple.com/documentation/watchkit/playing-background-audio)).
- Series 10+ and Ultra 2+ can play media through the speaker, and third-party apps like Overcast do it ([Geeky Gadgets](https://www.geeky-gadgets.com/the-best-apple-watch-speaker-apps/)). The doc may be out of date **(unverified for third-party long-form)**.
- **Don't use `.longFormAudio` for voice chat.** Use `.playAndRecord`, which routes to the speaker or to connected AirPods (HFP).

**Formats:**
- Capture PCM from AVAudioEngine and resample to **16 kHz or 24 kHz PCM16** with `AVAudioConverter`. That's what the provider APIs take.
- For LTE, encode **Opus** (~24 kbps vs 256 kbps for PCM16 at 16 kHz). Whether `AVAudioConverter` can encode Opus on watchOS is **(unverified)**. The safe route is [alta/swift-opus](https://github.com/alta/swift-opus) (libopus; supports watchOS 6+). AAC-LC via `AVAudioRecorder` works for push-to-talk file uploads.
- Playback: schedule decoded PCM buffers on an `AVAudioPlayerNode`.

**Interruptions:** "Recording cannot be resumed when the app is in the background on watchOS. It must be a user-initiated event while the app is in the foreground. (Recording can then continue once the app moves to the background.)" (Apple Frameworks Engineer, [forum 750432](https://developer.apple.com/forums/thread/750432)).

---

## 4. Speech (STT/TTS)

- **No third-party on-device STT.**
  - `SFSpeechRecognizer`: iOS, macOS and visionOS only.
  - `SpeechAnalyzer`/`SpeechTranscriber`: iOS, macOS, tvOS and visionOS 26. **Not watchOS** ([doc](https://developer.apple.com/documentation/speech/speechtranscriber)).
  - `DictationTranscriber`: not on watchOS.
  - The watchOS 26 release notes list Speech as "not available in the watchOS SDK" (cited in [openclaw PR #135826](https://github.com/openclaw/openclaw/pull/135826)).
  - watchOS 27 adds **Foundation Models** (`FoundationModels` watchOS 27.0) and Vision, but **not Speech** ([What's new](https://developer.apple.com/watchos/whats-new/)).
- **System dictation:**
  - SwiftUI `TextField`/`TextFieldLink` (watchOS 9+) opens the system input sheet. `presentTextInputController(withSuggestions: nil, allowedInputMode: .plain)` goes **straight to the dictation screen**. Passing any suggestion list, even an empty one, shows the picker first ([openclaw #135826](https://github.com/openclaw/openclaw/pull/135826)).
  - The user sees a live transcript, but the app gets **only final text after the user taps Done**. There's no auto-send and no partial results.
  - Series 9+ (S9 SiP) does dictation on-device and is ~25% more accurate ([Apple newsroom](https://www.apple.com/newsroom/2023/09/apple-introduces-the-advanced-new-apple-watch-series-9/)). It works without the iPhone. Older models need a network connection, and the exact offline behavior is **(unverified)**.
- **TTS:** `AVSpeechSynthesizer` is on watchOS 2+ and works on the watch speaker (gemini-watch uses it). `.premium` voice quality (watchOS 9+) and Personal Voice authorization (watchOS 10+) exist as APIs. Whether premium voices can be downloaded on the watch is **(unverified)**. Built-in voices are serviceable but robotic next to server neural TTS. **Use server TTS for the product voice** and keep `AVSpeechSynthesizer` as an offline fallback.

---

## 5. Background & lifecycle

Sources: [Frontmost app state](https://developer.apple.com/documentation/watchkit/taking-advantage-of-frontmost-app-state), [Always On](https://developer.apple.com/documentation/watchos-apps/designing-your-app-for-the-always-on-state), [forum 775151](https://developer.apple.com/forums/thread/775151)

- **Wrist down, no session:** the app goes inactive and becomes the "frontmost app". It stays in the foreground for the **Return to Clock** time (default **2 min**, max **1 h**, set by the user per app), then gets suspended. Pressing the crown or covering the screen sends it to the background **immediately**.
- **With background audio or recording active:** "Workout, location, background audio, and audio-recording apps… continue to run in the background throughout the entire… audio session." A glyph on the watch face lets the user return. **A live voice session keeps running with the wrist down, as long as it was started in the foreground.**
- **Always On (S5+, not SE):** UI stays visible but dimmed and updates at low frequency. Use `isLuminanceReduced` and `TimelineView`. Background sessions can keep updating the UI slowly.
- **`WKExtendedRuntimeSession`:** its types are only self care (10 min), mindfulness (1 h), physical therapy (1 h) and smart alarm. **None fits a voice assistant**, and using one would be misuse ([docs](https://developer.apple.com/documentation/watchkit/using-extended-runtime-sessions)). Forum 841590 notes extended runtime doesn't grant networking either.
- Sustained high CPU in any session can make the system cancel it (`exceededResourceLimits`).

---

## 6. Entry points

| Entry | Third-party? | Notes |
|---|---|---|
| **Action button (Ultra)** | ✅ via **Controls (watchOS 26+)** | `ControlWidget` is on watchOS 26. Controls appear in **Control Center, the Smart Stack and the Ultra Action button** ([WWDC25 334](https://developer.apple.com/videos/play/wwdc2025/334/)). A watch app's control runs on the watch. **Best path:** a "Talk" control whose intent opens the app into listening. Whether an `OpenIntent` from a control foregrounds the watch app *and* is allowed to start mic capture is **(unverified)**. |
| Action button via `StartWorkoutIntent` | ⚠️ workout apps only | Needs a real workout session (`workout-processing`). Using it for a non-workout app would be a review risk ([docs](https://developer.apple.com/documentation/appintents/actionbuttonarticle)). |
| Action button → Shortcut | ✅ | Users can bind a Shortcut that runs our App Shortcut. |
| `AudioRecordingIntent` (watchOS 11+) | ⚠️ | The doc requires a **Live Activity** "in iOS, iPadOS, and watchOS", but ActivityKit is **iOS-only**. How this works on the watch is **(unverified)**. |
| Complications / Smart Stack widgets | ✅ | WidgetKit accessory families (watchOS 9+). Relevance widgets (`RelevanceConfiguration`, watchOS 26). Push-updated widgets. Tapping one launches the app. |
| Siri / App Shortcuts | ✅ | `AppShortcutsProvider` watchOS 9+. watchOS 27's "Siri AI" takes App Intents across platforms ([WWDC26 343](https://developer.apple.com/videos/play/wwdc2026/343/)). |
| **Double Tap** | ✅ in-app only | `.handGestureShortcut(.primaryAction)` watchOS 11+ (S9+/Ultra 2+), only while the app is frontmost. Good for "tap to talk / stop". watchOS 27's new single-tap Smart Stack gesture has **no third-party API** ([search summary](https://www.macstories.net/stories/watchos-27-the-macstories-public-beta-preview/)). |

---

## 7. Standalone app, accounts, payments

- **Watch-only app**: an Xcode template exists. The iOS "stub" target installs nothing on the iPhone. Users can buy apps and make in-app purchases directly on the watch ([Creating independent watchOS apps](https://developer.apple.com/documentation/watchos-apps/creating-independent-watchos-apps)).
- **arm64 builds are required** for watchOS 26 (WWDC25 334).
- A reasonable deployment target is **watchOS 26**, which covers Series 6–8 on 26 plus everything on 27.
- **Sign in with Apple:** AuthenticationServices watchOS 6+, with `SignInWithAppleButton` in SwiftUI. **OAuth:** `ASWebAuthenticationSession` watchOS 6.2+. Password AutoFill and the Continuity Keyboard work on the watch ([Authenticating users](https://developer.apple.com/documentation/watchos-apps/authenticating-users-on-apple-watch)).
- **StoreKit 2** subscriptions: `Product.SubscriptionInfo` watchOS 8+. Purchases are universal when a companion iOS app exists.
- **Tokens between iPhone and watch:**
  - App-group keychain sharing is **not** cross-device.
  - `kSecAttrSynchronizable` (iCloud Keychain) is available on watchOS and reported to sync with some lag ([Damian Mehers, 2020](https://damian.fyi/swift/2020/07/23/sharing-tokens-between-macos-ios-and-watchos-using-icloud-keychain.html)). It depends on the user having iCloud Keychain on, so reliability is **(unverified)**.
  - WatchConnectivity is an opportunistic extra.
  - **Design sign-in so it can finish entirely on the watch.**

---

## 8. Performance, battery, latency

- **Radio paths:** iPhone proxy over Bluetooth (the `ipsec1` tunnel), watch Wi-Fi (`en0`) or cellular. Series 11, Ultra 3 and SE 3 have **5G RedCap** ([9to5Mac](https://9to5mac.com/2025/09/16/review-apple-watch-ultra-3-series-11/)). URLSession on the watch goes out of process, so expect higher time-to-first-byte than on the iPhone ([forum 88205](https://developer.apple.com/forums/thread/88205)).
- **Battery:**
  - Apple publishes no figure for sustained LTE streaming.
  - Historically watch talk time on LTE is about **1.5 h** (Series 8-era figure, **unverified** for current models). Ultra 3's 42 h test assumes only 8 h *connected* to cellular, not streaming.
  - Continuous mic + radio + speaker should land roughly in that talk-time range.
- **Implications:**
  - Default to push-to-talk.
  - Cap live sessions (e.g. warn at 10 min).
  - Use Opus rather than PCM.
  - Stop the engine and socket right away when the user ends a session (gemini-watch cancels its URLSession work for radio/battery reasons).
- **Latency budget:** LTE RTT is typically ~40–100 ms **(unverified; general figure)**. Add the out-of-process URLSession hop and 20–60 ms of Opus framing.

---

## 9. Apps and code that show the pattern

| App / repo | What it proves |
|---|---|
| [ReviewStage/luke #704](https://github.com/ReviewStage/luke/pull/704) (Sept 2026) | A production watch voice client for a realtime backend: **`.playAndRecord` + async activate + NWConnection WebSocket**, with URLSession for HTTP. |
| [Forum 841590](https://developer.apple.com/forums/thread/841590) | A live-mic WebSocket app on the watch, held 11.5 min with the 30 s re-activate workaround. |
| [leptos-null/watchos-websocket](https://github.com/leptos-null/watchos-websocket) | A minimal `.playback` + `activate` + `NWProtocolWebSocket` demo that works on a device. |
| [werdnum/family-assistant #1187](https://github.com/werdnum/family-assistant/pull/1187) | Gemini Live over Network-framework WebSockets on the watch. Not yet tested on a device. |
| [gemini-watch](https://github.com/cyroz1/gemini-watch) | Standalone watch LLM chat: **URLSession SSE streaming**, system dictation input, AVSpeechSynthesizer, Double Tap. |
| Wrist AI, WristGPT, Watch AI ([App Store](https://apps.apple.com/us/app/wrist-ai-1-tap-watch-gpt/id6752909449)) | Standalone cellular AI assistant apps pass App Review. |
| Webex (CallKit on watch); WhatsApp (voice notes, **no calls**: "platform limitations", [Meta](https://about.fb.com/news/2025/11/introducing-whatsapp-for-apple-watch/)) | The VoIP path exists but big players still skip it. |
| Zello | Pulled its watch app years ago over mic/speaker API limits ([X](https://x.com/zello/status/1004508559600693248)). Not current evidence. |

---

## Architecture implications

### (a) Dictation / push-to-talk mode → **plain HTTPS `URLSession` only** (recommended default, ship first)
1. **Input, option A (zero-risk):** system dictation (`presentTextInputController` nil/.plain or `TextField`). Final text arrives on Done, then POST it.
2. **Input, option B (better UX):** push-to-talk with AVAudioEngine capture → Opus/AAC → `URLSession` POST on release, then server-side STT.
   - Optionally stream the upload with `uploadTask(withStreamedRequest:)` **(unverified)**.
   - Start the audio session in the foreground (button, Double Tap or control). This also keeps us running with the wrist down.
3. **Output:** stream text over SSE with `URLSession.bytes(for:)` and render it as it arrives. Stream TTS audio as a chunked HTTP response and play it through `AVAudioPlayerNode`. `AVSpeechSynthesizer` is the fallback.
4. **Why:** TN3135 lets all apps use this path. It has no revocation timer, works on cellular without an iPhone, and has App Store precedent.

### (b) Live full-duplex mode → **Network.framework WebSocket to our own relay, under an active `.playAndRecord` session**
- **Setup:**
  - `UIBackgroundModes: audio`.
  - `setCategory(.playAndRecord, mode: .voiceChat or .spokenAudio)`.
  - **`await activate(options:)`**, then open `NWConnection` + `NWProtocolWebSocket` over TLS. **Never use `URLSessionWebSocketTask`.**
- **Keep-alive:** re-call `activate()` about every 30 s (the FB24377808 workaround). Also build **session resume** in the protocol: a server-side session ID, a replay cursor, and reconnect within 1–2 s on `.unsatisfied`, so a revocation or radio handoff is a blip.
- **Audio:**
  - Up: Opus 16–24 kHz mono, 20 ms frames, via swift-opus.
  - Down: Opus or PCM16 24 kHz. The relay transcodes to the provider format (OpenAI Realtime / Gemini Live PCM16).
  - Try `setVoiceProcessingEnabled(true)` for echo cancellation. Also keep server-side barge-in/echo guards, and on the watch speaker, optionally duck the mic while TTS plays.
- **Plan B:** wrap live mode in a **CallKit outgoing "call"**. TN3135 explicitly allows low-level networking during a call. Cost: review and China risk.
- **Plan C (if both are blocked):** "walkie-talkie" half-duplex over (a), with server VAD and auto-rearm. It feels ~70% as live with zero platform risk.

### Risks, highest first
1. **The 36 s grant revocation.** The workaround is undocumented and Apple could fix or harden it in either direction. Re-test on watchOS 27.x first.
2. **URLSession streaming latency and buffering** through the out-of-process daemon **(unverified)**. Measure time-to-first-token on Wi-Fi, cellular and the iPhone proxy.
3. **Echo cancellation on the watch speaker (unverified).** Without it, the model hears itself in full-duplex mode.
4. **Interruptions** (a call, Siri) end recording, and it can't be restarted from the background. The UI must return to a "tap to resume" state.
5. **App Review:** if we use CallKit, or bind the Action button through `StartWorkoutIntent`. Controls are the clean Action-button path.
6. **Battery:** live mode over LTE drains roughly like a phone call (~1–2 h, unverified). Cap it and make it opt-in.
7. **The simulator hides every one of these issues.** Budget for physical devices (a cellular model, and an iPhone with Wi-Fi *and* Bluetooth turned off in Settings, per TN3135) from day 1.
