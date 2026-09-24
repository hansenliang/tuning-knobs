# WatchGPT — Business Model, Pricing & App Store Policy Research

*Compiled 2026-09-24. All claims cite sources with access dates; anything not independently confirmed against a primary Apple/vendor source is marked "(unverified)".*

---

## 1. App Store Review Guidelines — what applies to WatchGPT

### 1.1 In-app purchase (3.1.1) and external payment on watchOS

| Question | Finding | Source |
|---|---|---|
| Must subscriptions go through Apple IAP? | Yes, by default: Guideline 3.1.1 requires Apple's IAP for unlocking digital features/content inside the app (subscriptions, credits, etc.). | [developer.apple.com/app-store/review/guidelines](https://developer.apple.com/app-store/review/guidelines/) (accessed 2026-09-24) |
| Can we link out to Stripe checkout instead, on the **US storefront**? | Yes, as of the May 2025 guideline update following the Epic v. Apple contempt ruling: on the US storefront there is **no prohibition** on buttons/external links/calls-to-action to outside purchase flows, and **no entitlement is required**. Everywhere else (non-US storefronts) the old rule still applies unless you hold the External Purchase Link entitlement. | [Frankfurt Kurnit summary](https://fkks.com/news/court-finds-apple-violated-order-resulting-in-key-changes-for-ios-external-purchase-methods); [mjtsai.com summary of May 2025 guideline update](https://mjtsai.com/blog/2025/05/02/app-review-guidelines-updated-for-epic-anti-steering/) (accessed 2026-09-24) |
| Does this hold on watchOS specifically? | The ruling covers "apps offered on the United States storefront" generally, not a per-platform carve-out, so it should extend to watchOS apps. **(unverified)** — no Apple doc found that names watchOS explicitly; treat as inferred from the general guideline text. |
| Is a Stripe/web link *practical* on-watch? | Poor UX today: watchOS has **no built-in Safari app**; opening a URL launches a limited WebKit viewer or hands off to a paired iPhone. Text-field checkout entry is described as impractical on-watch. So even where legally permitted, on-device external checkout is a bad experience for a "wrist-only" flow. | [µBrowser / Watch browser app reviews](https://www.itechguides.com/best-web-browser-for-apple-watch/); [Stora external-link implementation guide](https://stora.sh/blog/2026-05-16-apple-app-store-external-purchase-links-implementation-guide) (accessed 2026-09-24) |
| Litigation status (does the 0%-commission window last)? | As of Sep 2026: no court-approved replacement commission on external purchases yet, so **effectively 0% Apple cut** on US external links today. Apple asked the court (Aug 13, 2026) to approve 15% standard / 10% partner-program / 5% Small Business Program rates on external transactions; not yet approved. Supreme Court agreed (Jul 2, 2026) to hear Apple's appeal of the underlying contempt finding, arguments expected Oct 2026 term — the whole regime could change. | [AppleInsider, Sep 14 2026](https://appleinsider.com/articles/26/09/14/apple-standing-its-ground-in-epics-app-store-fee-suit); [MacDailyNews, Aug 14 2026](https://macdailynews.com/2026/08/14/u-s-supreme-court-clears-path-for-app-store-commission-showdown-as-apple-must-defend-its-rates-in-lower-court/) (accessed 2026-09-24) |
| **Recommendation** | Ship v1 on **Apple IAP/StoreKit** (simplicity + it's the only option that reliably works *from the watch itself*, and it's what users expect). Revisit external Stripe checkout later, driven from an iPhone companion or marketing site, once the external-link commission regime settles and only for renewal savings — not as the primary path. |

### 1.2 Can a **watch-only** app sell subscriptions via StoreKit at all?

- Apple enabled IAP on watchOS with **watchOS 6.2** (Feb 2020); StoreKit 2 supports iOS/iPadOS/macOS/tvOS/watchOS uniformly. In principle a standalone (no iPhone companion) watch app can present its own paywall and complete purchases entirely on-device. [Apple Developer News, watchOS 6.2 IAP](https://developer.apple.com/news/?id=02052020b) (accessed 2026-09-24)
- In practice, developer-forum reports describe friction for **fully independent** (no companion iOS app, no shared bundle) watch apps — some developers found StoreKit purchase flows or App Store Connect configuration assumed/worked more smoothly with a companion iOS app on the same bundle ID sharing one app record. **(unverified — appears to be tooling/UX friction, not a hard platform block; worth a StoreKit-2 spike before committing to watch-only IAP.)** [Apple Developer Forums thread](https://developer.apple.com/forums/thread/739963); [Apple Developer Forums thread](https://developer.apple.com/forums/thread/120705) (accessed 2026-09-24)
- **Recommendation:** prototype the StoreKit 2 subscription paywall directly on a watch-only target early (Milestone 0 spike) to de-risk this before it becomes a launch blocker.

### 1.3 Guideline 4.2 — Minimum Functionality

- Core risk for any "thin wrapper around an API" app: Apple rejects apps that are little more than a web view or a single-purpose utility with minimal interactivity, or that require a constant connection to show any meaningful UI.
- Mitigations that reviewers accept: genuine native UI (watch-native chat/transcript UI, complications, Digital Crown scrolling), a few native-feel capabilities (Siri/Shortcuts integration, offline cached history, haptics), and clear reviewer notes explaining the product.
- WatchGPT is more defensible than a generic "ChatGPT wrapper" because live voice + dictation + a purpose-built watch UI is a real native interaction model, not a repackaged website — but the wrapper-app rejection pattern under 4.2 is explicitly called out for "AI wrapper" apps, so demo notes and a distinctive on-watch UX matter at submission.
- Sources: [technetexperts guide](https://www.technetexperts.com/guideline-4-2-minimum-functionality/); [PTKD Journal — AI wrapper 4.2 rejections](https://ptkd.com/journal/guideline-4-0-design-minimum-functionality-ai-wrapper) (accessed 2026-09-24)

### 1.4 Guideline 5.1.2(i) — NEW (Nov 13, 2025): third-party AI data-sharing disclosure

- **This is the single most important new compliance item for WatchGPT.** Effective Nov 13, 2025, Apple added: apps must "clearly disclose where personal data will be shared with third parties, including with third-party AI, and obtain **explicit permission** before doing so."
- Applies squarely to WatchGPT: every dictation/voice utterance is sent off-device to your server, then to OpenRouter-routed model providers and realtime voice APIs — this is exactly the pattern the rule targets (cloud LLM calls trigger it even if pseudonymized; on-device-only processing would not).
- Practically: name the provider(s) (or at least "third-party AI providers via OpenRouter," disclose what's sent and why, and get an explicit consent tap — not just a privacy-policy link — before the first request goes out. Enforcement has been consistent since rollout (~6 months of case history by Sep 2026 rejections reported).
- Sources: [DEV.to breakdown of 5.1.2(i)](https://dev.to/arshtechpro/apples-guideline-512i-the-ai-data-sharing-rule-that-will-impact-every-ios-developer-1b0p); [TechCrunch, Nov 13 2025](https://techcrunch.com/2025/11/13/apples-new-app-review-guidelines-clamp-down-on-apps-sharing-personal-data-with-third-party-ai); [Stora implementation guide](https://stora.sh/blog/2026-05-06-apple-ai-consent-rule-5-1-2-i-implementation-guide) (accessed 2026-09-24)
- **Action item:** build a one-tap, one-time (or first-run) consent screen naming "your query/voice audio is sent to our servers and processed by third-party AI models to generate a response" before any first API call.

### 1.5 Age ratings — 2025/2026 overhaul (13+/16+/18+)

- Announced Jul 24, 2025: new categories **13+, 16+, 18+** replace 12+ and 17+ (4+ and 9+ remain). Compliance questionnaire deadline was **Jan 31, 2026** (passed); apps that haven't completed the new questionnaire are blocked from new submissions/updates.
- Relevant new question categories include AI-chat/generative content exposure — Apple's July 2025 guidance explicitly asks developers to account for how AI features (chatbots/assistants) might produce sensitive content when self-rating.
- **Recommendation:** WatchGPT should self-rate conservatively (likely 13+ or 16+, not 4+) given open-ended generative text/voice output cannot be fully content-filtered, and answer the AI-content questionnaire honestly to avoid a rejection/pull-down later.
- Sources: [MacRumors, Jul 25 2025](https://www.macrumors.com/2025/07/25/apple-overhauls-app-store-age-ratings/); [PTKD Journal 2026 explainer](https://ptkd.com/journal/app-store-age-ratings-2025-update) (accessed 2026-09-24)

### 1.6 Apple Small Business Program (15%)

- Cuts Apple's commission from 30% → **15%** on paid apps, one-time IAP, and subscriptions for developers with ≤$1M prior-year proceeds (across associated accounts). New/first-year developers qualify automatically. Rate change takes effect ~15 days after the enrollment month ends; exceeding $1M mid-year reverts you to 30% for the rest of that year.
- A solo founder pre-revenue clearly qualifies — **enroll on day one** in App Store Connect; there's no downside.
- Source: [Apple Developer — Small Business Program](https://developer.apple.com/app-store/small-business-program/); [RevenueCat guide](https://www.revenuecat.com/blog/engineering/small-business-program) (accessed 2026-09-24)

### 1.7 Guideline 4.8 — Login Services (Sign in with Apple)

- Only triggers if you use a **third-party social login** (Google, Facebook, etc.) as the account setup/auth method — then you must also offer an equivalent privacy-preserving alternative (Sign in with Apple satisfies it automatically). Apps using **only their own** email/account system, or **no login at all**, are exempt from 4.8 entirely.
- Source: [PTKD Journal 4.8 explainer](https://ptkd.com/journal/app-store-rejection-4-8-sign-in-with-apple-requirement-fix); [9to5Mac, Jan 2024 policy update](https://9to5mac.com/2024/01/27/sign-in-with-apple-rules-app-store/) (accessed 2026-09-24)
- **Implication:** if WatchGPT goes with the "no login, StoreKit-receipt-as-identity" model (see §3), 4.8 doesn't apply at all — one more reason it's the simplest path.

### 1.8 Guideline 5.1.1(v) — Account deletion

- Any app that supports account creation **must** let users delete the account (not just deactivate) from inside the app; if using Sign in with Apple, must also revoke the Apple token server-side via Apple's REST API on deletion. In force since June 30, 2022, actively enforced.
- Source: [Apple Developer News](https://developer.apple.com/news/?id=12m75xbj); [Apple Developer Forums](https://developer.apple.com/forums/thread/693997) (accessed 2026-09-24)
- **Implication:** if WatchGPT has *no account system* (device/receipt-based identity only), this guideline likely doesn't apply — another point in favor of the no-login model — but you'll still want an in-app "delete my data" action to satisfy the spirit of the rule and general privacy hygiene/GDPR-style requests.

### 1.9 Trademark: "GPT" / "ChatGPT" / "Claude" in app name or metadata

| Mark | Rule | Source |
|---|---|---|
| **GPT / ChatGPT** (OpenAI) | OpenAI's brand guidelines explicitly **do not permit** third parties to use "GPT" or model names in app/product/company names — cited concern is user confusion with OpenAI's own products. OpenAI has been actively sending takedown/rename requests to companies using "GPT" in branding. | [OpenAI brand guidelines](https://openai.com/brand/); [Slator report on enforcement](https://slator.com/openai-hunts-down-companies-using-trademarked-gpt-in-brand/) (accessed 2026-09-24) |
| **Claude** (Anthropic) | Anthropic's Trademark Guidelines: third parties may not use Anthropic/Claude names or logos as part of their own product/company name or logo, or in any way implying endorsement/partnership, without prior written permission. | [Anthropic Trademark Guidelines](https://www.anthropic.com/legal/trademark-guidelines) (accessed 2026-09-24) |
| **Recommendation** | **Do not name the app "WatchGPT"** for public launch, and avoid "GPT"/"ChatGPT"/"Claude" in the App Store name, subtitle, or keyword field tied to branding claims. A neutral name ("model-agnostic AI on your wrist") sidesteps both a likely App Store trademark rejection and a takedown request. Referring to *which models are supported* inside descriptive body text ("powered by models including GPT-5 and Claude" as a factual, nominative reference) is lower-risk than using the mark *as* the product name — but still worth a one-line legal sanity check before submission. |

---

## 2. Pricing benchmarks

### 2.1 Direct competitors (Apple Watch AI chat apps)

| App | Platform pricing | Model | Source |
|---|---|---|---|
| **Petey** | Watch: **$4.99 one-time** (unlimited on-watch requests using their backend). iPhone: free 2-week trial → **$6.99/mo** subscription (cheaper annual option), or bring-your-own-API-key for a **$3.99** one-time unlock instead of subscribing. | Hybrid: cheap one-time unlock on watch, subscription on phone, BYO-key escape hatch | [petey.app FAQ](https://petey.app/faq/); [gHacks](https://www.ghacks.net/2023/03/31/introducing-petey-accessing-chatgpt-on-your-apple-watch/) (accessed 2026-09-24) |
| **Watch AI Chat / Open Chatbot** | **$3.99/week, $9.99/month, $24.99/year** | Tiered time-boxed subscription | App Store listing (accessed 2026-09-24) |
| **Iris: VoiceGPT for Apple Watch** | **$4.99/month** after a 3-day trial | Flat subscription | App Store listing (accessed 2026-09-24) |
| **WristGPT** | Free / Pro / Max tiers (specific prices not confirmed) **(unverified)** | Freemium tiered | App Store listing (accessed 2026-09-24) |

Takeaway: incumbents cluster around **$5–7/month** (or a cheap one-time watch-only unlock around **$5**), all pass model cost through a markup rather than metering minutes explicitly.

### 2.2 Frontier AI subscriptions (what users already pay / compare against)

| Product | Price (Sep 2026) | Notes |
|---|---|---|
| ChatGPT Plus | **$20/mo** | Standard tier |
| ChatGPT Go | **$8/mo** | Budget tier, global rollout Jan 2026 |
| ChatGPT Pro | **$100/mo** (new Apr 9, 2026) | Heavy-use tier |
| Claude Pro | **$20/mo** | Standard tier |
| Claude Max | **$100 / $200 per mo** | 5x / 20x usage |
| Google AI Pro (was "Gemini Advanced") | **$19.99/mo** | Name retired early 2026 |
| Google AI Ultra | **$249.99/mo** (intro $124.99/mo x3 mo) | Top tier |
| Perplexity Pro | **$20/mo** | Standard tier |

Source: [PricePerToken 2026 subscription comparison](https://pricepertoken.com/subscriptions); [SurePrompts 2026 comparison](https://sureprompts.com/blog/ai-subscription-plans-compared-2026) (accessed 2026-09-24)

Takeaway: the market has converged on **$20/mo** as the default "serious user" price point, with a **~$8–10/mo** budget tier below it. Users already paying $20/mo for ChatGPT Plus/Claude Pro on their phone are a plausible upsell audience for a **companion/access** product (WatchGPT as *how* they reach a model on their wrist, not a competing subscription) — or WatchGPT can be priced as a standalone convenience product at the lower **$5–10/mo** band that watch-only competitors occupy.

### 2.3 Underlying voice/inference cost structure (why usage caps matter)

- **OpenAI Realtime voice API**: priced in audio tokens, roughly **$0.03–0.05/min** for full "gpt-realtime" models, **~$0.016/min** for mini variants; output audio costs 2x input. Real-world costs vary a lot with turn-taking/silence. [HackerNoon 2026 measured-sessions report](https://hackernoon.com/openai-realtime-api-pricing-in-2026-real-world-data-from-4000-measured-sessions); [TokenMix blog](https://tokenmix.ai/blog/openai-realtime-voice-api-2026-cost-latency) (accessed 2026-09-24)
- **ElevenLabs** (comparable consumer voice-AI vendor) prices its own consumer plans as a **credit pool "like a cellphone plan"**: Free ~10 min TTS + 15 min voice-agent/mo; Starter $6, Creator $22 (~first month $11), Pro $99, with **per-minute overage fees ($0.17–0.18/min)** once the pool is used up. This is a directly analogous "fair-use minutes + overage" model. [Cekura ElevenLabs pricing breakdown](https://www.cekura.ai/blogs/elevenlabs-pricing); [Flexprice breakdown](https://flexprice.io/blog/elevenlabs-pricing-breakdown) (accessed 2026-09-24)
- Takeaway: **usage-capped ("fair use") minutes bundles with metered overage are the norm** in consumer voice AI, precisely because live voice inference cost scales with minutes in a way flat subscriptions don't absorb well at high usage. A solo founder fronting the inference bill needs this cap to avoid being the exit-liquidity for power users.

### 2.4 Recommended pricing model

Given the goal of "absolutely simple," two viable shapes — recommend **Option A**:

**Option A — Single tier + fair-use cap (recommended for v1)**
- One paid plan, e.g. **$9.99/mo**, free 7-day trial (or a small number of free messages/minutes with no card required, to lower onboarding friction).
- Includes **unlimited dictation-based (text) chat** (cheap — LLM text tokens only) + a **fair-use live-voice allowance** (e.g., 30–60 min/month of realtime voice, in line with ElevenLabs' consumer bundles), with either graceful degradation (fallback to dictation) or a small top-up IAP after the cap, rather than metered overage billing (keeps it simple — no surprise bills).
- Rationale: one price, one decision for the user ("is this worth $10/mo") mirrors the successful incumbents' $5–10 band while insulating the founder from unbounded realtime-voice cost exposure. Avoids the complexity of a 2-tier "Dictation vs Live Voice" SKU, which adds a purchase decision most users won't want to make on a watch screen.

**Option B — Two tiers ("Dictation" / "Live Voice") — only if cost data post-launch shows Option A's cap is regularly hit**
- Dictation-only tier ~$4.99/mo (cheap, matches Iris/Watch-AI-Chat pricing) for cost-sensitive users; Live Voice tier ~$14.99/mo with a larger minutes pool for power users.
- Rationale to defer: adds a decision + doubles the paywall/testing surface for a solo founder pre-product-market-fit; only worth it once usage data shows a bimodal user base.

Either way: **meter and cap live-voice minutes server-side from day one** — it is the one line item that can bankrupt a solo founder's OpenRouter/realtime bill if unbounded.

---

## 3. Account model

| Model | How it works | Pros | Cons |
|---|---|---|---|
| **Sign in with Apple on watchOS** | User authenticates via Apple ID (Face ID/passcode relay from paired iPhone or Watch passcode); server maps Apple's opaque user ID to an account. | Real portable identity (works if the user changes device); satisfies 4.8 cleanly since it's Apple's own system; supports future iPhone companion / multi-device sync. | Extra screen(s)/taps in an already tiny watch UI; still requires **account deletion support (5.1.1(v))**; Apple ID relay UX on watch has historically been clunky for some users. |
| **Anonymous device account keyed to StoreKit `originalTransactionID` / receipt** | No login screen at all — first launch immediately provisions a server-side "account" the moment a subscription purchase (or trial) completes, identified by the App Store transaction, not a user credential. | **Zero onboarding friction** — literally "install, tap subscribe, start talking" which matches the "absolutely simple" goal; no 4.8/5.1.1(v) obligations since there's no user-facing account/login; no password/email to manage as a solo founder. | Identity is tied to **one Apple ID / one device family** — restoring on a new Watch requires "Restore Purchases," and there's no cross-platform (Android, web) story later; harder to do customer support ("who are you") without some pairing code; losing/wiping the device with no iCloud-linked backup could strand chat history unless it's synced via iCloud key-value or CloudKit rather than tied purely to the receipt. |

**Recommendation:** **anonymous device/receipt-based identity for v1**, with StoreKit's `originalTransactionId` (or an App Store server-notifications-derived ID) as the server-side account key, and chat history sync via **CloudKit** (private database, keyed to the user's iCloud account, not a WatchGPT login) to solve the "restore on new device" problem without inventing a login system. This is the simplest path that also sidesteps Guidelines 4.8 and 5.1.1(v) entirely. Add Sign-in-with-Apple later only if/when an iPhone companion or web dashboard is built and cross-device identity actually matters.

---

## 4. Privacy / compliance basics

| Item | Requirement / recommendation | Source |
|---|---|---|
| **Privacy Nutrition Label** | Required at submission (App Store Connect "App Privacy" questionnaire). Must accurately disclose: audio data collected (voice dictation), and that it's sent to third parties (OpenRouter-routed model providers) — this is separate from, but closely related to, the new 5.1.2(i) in-app consent requirement. Mislabeling is an explicit enforcement risk ("labels have no value if they're based on lies"). | [Apple Developer — App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/) (accessed 2026-09-24) |
| **Not training on user data** | Not an Apple mandate, but a strong trust/marketing claim to make explicitly (mirrors Anthropic's own default of not training on commercial API data) — put it in the privacy policy and the 5.1.2(i) consent copy. **(verify your specific OpenRouter/provider contracts guarantee no-training-by-default before claiming this — providers vary.)** | [sensai.fit 2026 AI privacy piece](https://www.sensai.fit/blog/ai-fitness-app-data-privacy-2026) (accessed 2026-09-24) |
| **Data retention** | Define and publish a concrete retention window (e.g., "voice audio deleted after transcription; transcripts retained N days unless the user saves them") — the FTC's 2026 COPPA amendments now *require* written data-retention policies with deletion timelines for any app that could reach children, which is good practice generally even if WatchGPT age-gates adults-only. | [Respectlytics COPPA 2026 summary](https://respectlytics.com/blog/coppa-rules-2026-mobile-app-compliance/) (accessed 2026-09-24) |
| **COPPA / age gating** | FTC's amended COPPA Rule became enforceable **April 22, 2026**: expands "personal information" (incl. biometric identifiers), requires opt-in consent for third-party data sharing, and requires **neutral age gates** for mixed-audience apps. Practical path: self-rate 13+ (or 16+) on the App Store, state a minimum age (e.g., 16+) in the ToS, and do NOT knowingly target or market to children — avoids being deemed "directed to children" and the full COPPA compliance burden. | [Respectlytics](https://respectlytics.com/blog/coppa-rules-2026-mobile-app-compliance/); [banthebots.org 2026 explainer](https://www.banthebots.org/explainers/ai-chatbot-age-requirements) (accessed 2026-09-24) |
| **Voice data handling** | Given 5.1.2(i): disclose that raw voice audio is transmitted to your server and to third-party realtime-voice/model APIs; state whether raw audio is stored or discarded post-transcription (discarding audio post-transcription is the lower-liability default). | See §1.4 above |
| **Account deletion** | Only a hard Apple *requirement* if you support account creation (5.1.1(v)). Recommend building an in-app "Delete my data" action anyway (maps to the receipt-keyed record + CloudKit data) even under the anonymous-account model — good practice and simplifies any future GDPR/CCPA-style requests. | See §1.8 |

---

## 5. Distribution: watch-only vs. + iPhone companion

| Factor | Watch-only (no iPhone app) | + iPhone companion |
|---|---|---|
| **Discoverability** | Since watchOS 6, the on-watch App Store lets users search/browse and install directly from the wrist (Scribble/dictation/keyboard search, curated collections) — a standalone app is fully discoverable without ever touching an iPhone. Apple's general developer messaging also treats independent watch apps as a first-class distribution model, not a lesser one. | Same on-watch discoverability, **plus** presence in the (much higher-traffic) iPhone App Store search/browse, App Store editorial features, and share links that work for iPhone users who haven't yet paired a Watch. |
| **Onboarding** | Everything must happen in the tiny watch UI: paywall, consent screen (5.1.2(i)), account/receipt bootstrap. Feasible but cramped — every extra screen costs more relative to screen real estate than on iPhone. | iPhone gives room for a proper onboarding flow (explain the product, show the consent/disclosure clearly, run the paywall) before the user ever puts it on their wrist — much easier to do "absolutely simple but not confusing" well. |
| **Payments** | StoreKit purchase sheet works on-watch (see §1.2) but is a small, low-context UI for a purchase decision; no in-watch way to do web/Stripe checkout comfortably (no Safari). | Paywall and (if ever used) external checkout are far more natural on a full iPhone screen with real Safari. |
| **Settings / support** | Limited — small screen for toggles, no text-heavy settings, hard to do things like "manage voice minutes usage" or view usage history comfortably. | Natural home for account/usage dashboard, support links, longer chat history review, export, etc. |
| **Engineering cost for a solo founder** | One target, one codebase, ships faster — matches "absolutely simple" both for the user and for the founder's own bandwidth. | Meaningfully more surface area: a second app target, a second App Store listing to maintain, a second review pass, and WatchConnectivity/CloudKit sync code between the two. |

**Recommendation:** **Ship v1 as watch-only.** It's fully discoverable via the on-watch App Store, keeps the founder's build/maintenance surface to one target (directly serves the "absolutely simple" constraint on the build side too), and StoreKit purchases and the 5.1.2(i) consent screen are both achievable natively on-watch even if cramped. **Revisit an iPhone companion after initial traction** — the strongest trigger to add one would be: (a) onboarding/paywall conversion data showing users bounce on the watch-only flow, (b) wanting a proper settings/usage dashboard, or (c) wanting the higher-traffic iPhone App Store surface area for growth. A companion app is additive later, not a launch blocker now.

---

## Open items to verify before submission (flagged "(unverified)" above)

1. Whether watch-only (no-iPhone-companion) apps hit any hard StoreKit/App Store Connect blockers for subscriptions in current tooling — spike this early.
2. Whether the US anti-steering ruling's "no entitlement needed for external links" language has been confirmed by Apple to apply on watchOS specifically (vs. iOS/iPadOS where most commentary is focused).
3. OpenRouter's Terms of Service on using it as the backend for a paid consumer app — search results suggest a "no reselling API access / no competing service" clause; **read the current openrouter.ai/terms text directly** before finalizing the OpenRouter dependency, since this affects the entire business model's legality, not just an App Store nuance. ([openrouter.ai/terms](https://openrouter.ai/terms) — accessed for URL only, not content-verified 2026-09-24)
4. Confirm current no-training defaults contractually with each model provider routed through OpenRouter before making a "we don't train on your data" marketing/privacy claim.
