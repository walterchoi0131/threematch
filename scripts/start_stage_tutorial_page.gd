class_name StartStageTutorialPage
extends Resource

@export var page_id: String = ""
@export_file("*.png", "*.jpg", "*.jpeg", "*.webp") var image_path: String = ""
@export var chi_title: String = ""
@export var eng_title: String = ""
@export_multiline var ch_info: String = ""
@export_multiline var eng_info: String = ""


func is_blank() -> bool:
	return image_path.strip_edges().is_empty() \
		and chi_title.strip_edges().is_empty() \
		and eng_title.strip_edges().is_empty() \
		and ch_info.strip_edges().is_empty() \
		and eng_info.strip_edges().is_empty()


func copy_content_from(other: StartStageTutorialPage) -> void:
	if other == null:
		return
	image_path = other.image_path
	chi_title = other.chi_title
	eng_title = other.eng_title
	ch_info = other.ch_info
	eng_info = other.eng_info
