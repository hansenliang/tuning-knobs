# WatchGPT: Can users bring their existing ChatGPT / Claude / Gemini subscription?

*Compiled 2026-09-24. Many primary pages (openai.com, help.openai.com, openrouter.ai) were blocked by this environment's egress proxy, so some claims rest on search-result excerpts and secondary coverage. Those are marked **(secondary)**. Anything not confirmed is marked **(unverified)**.*

---

## TL;DR

- **No, not legitimately today.** None of OpenAI, Anthropic or Google offers a sanctioned way for a third-party **consumer app** to bill inference to a user's Plus/Pro, Pro/Max or AI Pro plan.
- **Anthropic prohibits it outright** in writing. **Google bans accounts** that do it. **OpenAI tolerates it for open-source coding tools only**, through the Codex OAuth client. That is a gray area, it is not a program, and OpenAI is enforcing against proxy/sharing setups (Aug 2026).
- **OpenAI is building "ChatPass"** (metered subscription sharing with approved apps). It is unreleased and not documented (secondary). Watch it.
- **Legitimate bridges that work now:**
  1. **OpenRouter OAuth PKCE.** The user connects their own OpenRouter account and pays OpenRouter directly. This fits the existing OpenRouter architecture.
  2. **BYOK API keys.**
  3. **Apple's `PrivateCloudComputeLanguageModel` on watchOS 27.** It's free to us under 2M first-time downloads, and users with **iCloud+** get higher limits. That iCloud+ allowance is the only "subscription the user already pays for" that a third-party watch app can legitimately use.

---

## 1. OpenAI (ChatGPT Plus/Pro)

| Item | Finding | Source |
|---|---|---|
| "Sign in with ChatGPT" (May 2025) | OpenAI explored it and previewed it in Codex CLI. At that point it linked a ChatGPT account to an API org, with $5/$50 of API credit as a sign-up bonus. | [TechCrunch 2025-05-27](https://techcrunch.com/2025/05/27/openai-may-soon-let-you-sign-in-with-chatgpt-for-other-apps/) |
| "Sign in with ChatGPT" GA beta (**2026-08-02**) | **Identity only.** The partner receives the user's name, email and avatar. It "does not independently share conversations, memory, files, **tokens, billing information**." Launch partners are Airtable, GitLab, HubSpot, Notion, Supabase and Vercel. We found no public self-serve developer signup. | [OpenAI Help: Sign in with ChatGPT](https://help.openai.com/en/articles/20001410-sign-in-with-chatgpt) (secondary, via search excerpt); [Supabase blog](https://supabase.com/blog/sign-in-with-chatgpt-beta); [Vercel changelog](https://vercel.com/changelog/sign-in-with-chatgpt-is-now-available-on-vercel) |
| Bill inference to the user's plan? | **No official mechanism.** Developers are still asking for one: [community thread](https://community.openai.com/t/let-third-party-apps-use-a-user-s-chatgpt-plan-instead-of-developer-funded-api-usage/1396834) and [codex#10974](https://github.com/openai/codex/issues/10974). | links |
| "ChatPass" / "Subscription sharing" | Strings in the Codex desktop client describe an allowance meter for "ChatPass applications," a separately metered share of a user's plan. The server had not enabled it as of 2026-08-27. OpenAI has published no docs, eligibility rules or date. | [RuntimeWire](https://runtimewire.com/article/openai-is-building-subscription-sharing-for-ai-apps) **(secondary, reverse-engineered)** |
| Third-party harnesses on ChatGPT plans | OpenAI's Tibo Sottiaux publicly welcomed third-party **coding** harnesses on ChatGPT subscriptions: "build on top of [Codex] directly, which includes ChatGPT [login]" (Jan 2026). Pi and OpenCode reportedly make up about 10% of Codex traffic (mid-2026). These tools reuse **the Codex OAuth client** (browser or device-code flow) and call the Codex backend. | [Tibo on X, ~2026-01-10](https://x.com/thsottiaux/status/2009714843587342393); [Manifest, ~Jul 2026](https://manifest.build/blog/chatgpt-plus-tokens-third-party-harnesses/) (secondary) |
| Enforcement | On **2026-08-21** Tibo said many accounts with limit problems were routing subscriptions through **sub2api**, a proxy that re-serves a subscription as shared API traffic, and that this is "not supported." Account bans have also been reported. | [explainx.ai Aug 2026](https://explainx.ai/blog/codex-usage-limits-sub2api-sign-in-chatgpt-august-2026) (secondary); [community ban report](https://community.openai.com/t/codex-chatgpt-pro-account-banned-with-no-warning-no-explanation-18-month-subscriber/1381906) |
| Terms of Use | The Terms bar sharing credentials or "mak[ing] your account available to anyone else" and "automatically or programmatically extract[ing] data or Output." They neither explicitly permit nor explicitly forbid non-OpenAI clients. Commentators describe the position as "tolerated, not committed." | [OpenAI Terms of Use](https://openai.com/policies/row-terms-of-use/); [Account sharing policy](https://help.openai.com/en/articles/10471989-openai-account-sharing-policy) |
| Could WatchGPT reuse the Codex OAuth client? | It is *technically* possible: device-code login works on devices without a browser once the user enables "device code authorization" in ChatGPT security settings. But it means a closed-source, paid, **non-coding** consumer app impersonating OpenAI's Codex client and calling an undocumented `chatgpt.com/backend-api/codex/*` endpoint. That is outside what OpenAI has blessed (OSS coding tools), and routing through our server would look like sub2api. | [Codex device-auth guide](https://codex.danielvaughan.com/2026/04/01/codex-cli-authentication-flows-credential-management/) (secondary) |

**Verdict (OpenAI):** there's no legitimate path today. Reusing the Codex client is a ToS gray area plus an App Store 5.2.2 problem (see §5). Re-check for ChatPass or a "Sign in with ChatGPT" inference scope every quarter.

---

## 2. Anthropic (Claude Pro/Max)

| Item | Finding | Source |
|---|---|---|
| **Official policy (current)** | "Anthropic does not permit third-party developers to offer Claude.ai login into their own applications, or to route requests through Free, Pro, or Max plan credentials on behalf of their users. Moreover, developers may not collect, store, or intermediate Claude.ai credentials or session tokens." Developers "should use API key authentication." Anthropic "may [enforce] without prior notice." | [Claude Code docs: Legal & compliance](https://code.claude.com/docs/en/legal-and-compliance) (fetched 2026-09-24) |
| Consumer Terms (eff. 2025-10-08) | These prohibit accessing the Services "through automated or non-human means ... except when ... via an Anthropic API Key or where we otherwise explicitly permit it." They also bar sharing account credentials. | [Consumer Terms](https://www.anthropic.com/legal/consumer-terms) (fetched) |
| Timeline | **2026-01-09:** server-side block of subscription OAuth in OpenCode, Cline, Roo and similar tools. **2026-02-19:** docs updated to say third-party OAuth use violates the terms. **2026-04-04:** OpenClaw and other third-party harnesses moved to metered "extra usage." **2026-05-14:** Agent SDK credit plan announced. **2026-06-15:** that plan **paused**. | [HN](https://news.ycombinator.com/item?id=46549823); [WinBuzzer 2026-02-19](https://winbuzzer.com/2026/02/19/anthropic-bans-claude-subscription-oauth-in-third-party-apps-xcxwbn/); [TechCrunch 2026-04-04](https://techcrunch.com/2026/04/04/anthropic-says-claude-code-subscribers-will-need-to-pay-extra-for-openclaw-support/) |
| Agent SDK + plan | Agent SDK, `claude -p` and "third-party apps that authenticate with your Claude subscription through the Agent SDK" still draw from plan limits. This covers the **user running** the Agent SDK or Claude Code locally. It is **not** permission for a developer to ship Claude.ai login. The Agent SDK also needs Claude Code/Node, so it can't run on watchOS. | [Claude Help: Agent SDK with your plan](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan) (fetched) |
| "Sign in with Claude" / partner program | **None for consumer apps.** Anthropic's official Swift package **ClaudeForFoundationModels** (v0.1.0 beta, supports watchOS 27) offers `.appAttest(clientID:)` (**billed to the developer's Anthropic workspace**), `.apiKey` and `.proxied`. It has no user-subscription mode. | [github.com/anthropics/ClaudeForFoundationModels](https://github.com/anthropics/ClaudeForFoundationModels) (fetched) |
| Real-world example | JetBrains ThinkRail issue #437 (2026-09-07) found that its "Anthropic Sign in" (Claude Code client ID plus spoofed headers) was actually billed as **extra usage, not the plan**, and violated the terms. The proposed fix was to remove it. | [JetBrains/thinkrail#437](https://github.com/JetBrains/thinkrail/issues/437) |

**Verdict (Anthropic):** it is explicitly prohibited and actively enforced. Don't do it.

---

## 3. Google (Gemini / Google AI Pro & Ultra)

- **No sanctioned program.** A Google AI Pro/Ultra subscription does not grant Gemini API quota. Developers are still asking for one on the forum ([forum thread](https://discuss.ai.google.dev/t/allow-ai-pro-subscription-quota-to-be-used-for-gemini-api/177882), [thread](https://discuss.ai.google.dev/t/gemini-subscription-access-for-third-party-apps-is-a-sanctioned-program-planned/175577)). "Sign in with Google" is identity/Workspace scopes only.
- **Enforcement:** in Feb 2026 Google restricted or banned paid AI Pro/Ultra accounts that routed Gemini CLI/Antigravity OAuth through OpenClaw, OpenCode and similar tools, with no refunds reported ([WinBuzzer 2026-02-23](https://winbuzzer.com/2026/02/23/google-bans-ai-subscribers-openclaw-no-refunds-xcxwbn/)). The Gemini CLI maintainers call "using Gemini CLI OAuth with third-party software" a "policy-violating use case" ([gemini-cli#22970](https://github.com/google-gemini/gemini-cli/discussions/22970), fetched). Consumer-account Code Assist OAuth was reportedly deprecated on 2026-06-18 ([Syntackle](https://syntackle.com/blog/google-gemini-ai-subscription-with-opencode/), secondary).
- Google also ships a Gemini Swift package for Foundation Models, which is API-billed (unverified details).

**Verdict (Google):** it isn't possible, and trying it gets user accounts banned.

---

## 4. Alternative legitimate bridges

### 4a. OpenRouter OAuth PKCE (strongest fit)
- **How it works:** send the user to `https://openrouter.ai/auth?callback_url=…&code_challenge=…&code_challenge_method=S256` (optionally with `key_label`). They log in and approve. We receive `?code=…` and `POST /api/v1/auth/keys` with `code` and `code_verifier`, which returns a **user-controlled API key**. The code is single-use and expires in 10 minutes. The callback can be an https URL or localhost. [OpenRouter OAuth docs](https://openrouter.ai/docs/guides/overview/auth/oauth) (secondary: page blocked here, confirmed via search excerpts).
- **Billing:** usage draws on the **user's** OpenRouter credits, and the user can revoke or limit the key on openrouter.ai. We pay $0 for inference.
- **Watch UX:** run the flow on the iPhone companion with `ASWebAuthenticationSession` and a universal-link https callback, then sync the key to the watch via Keychain/WatchConnectivity. On the watch alone, `ASWebAuthenticationSession` exists but a login on the watch screen is painful (unverified). Alternatively, use a QR/pairing code approved on the phone.
- **Caveat:** this is **not** the user's ChatGPT or Claude subscription. It is a new prepaid balance. It appeals to power users but won't convert people who "already pay $20 for ChatGPT."

### 4b. BYOK (user pastes an OpenAI, Anthropic, Gemini or OpenRouter API key)
- This is legitimate and widely shipped (Petey sells a $3.99 BYOK unlock; see `05-business-appstore.md`). API billing is **separate** from the consumer subscription, and most Plus/Pro users have no API account.
- Typing a key on the watch isn't workable. Paste it on the iPhone and store it in the shared Keychain. The key must never pass through our server. Otherwise we become an intermediary, and that creates privacy and 5.1.2(i) obligations.

### 4c. Handoff to official apps via Shortcuts / App Intents
- The ChatGPT iOS app exposes an **"Ask ChatGPT"** Shortcuts action. A user-built shortcut containing it can be run **from Apple Watch** (Shortcuts app, Siri, complication or Action Button), provided the shortcut has run once on iPhone first. It executes on the paired iPhone, bills the user's own ChatGPT plan, and is fully legitimate. [iGeeksBlog](https://www.igeeksblog.com/how-to-use-chatgpt-on-iphone-apple-watch/); [AskWatch](https://askwatch.app/en/chatgpt-on-apple-watch) (secondary)
- **Limits for WatchGPT:** a third-party watch app **cannot invoke another app's App Intent** or run a shortcut programmatically and read back the result. The watch has no `shortcuts://` run-and-return path (unverified; nothing public found). At most, WatchGPT could *document* a "ChatGPT on your wrist" shortcut. That helps users but isn't a product feature. It needs the iPhone nearby, with no streaming, no voice mode and no history in our UI.
- The Claude iOS app's Shortcuts actions weren't researched in detail (unverified).

### 4d. Apple Intelligence / Foundation Models (new in OS 27, WWDC 2026)
- **`PrivateCloudComputeLanguageModel`** is available on **watchOS 27**. It needs no account or API key. It is **free to developers with under 2M first-time downloads** (Small Business Program), and users draw from a daily limit that is **higher for iCloud+ subscribers**. It has a 32K context and reasoning, but it is Apple's model, not GPT or Claude. [WWDC26 "What's new in Foundation Models"](https://developer.apple.com/videos/play/wwdc2026/241/) (fetched); [socket-link/ampere#757](https://github.com/socket-link/ampere/issues/757)
- **Third-party providers in Foundation Models** (Anthropic's `ClaudeForFoundationModels`, Google's package) plug into the same `LanguageModelSession` API but are **billed to the developer** (App Attest client ID, API key or proxy). There is no user-subscription mode. [WWDC26 session 339](https://developer.apple.com/videos/play/wwdc2026/339/)
- **iOS 27 "Extensions"** let users choose ChatGPT, Claude or Gemini to power Siri, Writing Tools and Image Playground, signing in with their provider account. This is a **provider-facing** API: AI companies plug *into* Siri. We found no public API that lets a third-party app send prompts to the user's chosen Extension. Whether Extensions shipped in 27.0 and are available on watchOS is unverified. [Let's Data Science](https://letsdatascience.com/blog/apple-ios-27-extensions-claude-grok-third-party-ai) (secondary)

### 4e. MCP / ChatGPT Apps SDK / Claude connectors (reverse direction)
- These let WatchGPT's *data or tools* appear **inside** ChatGPT or Claude, where the user's plan pays for inference ([Apps in ChatGPT](https://openai.com/index/introducing-apps-in-chatgpt/)). They don't help a watch UI and aren't inference billing for our app. A "WatchGPT connector" would only make sense to push chat history or reminders into ChatGPT/Claude.

---

## 5. Risk assessment (for any unofficial subscription-token reuse)

| Risk | Detail |
|---|---|
| **ToS / user bans** | Anthropic prohibits it explicitly and enforces without notice. Google has banned paying accounts. OpenAI has banned and rate-limited accounts behind proxies. **Our users lose their $20–200/mo accounts because of our app.** That is a reputational disaster. |
| **App Store review** | Guideline **5.2.2**: "If your app uses, accesses ... a third-party service, ensure that you are specifically permitted to do so under the service's terms ... Authorization must be provided upon request." We couldn't produce that authorization. **4.1(b)** (impersonating another service) is also a risk if we spoof Codex or Claude Code client IDs. **5.1.2(i)** requires third-party AI disclosure regardless. [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) |
| **Reliability** | Undocumented endpoints, client-ID checks, header fingerprinting and silent billing reroutes (the ThinkRail case: plan became extra usage) have all been deployed overnight (Anthropic 2026-01-09 and 2026-04-04). A core feature could die on a Friday night. |
| **Security / liability** | Storing refresh tokens for users' ChatGPT or Claude accounts makes us a high-value credential store. Anthropic explicitly forbids storing them. |
| **Economics** | Even the tolerated paths are capped by plan limits tuned for coding and chat, and vendors are clearly squeezing third-party usage (Anthropic's extra-usage shift, OpenAI's ChatPass metering). |

---

## 6. Verdict table

| Option | Legit? | Feasible now? | UX | Risk | Recommendation |
|---|---|---|---|---|---|
| Reuse **Claude** Pro/Max OAuth (Claude Code client) | **No.** Explicitly prohibited | Technically, until blocked | Great while it works | **Very high**: bans, App Store 5.2.2, billing reroutes | **Do not build** |
| Reuse **Gemini** AI Pro/Ultra OAuth (Gemini CLI/Antigravity) | **No.** Named a policy violation | Mostly dead (deprecated Jun 2026, secondary) | n/a | **Very high**: bans, no refunds | **Do not build** |
| Reuse **ChatGPT** Plus/Pro via Codex OAuth client | **Gray.** Tolerated for OSS *coding* harnesses only | Yes (device-code flow) | Good | **High**: undocumented API, non-coding use, App Store 5.2.2, sub2api-style enforcement | **Do not ship.** Prototype privately at most |
| Official "Sign in with ChatGPT" (Aug 2026) | Yes | Partner-only beta, **identity only** | n/a | Low | Nice for login later. **It does not solve billing** |
| OpenAI **ChatPass** subscription sharing | Would be | **No.** Unreleased (secondary) | Likely ideal | Unknown | **Track it.** Apply the day it opens |
| **OpenRouter OAuth PKCE** | **Yes** | **Yes** | Good (one-time phone login) | Low | **Ship as "Connect OpenRouter" power-user tier** (matches our stack) |
| **BYOK** API keys (OpenAI/Anthropic/Gemini/OpenRouter) | **Yes** | **Yes** | Poor for mainstream users; fine for nerds | Low (keep keys on device) | **Ship as a one-time unlock** (Petey model) |
| **Apple PCC `LanguageModel`** on watchOS 27 | **Yes** | **Yes** (OS 27) | Excellent: no login | Low; capped daily, Apple model only | **Use as free tier / fallback.** iCloud+ is the one "existing subscription" we can use |
| Anthropic/Google **Foundation Models packages** | Yes | Yes (beta) | Good | Low | Developer-billed. A good SDK choice for our paid tier, **not a BYO-sub** option |
| Shortcut handoff ("Ask ChatGPT" on watch) | Yes | Yes (user-built) | Mediocre: iPhone needed, no streaming or voice | None | Offer as a **help article**, not a feature |
| iOS 27 Siri **Extensions** | Yes | No consumer API for third-party apps (unverified) | n/a | n/a | Monitor |
| MCP / Apps SDK / connectors | Yes | Yes | Wrong direction | Low | Not relevant to inference billing |

**Bottom line for the founder:** users **cannot** legitimately plug their ChatGPT or Claude consumer subscription into WatchGPT today. Anthropic forbids it, Google bans for it, and OpenAI only tolerates it for OSS coding tools. The plan:

1. Our own paid tier (IAP) on OpenRouter or the Foundation Models provider packages.
2. A **"Connect OpenRouter" (PKCE) / BYOK** tier so power users pay providers directly.
3. Apple **PCC** as a zero-cost free tier on watchOS 27.
4. Keep watching OpenAI **ChatPass**, the only credible future path to "use your ChatGPT plan."
