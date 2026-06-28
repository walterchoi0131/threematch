class_name TutorialPageLibrary
extends Resource

const _StartStageTutorialPage := preload("res://scripts/start_stage_tutorial_page.gd")

@export var pages: Array[_StartStageTutorialPage] = []


func ensure_page_ids() -> void:
	var used: Dictionary = {}
	for index in pages.size():
		var page: _StartStageTutorialPage = pages[index]
		if page == null:
			page = _StartStageTutorialPage.new()
			pages[index] = page
		var page_id: String = page.page_id.strip_edges()
		if page_id.is_empty() or used.has(page_id):
			page_id = make_unique_page_id(_page_id_base_for(page, index), used)
			page.page_id = page_id
		used[page_id] = true


func get_page(page_id: String) -> _StartStageTutorialPage:
	var needle: String = page_id.strip_edges()
	if needle.is_empty():
		return null
	for page: _StartStageTutorialPage in pages:
		if page != null and page.page_id == needle:
			return page
	return null


func has_page_id(page_id: String) -> bool:
	return get_page(page_id) != null


func add_page_with_id(base_id: String = "tutorial_page") -> _StartStageTutorialPage:
	ensure_page_ids()
	var used: Dictionary = {}
	for page: _StartStageTutorialPage in pages:
		if page != null and not page.page_id.strip_edges().is_empty():
			used[page.page_id] = true
	var page := _StartStageTutorialPage.new()
	page.page_id = make_unique_page_id(base_id, used)
	pages.append(page)
	return page


func remove_page_id(page_id: String) -> void:
	var needle: String = page_id.strip_edges()
	if needle.is_empty():
		return
	for index in range(pages.size() - 1, -1, -1):
		var page: _StartStageTutorialPage = pages[index]
		if page != null and page.page_id == needle:
			pages.remove_at(index)
			return


func make_unique_page_id(raw_base: String, used_ids: Dictionary = {}) -> String:
	var base: String = sanitize_page_id(raw_base)
	if base.is_empty():
		base = "tutorial_page"
	var candidate: String = base
	var suffix := 2
	while has_page_id(candidate) or used_ids.has(candidate):
		candidate = "%s_%d" % [base, suffix]
		suffix += 1
	return candidate


func display_name(page: _StartStageTutorialPage) -> String:
	if page == null:
		return "(Missing page)"
	var title: String = page.chi_title.strip_edges()
	if title.is_empty():
		title = page.eng_title.strip_edges()
	if title.is_empty():
		title = page.page_id.strip_edges()
	return title if not title.is_empty() else "(Untitled page)"


func _page_id_base_for(page: _StartStageTutorialPage, index: int) -> String:
	if page == null:
		return "tutorial_page_%d" % (index + 1)
	var title: String = page.eng_title.strip_edges()
	if title.is_empty():
		title = page.chi_title.strip_edges()
	if title.is_empty():
		title = "tutorial_page_%d" % (index + 1)
	return title


static func sanitize_page_id(raw_text: String) -> String:
	var result := ""
	var lower: String = raw_text.strip_edges().to_lower()
	for i in lower.length():
		var ch: String = lower.substr(i, 1)
		var code: int = ch.unicode_at(0)
		var is_digit: bool = code >= 48 and code <= 57
		var is_letter: bool = code >= 97 and code <= 122
		if is_digit or is_letter:
			result += ch
		elif ch == "_" or ch == "-":
			result += "_"
		elif not result.ends_with("_"):
			result += "_"
	result = result.strip_edges()
	while result.ends_with("_"):
		result = result.substr(0, result.length() - 1)
	while result.begins_with("_"):
		result = result.substr(1)
	return result
