# What the typography skill claims about Godot, held in the engine (tests/Test-Typography.ps1 runs it with GUT):
#   - every Class.member the skill's godot.md quotes exists in ClassDB (api.txt, written from the skill by the script)
#   - the numbers it states, measured with the bundled fallback font at 32 px: line pitch is the font height plus
#     line_spacing, spacing_glyph adds pixels, the default digits are tabular and proportional_figures changes them,
#     Label.uppercase widens text without changing it, feature names map to the OpenType tags
#   - punctuation.md: the marks exist in the bundled font, a no-break space keeps a pair on one line, a line may break after a
#     hyphen or an em dash, and a GDScript escape is the character
# How antialiasing, hinting or MSDF look on a given font is not here: the skill says to look at a shot frame.
extends GutTest

const SIZE := 32


func _kind(cls: String, member: String) -> String:
	var c := cls
	while c != "":
		for p in ClassDB.class_get_property_list(c, true):
			if p.name == member:
				return "property"
		if ClassDB.class_has_method(c, member, true):
			return "method"
		if ClassDB.class_has_signal(c, member):
			return "signal"
		if ClassDB.class_has_integer_constant(c, member):
			return "constant"
		c = ClassDB.get_parent_class(c)
	return ""


func _width(font: Font, text: String) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x


func test_every_name_the_skill_quotes_exists() -> void:
	var file := FileAccess.open("res://test/api.txt", FileAccess.READ)
	assert_not_null(file, "api.txt was not written by the script")
	if file == null:
		return
	var checked := 0
	var missing: Array[String] = []
	for line in file.get_as_text().split("\n", false):
		var token := line.strip_edges()
		var parts := token.trim_suffix("()").split(".")
		if not ClassDB.class_exists(parts[0]):
			missing.append(token + " (no such class)")
		elif parts.size() > 1 and _kind(parts[0], parts[1]) == "":
			missing.append(token)
		checked += 1
	gut.p("%d names checked" % checked)
	for name in missing:
		gut.p("missing from the engine: " + name)
	assert_gt(checked, 20, "the skill quotes fewer names than expected")
	assert_eq(missing, [] as Array[String], "names the engine does not have")


func test_line_pitch_is_font_height_plus_line_spacing() -> void:
	var font: Font = ThemeDB.fallback_font
	var height := font.get_height(SIZE)
	assert_eq(height, 45.0, "the bundled font is 45 px high at 32 px")
	for spacing in [0.0, 3.0, -8.0]:
		var label := Label.new()
		var settings := LabelSettings.new()
		settings.font = font
		settings.font_size = SIZE
		settings.line_spacing = spacing
		label.label_settings = settings
		label.text = "a\nb"
		add_child_autofree(label)
		assert_eq(label.get_minimum_size().y, 2.0 * height + spacing, "two lines at line_spacing %s" % spacing)


func test_spacing_glyph_adds_pixels() -> void:
	var base: Font = ThemeDB.fallback_font
	var tracked := FontVariation.new()
	tracked.base_font = base
	tracked.spacing_glyph = 4
	assert_eq(_width(base, "ABCD"), 86.0, "ABCD in the bundled font")
	assert_eq(_width(tracked, "ABCD"), 98.0, "three gaps of 4 px")


func test_digits_are_tabular_by_default_and_proportional_on_request() -> void:
	var base: Font = ThemeDB.fallback_font
	assert_eq(_width(base, "1"), _width(base, "8"), "default digits have one width")
	var tab := FontVariation.new()
	tab.base_font = base
	tab.opentype_features = {"tabular_figures": 1}
	assert_eq(_width(tab, "1"), _width(tab, "8"), "tabular figures have one width")
	var prop := FontVariation.new()
	prop.base_font = base
	prop.opentype_features = {"proportional_figures": 1}
	assert_ne(_width(prop, "1"), _width(prop, "8"), "proportional figures differ")


func test_uppercase_changes_the_view_not_the_text() -> void:
	var lower := Label.new()
	lower.text = "ab"
	add_child_autofree(lower)
	var upper := Label.new()
	upper.text = "ab"
	upper.uppercase = true
	add_child_autofree(upper)
	assert_eq(upper.text, "ab", "the stored text is untouched")
	assert_gt(upper.get_minimum_size().x, lower.get_minimum_size().x, "capitals are wider")


func test_feature_names_map_to_the_opentype_tags() -> void:
	var ts := TextServerManager.get_primary_interface()
	var tags := {"tabular_figures": "tnum", "standard_ligatures": "liga", "kerning": "kern", "lining_figures": "lnum",
		"oldstyle_figures": "onum", "small_capitals": "smcp"}
	for name in tags:
		assert_eq(ts.name_to_tag(name), ts.name_to_tag(tags[name]), "%s is %s" % [name, tags[name]])


func test_the_marks_exist_in_the_bundled_font() -> void:
	var font: Font = ThemeDB.fallback_font
	for code in [0x2018, 0x2019, 0x201C, 0x201D, 0x2013, 0x2014, 0x2026, 0x00A0, 0x2212, 0x00D7]:
		assert_true(font.has_char(code), "U+%04X is in the bundled font" % code)
	assert_eq("\u2019", char(0x2019), "a GDScript escape is the character")


func _lines(text: String, width: float) -> Array:
	var ts := TextServerManager.get_primary_interface()
	var rid := ts.create_shaped_text()
	ts.shaped_text_add_string(rid, text, ThemeDB.fallback_font.get_rids(), SIZE)
	var breaks := ts.shaped_text_get_line_breaks(rid, width, 0, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND)
	var lines := []
	for i in range(0, breaks.size(), 2):
		lines.append(text.substr(breaks[i], breaks[i + 1] - breaks[i]))
	ts.free_rid(rid)
	return lines


func test_a_no_break_space_keeps_a_pair_together_and_dashes_allow_a_break() -> void:
	var font: Font = ThemeDB.fallback_font
	var width := _width(font, "xx aaaa bbbb") - 5.0
	assert_eq(_lines("xx aaaa bbbb", width), ["xx aaaa ", "bbbb"], "an ordinary space breaks before bbbb")
	assert_eq(_lines("xx aaaa\u00A0bbbb", width), ["xx ", "aaaa\u00A0bbbb"], "a no-break space keeps aaaa and bbbb together")
	assert_eq(_lines("xx aaaa-bbbb", width), ["xx aaaa-", "bbbb"], "a line may break after a hyphen")
	assert_eq(_lines("xx aaaa\u2014bbbb", width), ["xx aaaa\u2014", "bbbb"], "a line may break after an em dash")
