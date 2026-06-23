# tuning-knobs

A Claude Code skill for **visually tuning a frontend component's parameters** — spacing, sizing, radius, shadow, color, animation duration and easing — with knobs and switches instead of nudging numbers one at a time in chat.

You drag sliders, watch a live preview, and click **Apply**. Claude reads the values you dialed in and **writes them straight back into your real source code.**

<!-- Add a screenshot or a GIF (a clip from your demo works great) at docs/screenshot.png, then uncomment:
![tuning-knobs harness](docs/screenshot.png)
-->

## Why this exists

Tuning a component through chat is a slow loop: "make padding 24px" → look → "try 20" → look → "actually 22" → look. Every round is a full request.

Anthropic's official [`playground`](https://claude.com/plugins/playground) plugin already builds interactive HTML explorers — but it ends by generating a **prompt you copy-paste back** to Claude. `tuning-knobs` **closes that loop**: there's no prompt to paste. You click Apply, and the chosen values are written directly into the component file. That's the whole difference, and it's the whole point.

## Install

```
/plugin marketplace add hansenliang/tuning-knobs
/plugin install tuning-knobs
```

## Use

Just ask, while you're tuning a component:

> "Give me knobs to dial in the spacing and shadow on this card."

Claude will:

1. **Read the component** and enumerate its tunable parameters.
2. **Generate a harness** — a single self-contained HTML file with one control per parameter and a faithful live preview.
3. **Serve it** with a tiny bundled local server and hand you a `localhost` URL.
4. You **dial it in by eye** and click **Apply to code**.
5. Claude **writes the values back** into your real source (CSS custom properties, Tailwind tokens, inline styles, props, or motion config) and shows you the diff.

That's the closed loop. No copy-paste.

## How it works

- **`harness-template.html`** — a self-contained, dependency-free single file. Dark theme, grouped controls (range / number / color / select / toggle), a live preview pane, and a values payload. Claude adapts two marked regions per component: the parameter list and the preview render. Everything else is a generic engine.
- **`apply_server.py`** — a zero-dependency (Python stdlib only) local server. It serves the harness so the in-page **Apply** button can POST same-origin, and writes the chosen values to a JSON file Claude then reads. `--once` exits after the first Apply so the agent can simply await it. A **Copy values** button is the fallback when no server is running.

The payload records only what *changed* from defaults, so the edit Claude makes back into your code is small and intentional.

## License

MIT © 2026 Hansen Liang
