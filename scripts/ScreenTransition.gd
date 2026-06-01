# ScreenTransition.gd
# Autoloaded singleton for fade-to-black screen transitions
extends CanvasLayer

signal fade_in_done
signal fade_out_done

@onready var color_rect: ColorRect = $ColorRect

func _ready() -> void:
	# Ensure full screen coverage
	color_rect.color = Color(0, 0, 0, 0)
	color_rect.visible = false
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

func fade_in(duration: float = 0.3) -> void:
	# Fade from black to transparent
	color_rect.visible = true
	color_rect.mouse_filter = Control.MOUSE_FILTER_STOP  # Block input during fade
	color_rect.color = Color(0, 0, 0, 1)
	
	var tween = create_tween()
	tween.tween_property(color_rect, "color", Color(0, 0, 0, 0), duration)
	tween.tween_callback(_on_fade_in_complete)
	await fade_in_done

func fade_out(duration: float = 0.3) -> void:
	# Fade from transparent to black
	color_rect.visible = true
	color_rect.mouse_filter = Control.MOUSE_FILTER_STOP  # Block input during fade
	color_rect.color = Color(0, 0, 0, 0)
	
	var tween = create_tween()
	tween.tween_property(color_rect, "color", Color(0, 0, 0, 1), duration)
	tween.tween_callback(_on_fade_out_complete)
	await fade_out_done

func _on_fade_in_complete() -> void:
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	color_rect.visible = false
	fade_in_done.emit()

func _on_fade_out_complete() -> void:
	fade_out_done.emit()
