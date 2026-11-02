# Punctuation and spaces in text players read

From Butterick's *Practical Typography* (chapters on quotes, apostrophes, dashes, ellipses, spaces, symbols and
exclamation points), which writes for American English. Other languages have their own marks (guillemets, low
double quotes, spaced dashes): take those from the translator or the language's style guide, and let the rules below
set only the source text and the English table. Put the characters straight into UTF-8 strings and tables, or use
`"’"` in GDScript and C#; a table that is not UTF-8 fails the `l10n` gate.

| Mark | Character | Rule |
|---|---|---|
| Quotation marks | `‘` U+2018, `’` U+2019, `“` U+201C, `”` U+201D | Curly, never the straight `'` and `"`: "curly quotes are more legible on the page and match the other characters better." |
| Apostrophe | `’` U+2019 | "Apostrophes always point downward," so it is the closing single quote, also at the start of a word (`’70s`, `rock ’n’ roll`), where an automatic converter makes an opening quote by mistake |
| Foot and inch marks | straight `'` and `"` | The one exception to curly quotes (`5' 11"`) |
| Hyphen | `-` U+002D | Compound words and line breaks (`cost-effective`, `five-dollar bills`) |
| En dash | `–` U+2013 | A range or a connection: `1880–1912`, `pages 330–39`, `conservative–liberal`. Not a slash. With "from", use "to" |
| Em dash | `—` U+2014 | A break in a sentence, stronger than a comma and weaker than a colon. Never `--`: "it's another typewriter habit." If dashes look crushed on screen, word spaces around them are fine |
| Ellipsis | `…` U+2026 | One character, not `...` and not `. . .`. Spaces around it as a rule; with text on one side only, a non-breaking space on that side |
| Minus, times | `−` U+2212, `×` U+00D7 | `12 × 34 − 56`, not `12 x 34 - 56`; `1920 × 1080`, not `1920x1080`. An en dash is an acceptable minus if used rarely |
| Sentence spacing | one space (U+0020) | "Always put exactly one space between sentences," and in general after any punctuation. One word space at a time |
| Non-breaking space | U+00A0 | Between a reference and its number or a title and its name (`Fig. 23`, `Ex. A`, `Sgt. Rock`); the same idea for `Level 3`, `Chapter 2` and a value and its unit (`10 HP`) |
| Exclamation point | `!` | "Never use more than one exclamation point in a row." Overused; the book allows one for any document longer than three pages. The question mark is underused |
| Ampersand | `&` | Sparingly, and in proper names. The more formal the text, the less |
| Accents | `é ü ñ` | "In names, accented characters must always appear accurately," so the font must have them (`Font.has_char()`, the `l10n` glyph case) |
| Emoticons, emoji | | Casual only; overuse "is just as irritating as the overuse of question marks and exclamation points, or all caps" |

## In Godot 4.7.2 (measured with the bundled font, `tests/Test-Typography.ps1`)

- The bundled font has every character above, including U+2018, U+2019, U+201C, U+201D, U+2013, U+2014, U+2026, U+00A0,
  U+2212 and U+00D7. A font you ship may not: check with `Font.has_char()` before using the mark in the UI.
- A non-breaking space keeps a pair together: "xx aaaa bbbb" in a box too narrow for it broke as `xx aaaa` / `bbbb`, and
  "xx aaaa bbbb" broke as `xx` / `aaaa bbbb`.
- A line may break after a hyphen or an em dash (`xx aaaa-` / `bbbb`, `xx aaaa—` / `bbbb`), so a dash that must stay with the
  word before it needs a non-breaking space or a rewrite.
- Godot has no smart-quote conversion: curly marks are typed into the string or table. Text the player types (a name) is not
  converted.
- In a flow, `equals` is exact: assert with the same characters the label has (`ui-flows`).
