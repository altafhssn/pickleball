# PaddleCard.gd
# Individual paddle card within the shop grid
extends MarginContainer

signal paddle_selected

# Visual references
@onready var name_label: Label = $VBox/NameLabel
@onready var rarity_label: Label = $VBox/RarityLabel
@onready var owned_label: Label = $VBox/OwnedLabel

var paddle_id: int = -1
var stats: Dictionary = {}

func setup(id: int, paddle_stats: Dictionary, owned: bool, equipped: bool) -> void:
	paddle_id = id
	stats = paddle_stats
	
	name_label.text = paddle_stats.get("name", "Unknown")
	
	var rarity_name: String = paddle_stats.get("rarity", "common")
	rarity_label.text = rarity_name.capitalize()
	rarity_label.modulate = Color(PaddleData.get_rarity_color(paddle_stats.get("rarity_index", 0)))
	
	if equipped:
		owned_label.text = "✅ Equipped"
		owned_label.show()
	elif owned:
		owned_label.text = "✓ Owned"
		owned_label.show()
	else:
		owned_label.hide()
	
	# Make clickable
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		paddle_selected.emit()

func get_paddle_id() -> int:
	return paddle_id
