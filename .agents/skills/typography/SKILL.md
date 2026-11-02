---
name: typography
description: Use when choosing, sizing or setting the text of a game (UI, HUD and dialogue fonts, a title or logo font, all-caps labels, numbers that change, a pixel font), or when text looks cramped, dull or tiring to read.
---

# Typography: fonts and spacing for game text

Sizes and contrast floors (18 px PC, 26 px console body height at 1080p, 4.5:1) belong to `ui-accessibility`; the `textsize`
runner enforces them. This skill is about the rest: which fonts, how many, how far apart, and what to do with numbers and
capitals. The rules come from Butterick's *Practical Typography*, written for pages and screens; they are marked where a game
differs. The Godot properties and measured numbers are in [godot.md](godot.md), the marks and spaces in
[punctuation.md](punctuation.md); the sources, with what could and could not be read, in `docs/typography.md`.
The rules also live where they are used: `look` (the style guide), `asset-pipeline` (choosing and shipping fonts),
`localization` (marks per language) and `ui-flows` (asserting text).

## Decide roles before fonts

A game has few text roles: title or logo, heading, body or dialogue, label or button, HUD numbers, caption or subtitle. Write
the list, give each role one font, size and weight in the theme (a theme type variation per role, `godot.md`), and let no
scene override it.

- **Few families.** "Most documents can tolerate a second font. Few can tolerate a third. Almost none can tolerate four or
  more." Take one family with several weights, plus at most one more for a title, a diegetic sign or numbers.
- **Each font has a role** and never mixes inside a line. Two fonts can differ only a little (two serifs, two sans) and
  work better than a loud pair. Fonts by one designer usually pair.
- **A display or "goofy" font is for the logo, title and a few words**, never for body, dialogue or menus.
- **Free is not the problem; licence and fit are.** Use a family drawn for text, check its licence allows embedding in a game
  (OFL fonts do), and list it in the credits (`credits` ships the OFL text).
- **Monospace is for code, a debug console and aligned columns**, not for dialogue.

## Setting body text and dialogue

| Rule | Number |
|---|---|
| Line spacing | 120-145% of the font size. As size goes down, spacing and line length go down too |
| Line length | 45-90 characters per line including spaces, or 2-3 alphabets (`abcdefghijklmnopqrstuvwxyz` twice to three times) |
| Emphasis | Bold or italic, not both; as little as possible. In a sans, skip italic and use bold |
| Capitals | Fine for under one line (a button, a heading); never a paragraph; add 5-12% letter-spacing (0.05-0.12 em) |
| Kerning | Always on. Lowercase needs no extra letter-spacing |
| Ligatures | Mandatory only where the letters f and i actually collide; otherwise a style choice |

- A dialogue box is a text column: set its width by the characters per line (45-90), not by the screen; one line across a
  whole TV is far past it.
- The same pixel size looks different in different fonts: the size is not absolute, so "let your eyes be the judge". Compare
  candidates with `shot` at the target resolution, not by the size field.
- Hierarchy needs small steps, not a doubled heading: try a smaller jump first, and let weight and capitals carry the rest.
- Colour: nothing draws the eye like light against dark, so a colour used for emphasis competes with it. Keep colour for
  meaning (damage, the selected item), keep it to a few, and keep the contrast floor. Butterick's advice for a projected
  slide in a dark room (start from grey, brighten until legible) applies to long text on a full-screen black: avoid pure
  white on pure black for paragraphs, and look at a frame.

## Punctuation and spaces

Real marks in the source text: curly quotes and apostrophes (`’`), en dash for ranges, em dash for a break, one ellipsis
character `…`, `×` and `−` for sums and sizes, one space after punctuation, a non-breaking space inside `Level 3` and
`10 HP`, and at most one exclamation point at a time. The table, the exceptions and the Godot behaviour are in
[punctuation.md](punctuation.md); other languages follow their own conventions (`localization`).

## Numbers and HUD

- **Counters that change need figures of equal width** (tabular), or the number shifts as digits change. Most proportional
  fonts have tabular figures by default; check, and set the feature explicitly (`godot.md`).
- **Lining figures with capitals**; oldstyle figures only in running lowercase text. A score in caps-and-digits style is
  lining.

## Pixel and bitmap fonts

Use them at whole multiples of the size they were drawn for, usually with antialiasing and subpixel positioning off, and
view the result at every resolution you ship: a pixel font at a fractional scale can come out smeared. Some
pixel fonts draw small for their nominal size, so give each style a scale factor in the theme (`ui-accessibility` layout
notes). Pixel fonts rarely cover other scripts: plan the fallback (`localization`).

## Check it

- `shot -Json -Quiet -Scene res://ui/Hud.tscn -Resolution 1920x1080` at the sizes you ship, plus `-Locale` and `-Pseudo` for
  the longest languages; read the frames.
- `textsize` and `layout` for the floors and for clipping; the `l10n` glyph case for characters a font lacks.
- In a code review, count the fonts and sizes the theme defines, not the ones a scene overrides.

## Vocabulary

Baseline, x-height (height of lowercase without ascenders), ascender, descender, cap height; serif, sans serif, slab,
monospaced, script, display; weight, width, italic (a redrawn face) against oblique (a slanted one); tracking or
letter-spacing (every pair) against kerning (chosen pairs). Name these when briefing an artist or an agent.
