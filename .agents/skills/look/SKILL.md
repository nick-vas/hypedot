---
name: look
description: Use when the user asks how the game looks, wants its screens critiqued, or is choosing between a visual change and how it was before.
disable-model-invocation: true
---

# /look: style guide, screenshot critique, before and after

Screens are judged against a written style guide, at the resolutions the game targets, from real screenshots. The user makes
the visual calls; you show them evidence and record their choices.

## 1. The style guide (first run only)

`status -Json` returns `look.styleGuide`. If it is null, write `docs/STYLE.md` from `${CLAUDE_PLUGIN_ROOT}/ci/godot/templates/STYLE.md`
with the user, one multiple-choice question per section: target resolutions (design resolution first), palette (offer the
colours the game already uses, read from its themes and scenes), type (the roles and the one font, size and line spacing of
each, from `typography`) and smallest text size, readability rules, motion rules.
Keep the `Resolutions:` line on one line; tools read it.

Before art agents start, gather real reference (photos or video of the places and objects, in `docs/reference/`) and
link it from STYLE.md: before OutRun, Yu Suzuki and Yoji Ishii took a road trip across a continent with a video
camera. The user's rough sketches or photos are source material: agents clean, colour and add effects, keeping the
original beside the result (Hitoshi Yoneda draws by hand, scans, then adds effects; *Untold History*).

## 2. Critique

Hand the screenshots to the `godot-verifier` subagent so the images stay out of this conversation: every screen the user named
(or the main scenes from `status` `inventory.scenes`), at every resolution in `look.resolutions`:

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1 shot -Json -Quiet -Scene res://ui/Menu.tscn,res://ui/Hud.tscn -Resolution 1920x1080 -RequireResolution -Output screenshots/1920x1080
```

`-RequireResolution` makes a picture of another size fail with `shot-size`. A project whose stretch aspect is `keep` (Godot's default) renders its base
size with bars in any window, so `-Resolution 2560x1080` would otherwise hand back a 1920x1080 picture that looks like a wide layout and is not one
(six rounds once passed without judging 21:9 and 4:3 for that reason; `doctor` warns about it too). When a resolution fails with `shot-size`, that
layout is not shown: do not judge a picture as if it were that size. Report it as a finding (resolution | not shown | the stretch mode and aspect from
the error), run the other resolutions, and let the user choose between aspect `expand` (or `keep_width`, `keep_height`) in Project Settings > Display >
Window > Stretch and dropping the resolution from the `Resolutions:` line of `docs/STYLE.md`.

Ask it to judge each picture against `docs/STYLE.md` and its "Choices": text too small or clipped, contrast, overlap, things
outside the safe area, colours off the palette (`shots[].palette`: `offPalettePercent`, `colours[]` and the marked
`palette.image`; a `palette.problem` means the style guide has no palette table yet), screens that disagree with each other, and the rules in
`ui-accessibility` that a picture can show (colour alone, focus outline, target size, text painted into images).
Name the WCAG criterion with each accessibility problem. Ask it for type problems too, by the rules of `typography`: more
than two families or two fonts in one line, a paragraph in capitals, body lines far outside 45-90 characters, HUD numbers
that change width, straight quotes, `...` or `--` where `’`, `…` and `—` belong, and a text role that differs between
screens. Take the design resolution again with
`-ColorVision protan,deutan,tritan` and ask it to compare each `shots[].colorVision` picture with the original: team colours,
health bars, map markers, selected or locked states and must-not-confuse pairs that become the same colour there, and
markers that sink into the background (1.4.1). For each gameplay screen, also ask it to name the first, second and
third read (what the eye finds first, next, last; Zach Gage, GDC): flag state the player needs all the time (status
effects, the current goal) drawn smaller than decoration, and screens where the second and third reads are the same size.
Report the problems as a table:
screen | resolution | problem | rule it breaks | screenshot path. Do not fix anything the user has not chosen to fix.

## 3. Before and after

For a visual change, take the "before" pictures first, at the design resolution:

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1 shot -Json -Quiet -Scene res://ui/Hud.tscn -Resolution 1920x1080 -Output screenshots/before
```

Make the change, then compare:

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1 shot -Json -Quiet -Scene res://ui/Hud.tscn -Resolution 1920x1080 -Output screenshots/after -Baseline screenshots/before
```

Each shot gets `compare.changedPercent` and `compare.image`: before | after | changes in red. Look at the comparison image,
then ask one multiple-choice question: **Keep before**, **Take after**, or one or two **named tweaks** you can see would help.
Put the comparison image's path and a one-line description of what changed in the question, so the user can open it. A change
of 0% means the edit did not reach that screen; say so instead of asking.

Revert or keep the change as chosen, and add the decision under "Choices" in `docs/STYLE.md`
(`yyyy-mm-dd, screen: what was chosen and why`), so later critiques respect it.

## 4. Feel

How the game feels in motion is `game-juice`: offer it when the critique is about responsiveness rather than layout.
