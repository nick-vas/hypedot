# Typography in Godot 4.7: properties and measured numbers

Names below were checked against Godot 4.7.2 (`tests/Test-Typography.ps1`). Numbers were measured with the engine's bundled
fallback font (Open Sans SemiBold, `ThemeDB.fallback_font`) at 32 px; other fonts differ, so measure yours the same way. In C#
the names are PascalCase (`SpacingGlyph`, `OpentypeFeatures`, `LineSpacing`).

## Roles in the theme

One theme type variation per role (`Control.theme_type_variation`), with the font, size and colour set on the variation, not on
the node. `LabelSettings` (`Label.label_settings`) is the lighter choice for one-off labels: `LabelSettings.font`,
`LabelSettings.font_size`, `LabelSettings.line_spacing`, `LabelSettings.paragraph_spacing`, `LabelSettings.outline_size`.

## Line spacing is extra pixels, not a multiple

The line pitch is the font's own height plus `LabelSettings.line_spacing` in pixels. At 32 px the bundled font is 45 px high
(`Font.get_height(32)`, 141% of the size), so two lines measured 90 px with `line_spacing` 0, 93 px with 3 and 82 px with -8.
For a target of 120-145%:

```gdscript
var size := 32
var font: Font = ThemeDB.fallback_font
var target := 1.3 * size                       # 130% of the size
settings.line_spacing = target - font.get_height(size)   # negative when the font is already tall
```

Check `font.get_height(size) / size` for each candidate font first: a font taller than 145% needs a negative `line_spacing`.

## Letter-spacing, figures, ligatures, capitals

- **Tracking:** `FontVariation.spacing_glyph` adds pixels between glyphs, not an em fraction: 4 px made "ABCD" 98 px instead of
  86 (three gaps). Scale it with the size: 5-12% of the font size for capitals. `FontVariation.spacing_space` widens spaces.
- **OpenType features:** `FontVariation.opentype_features` takes feature names or four-letter tags: `tabular_figures`
  (`tnum`), `proportional_figures`, `lining_figures` (`lnum`), `oldstyle_figures` (`onum`), `standard_ligatures` (`liga`),
  `kerning` (`kern`), `small_capitals` (`smcp`). The bundled font's digits are already tabular (1, 8 and 0 all 18 px); with
  `proportional_figures` they were 15 and 19 px. Set the one you mean: `{"tabular_figures": 1}` on the HUD font.
- **Capitals:** `Label.uppercase` shows capitals without changing the string ("ab" was 22 px wide against 20 px), so the
  stored text stays in natural case for translation. Add the tracking above to the same role.

```gdscript
var hud := FontVariation.new()
hud.base_font = load("res://fonts/Body.ttf")
hud.opentype_features = {"tabular_figures": 1}
hud.spacing_glyph = 0                  # lowercase and digits: none
```

## Rendering choices on the font file

`FontFile.antialiasing`, `FontFile.hinting`, `FontFile.subpixel_positioning`, `FontFile.oversampling` and
`FontFile.generate_mipmaps` are the import and rendering switches; `FontFile.multichannel_signed_distance_field` with
`FontFile.msdf_pixel_range` and `FontFile.msdf_size` renders text that is scaled, rotated or in world space. `FontFile.fixed_size`
and `FontFile.fixed_size_scale_mode` fix a bitmap font to a size. For a pixel font turn antialiasing and subpixel positioning
off and keep the size at a whole multiple of its design size. The effect of each switch on your font at your resolutions is not
something to assume: look at it with `shot`.

## Fallbacks and glyphs

`FontFile.fallbacks` (and the same list on a `FontVariation`) chains fonts for scripts the main font lacks; `Font.has_char()`
asks one font about one character, and the `l10n` glyph case checks every translated character against the chain. The
bundled font draws CJK and similar scripts only through the player's system fonts (`FontFile.allow_system_fallback`), which is
a warning, not a guarantee (`localization`).
