# Typography for game text: sources and what was kept

The `typography` skill (`.agents/skills/typography/`) is built from a list of 15 free typography resources the owner pasted on
2026-11-02. This page records what was read, what could not be, which rules were taken, which were left out and why, and what
was measured in the engine. Read on 2026-11-02 over HTTP with the page text extracted; quotes were checked against that text.

## The 15 sources

| # | Source | Status | Use |
|---|---|---|---|
| 1 | [Google Fonts Knowledge](https://fonts.google.com/knowledge) | **Not read.** A script-rendered app; its app script is blocked in transit from this environment (`ERR_BLOCKED_BY_ORB`) | Open in [roadmap](roadmap.md) |
| 2 | [Letterform Archive toolkit](https://letterformarchive.org/news/a-toolkit-for-learning-type-history/) | **Not read.** 403 from Cloudflare's bot check | Open |
| 3 | [OERT](https://www.oert.org/en/) | Read the front page: a syllabus outline (type families, size, spacing, grids, legibility, hierarchy). No rules to quote | Confirms the topic list of the skill |
| 4 | [Luc Devroye's history index](https://luc.devroye.org/history-index.html) | Reachable (350 KB); a link index to designers and foundries, not read through | Where to look for a typeface's history |
| 5 | [Practical Typography](https://practicaltypography.com) | **Read** (36 chapters: key rules, point size, line spacing, line length, capitals, letter-spacing, kerning, figures, ligatures, monospace, bold/italic, mixing fonts, colour, screen reading, presentations and more) | The source of the numbers |
| 6 | thinkingwithtype.com | **Not read.** The connection closed after ten seconds | Open |
| 7 | [Typewolf](https://www.typewolf.com) | Reachable; a gallery of trending typefaces and pairings, little text | Taste, not rules |
| 8 | [Fonts In Use](https://fontsinuse.com) | Reachable; a gallery of real uses | Taste, not rules |
| 9 | [TypeDrawers](https://typedrawers.com) | Reachable; a forum for type designers | Not distilled; for type-design questions |
| 10 | historyoftype.com | **Not read.** The gateway answered 502 to the connection (a policy denial or the site being down) | Open; the list called it free, which could not be confirmed |
| 11 | [MIT OpenCourseWare](https://ocw.mit.edu) | Reachable; the home page of all courses, not a typography course | Search for a course if wanted |
| 12 | [CalArts](https://calarts.edu) | Reachable; the university's home page, not typography material | No use as given |
| 13 | [AIGA](https://www.aiga.org) | **Not read.** 403 from a bot check | Open |
| 14 | [Wikipedia: Typography](https://en.wikipedia.org/wiki/Typography) | Read: vocabulary and the line that sans serif is common for short text and serif for newspapers and books | Vocabulary section of the skill |
| 15 | [TypeThursday](https://typethursday.org) | **Not read.** 429 from a bot check | Open |

Six of the fifteen are listings, galleries or home pages rather than lessons, so the skill rests mainly on one book. That is
a limit of the list, not of the topic. The "Open" rows are in `docs/roadmap.md` under "To do".

## Rules taken from Practical Typography

| Rule | Quote (chapter) | Taken as |
|---|---|---|
| Line spacing | "Line spacing should be 120-145% of the point size." (summary of key rules; "line spacing" gives the 110% / 135% / 170% examples) | The same range for body text and dialogue |
| Line length | "The average line length should be 45-90 characters (including spaces)." and "Aim for an average line length of 45-90 characters"; the alphabet test: "between two and three alphabets" (line length) | Dialogue boxes set by characters per line |
| Smaller text, tighter | "As you reduce point size, also reduce line spacing and line length." (point size) | Said once in the table |
| Size is not absolute | "different fonts set at the same point size won't necessarily appear the same"; "you need to let your eyes be the judge" (point size) | Compare candidates in `shot` frames |
| Few fonts, one role each | "Most documents can tolerate a second font. Few can tolerate a third. Almost none can tolerate four or more." and "Font mixing is most successful when each font has a consistent role" (mixing fonts) | At most two families, a role each |
| Capitals | "All caps are fine for less than one line of text." and "Use 5-12% extra letterspacing with all caps and small caps." (summary; letterspacing: `0.05em` to `0.12em`) | Buttons and headings only, with tracking |
| Kerning | "Kerning should always be turned on." (summary) | Always on |
| Emphasis | "Use bold or italic as little as possible, and not together." (summary); "If you're using a sans serif font, skip italic and use bold" (bold or italic) | As written |
| Ligatures | "The only time ligatures are mandatory is when you have an actual overlap between the letters f and i." (ligatures) | Optional otherwise |
| Figures | "Lining figures are always preferred for all caps text"; tabular figures: "most proportional fonts include tabular figures by default" (alternate figures; monospaced fonts) | Equal-width digits for HUD counters |
| Monospace | "In standard body text, there are no good reasons to use monospaced fonts." (monospaced fonts) | Code and consoles only |
| Colour | "On a page of text, nothing draws the eye more powerfully than a contrast between light and dark colors"; "When everything is emphasized, nothing is emphasized." (color) | Colour for meaning, few of them |
| Light text in the dark | For slides in a dark room: "start your font at 50% gray and brighten it from there. When it's legible, stop." (presentations) | Applied cautiously to long text on full black |

## Left out, and why

- **Print and web sizes** ("10-12 points in printed documents, 15-25 pixels on the web"): a game is read at another distance on
  another device, and `ui-accessibility` already holds measured floors for it. The skill keeps the proportions, not the sizes.
- **Typewriter habits** (one space after a full stop, straight and curly quotes, dashes, ellipses, non-breaking spaces): they
  matter in translated dialogue and credits too, but belong to a localisation and copy-editing pass, not this skill. Worth a
  line in the localisation skill if the owner wants it.
- **Word, Pages and CSS recipes**, the book's own font recommendations and its font shop, and the advice against free and
  system fonts as a class: free OFL fonts are the normal choice for a game, and the skill asks for fit and licence instead.
- **Justified text, first-line indents, page margins, hyphenation**: book layout; a game column is left-aligned in a box.

## Measured in Godot 4.7.2

`tests/Test-Typography.ps1` runs these in the engine (bundled fallback font, 32 px unless stated):

| Claim | Measured |
|---|---|
| `LabelSettings.line_spacing` is extra pixels on top of the font height | `Font.get_height(32)` 45 px; two lines 90 px at `line_spacing` 0, 93 at 3, 82 at -8 |
| `FontVariation.spacing_glyph` is pixels | "ABCD" 86 px, 98 px with 4 (three gaps) |
| Digits of the bundled font are tabular by default | "1", "8" and "0" all 18 px; with `proportional_figures` 15 and 19 px; `tabular_figures` 18 px |
| `Label.uppercase` leaves the text and widens it | "ab" 22 px against 20 px |
| Feature names map to the OpenType tags | `tabular_figures` is `tnum`, `standard_ligatures` `liga`, `kerning` `kern` |

Not measured: how antialiasing, hinting, subpixel positioning, oversampling and MSDF look on a given font. The skill names the
properties (checked to exist) and says to look at a `shot` frame.
