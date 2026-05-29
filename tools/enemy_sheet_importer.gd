extends SceneTree

const SOURCE_DIR := "res://assets/enemy/set"
const GENERATED_IMAGE_ROOT := "res://assets/enemy/generated"
const MANIFEST_PATH := "res://assets/enemy/generated/enemy_manifest.json"
const REPORT_PATH := "res://assets/enemy/generated/import_report.md"
const GENERATED_ENEMY_ROOT := "res://enemies/generated"

const ACTION_ATTACK := 0
const ELEMENT_RED := 0
const ELEMENT_LIGHT := 6
const ELEMENT_DARK := 7

const SHEETS: Array[Dictionary] = [
	{
		"name": "dark_set",
		"file": "dark_set.png",
		"columns": 6,
		"rows": 4,
		"element": ELEMENT_DARK,
		"portrait_color": [0.30, 0.20, 0.45, 1.0],
		"enemy_level": 4,
		"max_hp": 1600,
		"attack_damage": 22,
		"loot_min": 20,
		"loot_max": 34,
	},
	{
		"name": "dessert_set",
		"file": "dessert_set.png",
		"columns": 6,
		"rows": 3,
		"element": ELEMENT_LIGHT,
		"portrait_color": [0.90, 0.76, 0.30, 1.0],
		"enemy_level": 3,
		"max_hp": 1300,
		"attack_damage": 18,
		"loot_min": 16,
		"loot_max": 28,
	},
	{
		"name": "dungeon_set",
		"file": "dungeon_set.png",
		"columns": 7,
		"rows": 4,
		"element": ELEMENT_DARK,
		"portrait_color": [0.34, 0.28, 0.42, 1.0],
		"enemy_level": 4,
		"max_hp": 1700,
		"attack_damage": 22,
		"loot_min": 20,
		"loot_max": 34,
	},
	{
		"name": "dungen_set2",
		"file": "dungen_set2.png",
		"columns": 7,
		"rows": 4,
		"element": ELEMENT_DARK,
		"portrait_color": [0.28, 0.25, 0.40, 1.0],
		"enemy_level": 4,
		"max_hp": 1700,
		"attack_damage": 22,
		"loot_min": 20,
		"loot_max": 34,
	},
	{
		"name": "lava_set",
		"file": "lava_set.png",
		"columns": 5,
		"rows": 3,
		"element": ELEMENT_RED,
		"portrait_color": [0.85, 0.28, 0.18, 1.0],
		"enemy_level": 5,
		"max_hp": 1900,
		"attack_damage": 26,
		"loot_min": 24,
		"loot_max": 40,
	},
	{
		"name": "light_set",
		"file": "light_set.png",
		"columns": 6,
		"rows": 3,
		"element": ELEMENT_LIGHT,
		"portrait_color": [0.95, 0.86, 0.35, 1.0],
		"enemy_level": 3,
		"max_hp": 1400,
		"attack_damage": 18,
		"loot_min": 16,
		"loot_max": 28,
	},
]


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var exit_code: int = OK
	if args.has("--generate-enemies"):
		exit_code = _generate_enemy_resources()
	else:
		exit_code = _crop_sheets_and_write_manifest()
	quit(exit_code)


func _crop_sheets_and_write_manifest() -> int:
	var dir_err: int = _ensure_res_dir(GENERATED_IMAGE_ROOT)
	if dir_err != OK:
		push_error("Cannot create generated image root: %s" % GENERATED_IMAGE_ROOT)
		return dir_err

	var entries: Array[Dictionary] = []
	var empty_cells: Array[String] = []
	for sheet: Dictionary in SHEETS:
		var sheet_name: String = sheet["name"]
		var source_path: String = "%s/%s" % [SOURCE_DIR, sheet["file"]]
		var image := Image.new()
		var load_err: int = image.load(source_path)
		if load_err != OK:
			push_error("Cannot load sheet: %s" % source_path)
			return load_err

		var output_dir: String = "%s/%s" % [GENERATED_IMAGE_ROOT, sheet_name]
		var output_err: int = _ensure_res_dir(output_dir)
		if output_err != OK:
			return output_err

		var has_alpha_background: bool = _has_transparent_background(image)
		var columns: int = int(sheet["columns"])
		var rows: int = int(sheet["rows"])
		for row_index in rows:
			for column_index in columns:
				var provisional_id: String = "%s_r%02d_c%02d" % [sheet_name, row_index + 1, column_index + 1]
				var cell_rect: Rect2i = _get_cell_rect(image.get_width(), image.get_height(), columns, rows, column_index, row_index)
				var bounds: Rect2i = _find_content_bounds(image, cell_rect, has_alpha_background)
				if bounds.size.x <= 0 or bounds.size.y <= 0:
					empty_cells.append(provisional_id)
					bounds = cell_rect
				var crop_path: String = "%s/%s.png" % [output_dir, provisional_id]
				var crop_err: int = _save_crop(image, bounds, crop_path)
				if crop_err != OK:
					return crop_err
				entries.append(_make_manifest_entry(sheet, row_index, column_index, provisional_id, crop_path, bounds, cell_rect))

	var manifest := {
		"version": 1,
		"manual_names_required": true,
		"generated_enemy_root": GENERATED_ENEMY_ROOT,
		"entries": entries,
	}
	var manifest_err: int = _write_text_file(MANIFEST_PATH, JSON.stringify(manifest, "\t"))
	if manifest_err != OK:
		return manifest_err

	var report_err: int = _write_text_file(REPORT_PATH, _build_report(entries, empty_cells))
	if report_err != OK:
		return report_err

	print("Cropped %d enemies. Manifest: %s" % [entries.size(), MANIFEST_PATH])
	if not empty_cells.is_empty():
		push_warning("Empty cells detected: %s" % [", ".join(empty_cells)])
	return OK


func _make_manifest_entry(sheet: Dictionary, row_index: int, column_index: int, provisional_id: String, crop_path: String, bounds: Rect2i, cell_rect: Rect2i) -> Dictionary:
	var display_name: String = _make_default_enemy_name(String(sheet["name"]), row_index, column_index, int(sheet["columns"]))
	return {
		"enabled": true,
		"source_sheet": sheet["name"],
		"row": row_index + 1,
		"col": column_index + 1,
		"provisional_id": provisional_id,
		"image_path": crop_path,
		"display_name": display_name,
		"slug": _slugify(display_name),
		"element": int(sheet["element"]),
		"portrait_color": sheet["portrait_color"],
		"enemy_level": int(sheet["enemy_level"]),
		"max_hp": int(sheet["max_hp"]),
		"attack_damage": int(sheet["attack_damage"]),
		"attack_coeff": 1.0,
		"attack_interval": 2,
		"action_pattern": [ACTION_ATTACK],
		"loot_min": int(sheet["loot_min"]),
		"loot_max": int(sheet["loot_max"]),
		"crop_rect": {"x": bounds.position.x, "y": bounds.position.y, "w": bounds.size.x, "h": bounds.size.y},
		"cell_rect": {"x": cell_rect.position.x, "y": cell_rect.position.y, "w": cell_rect.size.x, "h": cell_rect.size.y},
	}


func _make_default_enemy_name(sheet_name: String, row_index: int, column_index: int, columns: int) -> String:
	var prefix: String = "Monster"
	match sheet_name:
		"dark_set":
			prefix = "Dark Fiend"
		"dessert_set":
			prefix = "Desert Beast"
		"dungeon_set":
			prefix = "Dungeon Monster"
		"dungen_set2":
			prefix = "Deep Dungeon Monster"
		"lava_set":
			prefix = "Lava Beast"
		"light_set":
			prefix = "Light Spirit"
	var serial: int = row_index * columns + column_index + 1
	return "%s %02d" % [prefix, serial]


func _slugify(value: String) -> String:
	var lowered: String = value.to_lower()
	var result := ""
	var previous_dash := false
	for index in lowered.length():
		var character: String = lowered[index]
		var code: int = character.unicode_at(0)
		var is_alnum: bool = (code >= 48 and code <= 57) or (code >= 97 and code <= 122)
		if is_alnum:
			result += character
			previous_dash = false
		elif not previous_dash:
			result += "-"
			previous_dash = true
	return result.strip_edges().strip_edges(false, true).trim_suffix("-")


func _generate_enemy_resources() -> int:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		push_error("Cannot read manifest: %s" % MANIFEST_PATH)
		return ERR_FILE_NOT_FOUND
	var manifest_text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(manifest_text)
	if not (parsed is Dictionary):
		push_error("Manifest is not a JSON object.")
		return ERR_PARSE_ERROR

	var manifest: Dictionary = parsed
	var entries: Array = manifest.get("entries", [])
	var validation_error: String = _validate_manifest_for_generation(entries)
	if not validation_error.is_empty():
		push_error(validation_error)
		return ERR_INVALID_DATA

	var dir_err: int = _ensure_res_dir(GENERATED_ENEMY_ROOT)
	if dir_err != OK:
		return dir_err

	var generated_count: int = 0
	for entry_variant in entries:
		var entry: Dictionary = entry_variant
		if not bool(entry.get("enabled", true)):
			continue
		var slug: String = String(entry.get("slug", "")).strip_edges()
		var enemy_path: String = "%s/%s.tres" % [GENERATED_ENEMY_ROOT, slug]
		var tres_text: String = _build_enemy_tres(entry)
		var write_err: int = _write_text_file(enemy_path, tres_text)
		if write_err != OK:
			return write_err
		generated_count += 1

	print("Generated %d enemy resources in %s" % [generated_count, GENERATED_ENEMY_ROOT])
	return OK


func _validate_manifest_for_generation(entries: Array) -> String:
	var slugs: Dictionary = {}
	var names: Dictionary = {}
	for entry_variant in entries:
		var entry: Dictionary = entry_variant
		if not bool(entry.get("enabled", true)):
			continue
		var provisional_id: String = String(entry.get("provisional_id", ""))
		var display_name: String = String(entry.get("display_name", "")).strip_edges()
		var slug: String = String(entry.get("slug", "")).strip_edges()
		if display_name.is_empty() or slug.is_empty():
			return "Missing display_name or slug for %s. Fill the manifest before generating enemies." % provisional_id
		if slugs.has(slug):
			return "Duplicate slug in manifest: %s" % slug
		if names.has(display_name):
			return "Duplicate display_name in manifest: %s" % display_name
		slugs[slug] = true
		names[display_name] = true
	return ""


func _build_enemy_tres(entry: Dictionary) -> String:
	var display_name: String = _escape_resource_string(String(entry["display_name"]))
	var image_path: String = String(entry["image_path"])
	var color_values: Array = entry.get("portrait_color", [1.0, 1.0, 1.0, 1.0])
	var action_pattern: Array = entry.get("action_pattern", [ACTION_ATTACK])
	return "" + \
"[gd_resource type=\"Resource\" script_class=\"EnemyData\" load_steps=5 format=3]\n\n" + \
"[ext_resource type=\"Script\" path=\"res://scripts/enemy_data.gd\" id=\"1_script\"]\n" + \
"[ext_resource type=\"Texture2D\" path=\"%s\" id=\"2_texture\"]\n" % image_path + \
"[ext_resource type=\"Script\" path=\"res://scripts/loot_item.gd\" id=\"3_loot_script\"]\n\n" + \
"[sub_resource type=\"Resource\" id=\"gold_drop\"]\n" + \
"script = ExtResource(\"3_loot_script\")\n" + \
"item_type = 0\n" + \
"amount_min = %d\n" % int(entry.get("loot_min", 10)) + \
"amount_max = %d\n" % int(entry.get("loot_max", 20)) + \
"drop_chance = 1.0\n\n" + \
"[resource]\n" + \
"script = ExtResource(\"1_script\")\n" + \
"enemy_name = \"%s\"\n" % display_name + \
"enemy_level = %d\n" % int(entry.get("enemy_level", 1)) + \
"max_hp = %d\n" % int(entry.get("max_hp", 50)) + \
"attack_damage = %d\n" % int(entry.get("attack_damage", 6)) + \
"attack_coeff = %.3f\n" % float(entry.get("attack_coeff", 1.0)) + \
"attack_interval = %d\n" % int(entry.get("attack_interval", 2)) + \
"action_pattern = Array[int](%s)\n" % _format_int_array(action_pattern) + \
"portrait_color = Color(%.3f, %.3f, %.3f, %.3f)\n" % [float(color_values[0]), float(color_values[1]), float(color_values[2]), float(color_values[3])] + \
"portrait_texture = ExtResource(\"2_texture\")\n" + \
"element = %d\n" % int(entry.get("element", ELEMENT_DARK)) + \
"loot_table = Array[LootItem]([SubResource(\"gold_drop\")])\n"


func _get_cell_rect(image_width: int, image_height: int, columns: int, rows: int, column_index: int, row_index: int) -> Rect2i:
	var left: int = int(floor(float(column_index) * float(image_width) / float(columns)))
	var right: int = int(floor(float(column_index + 1) * float(image_width) / float(columns)))
	var top: int = int(floor(float(row_index) * float(image_height) / float(rows)))
	var bottom: int = int(floor(float(row_index + 1) * float(image_height) / float(rows)))
	return Rect2i(left, top, right - left, bottom - top)


func _find_content_bounds(image: Image, cell_rect: Rect2i, has_alpha_background: bool) -> Rect2i:
	var min_x: int = cell_rect.position.x + cell_rect.size.x
	var min_y: int = cell_rect.position.y + cell_rect.size.y
	var max_x: int = cell_rect.position.x - 1
	var max_y: int = cell_rect.position.y - 1
	for y in range(cell_rect.position.y, cell_rect.position.y + cell_rect.size.y):
		for x in range(cell_rect.position.x, cell_rect.position.x + cell_rect.size.x):
			var pixel: Color = image.get_pixel(x, y)
			if not _is_content_pixel(pixel, has_alpha_background):
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Rect2i(cell_rect.position, Vector2i.ZERO)
	var padding := 4
	min_x = maxi(cell_rect.position.x, min_x - padding)
	min_y = maxi(cell_rect.position.y, min_y - padding)
	max_x = mini(cell_rect.position.x + cell_rect.size.x - 1, max_x + padding)
	max_y = mini(cell_rect.position.y + cell_rect.size.y - 1, max_y + padding)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _has_transparent_background(image: Image) -> bool:
	var width: int = image.get_width()
	var height: int = image.get_height()
	var step_x: int = maxi(1, width / 32)
	var step_y: int = maxi(1, height / 32)
	for y in range(0, height, step_y):
		for x in range(0, width, step_x):
			if image.get_pixel(x, y).a < 0.95:
				return true
	return false


func _is_content_pixel(pixel: Color, has_alpha_background: bool) -> bool:
	if has_alpha_background:
		return pixel.a > 0.04
	if pixel.a <= 0.04:
		return false
	return not (pixel.r > 0.96 and pixel.g > 0.96 and pixel.b > 0.96)


func _save_crop(source_image: Image, bounds: Rect2i, output_path: String) -> int:
	var crop := Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	crop.blit_rect(source_image, bounds, Vector2i.ZERO)
	return crop.save_png(output_path)


func _ensure_res_dir(res_path: String) -> int:
	var absolute_path: String = ProjectSettings.globalize_path(res_path)
	return DirAccess.make_dir_recursive_absolute(absolute_path)


func _write_text_file(res_path: String, text: String) -> int:
	var file := FileAccess.open(res_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	return OK


func _build_report(entries: Array[Dictionary], empty_cells: Array[String]) -> String:
	var lines: Array[String] = [
		"# Enemy Sheet Import Report",
		"",
		"Generated entries: %d" % entries.size(),
		"Empty cells: %d" % empty_cells.size(),
		"",
		"Fill `display_name` and `slug` in `enemy_manifest.json`, then run this tool with `--generate-enemies`.",
		"",
	]
	var current_sheet := ""
	for entry: Dictionary in entries:
		var sheet_name: String = entry["source_sheet"]
		if sheet_name != current_sheet:
			current_sheet = sheet_name
			lines.append("## %s" % sheet_name)
			lines.append("")
		lines.append("- `%s` row %d col %d: %s" % [entry["provisional_id"], int(entry["row"]), int(entry["col"]), entry["image_path"]])
	if not empty_cells.is_empty():
		lines.append("")
		lines.append("## Empty Cells")
		for id_text: String in empty_cells:
			lines.append("- `%s`" % id_text)
	return "\n".join(lines) + "\n"


func _format_int_array(values: Array) -> String:
	var parts: Array[String] = []
	for value in values:
		parts.append(str(int(value)))
	return "[%s]" % ", ".join(parts)


func _escape_resource_string(value: String) -> String:
	return value.replace("\\", "\\\\").replace("\"", "\\\"")