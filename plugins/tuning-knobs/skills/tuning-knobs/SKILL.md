---
name: tuning-knobs
description: Use when hand-tuning the visual or numeric parameters of a frontend component — spacing, padding, sizing, border-radius, shadow, colors, opacity, animation duration/easing — by repeatedly asking the AI to nudge values and re-checking. Use when someone wants knobs, sliders, or switches to dial a UI in by eye, or says tweaking numbers one at a time is slow or tedious.
---

# tuning-knobs

## Overview

Tuning a component's numbers through chat is a slow loop: you ask for `padding: 24px`, look, ask for `20px`, look, ask for `22px`... Each round is a full request. **Instead, build a throwaway interactive harness with one knob per parameter and a live preview, let the human dial it in by eye, then write the chosen values straight back into the real source.**

**Core principle — close the loop.** The difference from a plain prompt-generating playground is the last step: you don't hand the human a prompt to paste back. You read the values they dialed in and **edit the actual component file yourself.** The human's only job is to drag sliders until it looks right and click Apply.

## When to use

- A component has several numeric/visual parameters being tuned by feel (spacing, radius, shadow, type scale, durations, easing, colors, opacity).
- The human says some variant of "tweaking these one at a time is tedious" or "give me sliders."
- You're about to enter a nudge-look-nudge chat loop. Stop and build the harness instead.

**When NOT to use:** a single one-off value change (just edit it); logic/behavior changes (knobs tune quantities, not control flow); layout restructuring.

## Workflow

### 1. Enumerate the parameters
Read the real component source. List every value worth a knob. For each, capture:
`id`, `label`, `group`, `type` (range/number/color/select/toggle), current `value`, a sensible `min`/`max`/`step` + `unit`, and a **`target`** — how this value maps back to source (e.g. `--card-padding` CSS var, a Tailwind class slot, an inline style, a prop, or a motion-config field). The `target` is what makes write-back unambiguous later.

- **The `id` is the join key.** It flows verbatim into the values file and is what step 4 matches on. Pick it deliberately and don't rename it between generating the harness and applying — a mismatch silently drops the value.
- **Only knob a value that exists as a standalone token in the source** — ideally a CSS custom property, prop, or config field. If a value you want to tune is buried inside a shorthand (`box-shadow`, `transition`, `font`), extract it to a custom property *first* so write-back is a one-token edit. Skip values the component hardcodes and isn't ready to expose.

### 2. Generate the harness
Copy [`harness-template.html`](harness-template.html) to a working file beside the component (e.g. `Card.tuner.html`). Edit **only the two `⟨FILL⟩` regions**:
- `PARAMS` — one entry per parameter from step 1.
- `renderPreview(v)` — reproduce the component in plain HTML/CSS driven by `v` so eyeballing is honest. Match the real thing closely (fonts, colors, structure).

Leave the generic engine (controls, state, payload, Apply/Copy) untouched.

### 3. Serve it and let the human tune
Run the bundled server so the in-page **Apply** button can write to disk:
```bash
python3 apply_server.py --html Card.tuner.html --out .tuner-values.json --once
```
It prints `http://localhost:PORT`. Give the human that URL and tell them: drag the knobs until it looks right, then click **Apply to code**. With `--once` the server writes the values file and exits, so you can simply await it.
(If you can't run a server, they click **Copy values** and paste the JSON back — same payload, manual step.)

### 4. Write the values back into real source — the closed loop
Read `.tuner-values.json`. It has this shape:
```json
{ "changed": { "padding": 40, "accent": "#ff5577" },
  "all": { ... },
  "meta": { "padding": { "default": 20, "unit": "px", "target": "--card-padding" } } }
```
Write-back uses `changed` + `meta` only; `all` exists for the Copy-values fallback and you can ignore it here. **Write only `changed` values** (leaving defaults alone keeps the diff small and intentional). For each changed id, use `meta[id].target` + `unit` to edit the real source at the right place: set the CSS custom property, swap the Tailwind token, update the inline style, the prop default, or the motion config. Make precise, idempotent edits — change the number, not the surrounding code. Then show the human a short before→after summary.

### 5. Clean up
Once the human has confirmed the applied diff, delete the `.tuner.html` and `.tuner-values.json` — they're scaffolding, not artifacts. Don't delete before the diff is confirmed, and keep them if the human wants to iterate again.

## Control quality

| Parameter kind | Control | Notes |
|---|---|---|
| length (px/rem) | `range` + unit | tight min/max around the current value, step 1 (or 0.5rem) |
| duration (ms) | `range`, unit `ms` | 0–600 is plenty for UI motion; step 10 |
| easing | `select` | offer `ease-out`, a custom `cubic-bezier`, `linear` |
| color | `color` | shows hex + swatch |
| count/ratio | `number` or `range` | unitless |
| on/off | `toggle` | booleans only |

- **Sensible defaults + presets.** Seed every knob with the component's *current* value so "no change" is the starting point and the changed-count starts at 0.
- **Group related knobs** (Spacing / Color / Motion). A wall of 20 ungrouped sliders is as bad as chat.
- **Keep the preview faithful and instant.** If the preview doesn't look like the real component, the human tunes the wrong thing.

## Common mistakes

| Mistake | Fix |
|---|---|
| Generating a prompt for the human to paste back | Close the loop — read the values and edit the source yourself. |
| Renaming a knob `id` between generating and applying | The `id` is the join key into the values file — pick it once, don't rename. |
| Knobbing a value buried in a `box-shadow`/`transition` shorthand | Extract it to a CSS custom property first, then knob and write back the token. |
| Writing every value, including unchanged ones | Write only `changed`; it keeps the diff honest. |
| Preview is a rough box, not the real component | Reproduce it faithfully in `renderPreview`, or eyeballing lies. |
| Opening the harness via `file://` and Apply fails | Serve it with `apply_server.py` (same-origin) — or use Copy values. |
| Knob ranges too wide (0–1000px) | Bracket the current value; wide ranges make fine-tuning impossible. |
| Leaving `.tuner.html` lying around | Delete scaffolding after applying. |

## Files

- [`harness-template.html`](harness-template.html) — the single-file harness. Adapt the two `⟨FILL⟩` regions; leave the engine alone.
- [`apply_server.py`](apply_server.py) — zero-dependency (stdlib) local server that serves the harness and writes the values file when Apply is clicked. `--once` exits after the first Apply. Run `python3 apply_server.py --help` for flags.
