# GameFeel.gd
# Manages camera shake, screen flash, hit VFX
extends Node

@onready var camera: Camera3D = null
@onready var hud: CanvasLayer = null

var shake_intensity: float = 0.0
var shake_duration: float = 0.0
var shake_timer: float = 0.0
var flash_duration: float = 0.0
var flash_timer: float = 0.0
var flash_node: ColorRect = null
# Captured at shake-start so per-frame camera follow keeps working between shakes.
var shake_base_pos: Vector3 = Vector3.ZERO

func _ready():
	EventBus.ball_hit.connect(_on_hit)
	EventBus.ball_bounced.connect(_on_bounce)
	EventBus.point_scored.connect(_on_point_scored)
	EventBus.ball_net_hit.connect(_on_net_hit)

func setup(cam: Camera3D, hud_layer: CanvasLayer) -> void:
	camera = cam
	hud = hud_layer

	# Create flash overlay
	flash_node = ColorRect.new()
	flash_node.name = "ScreenFlash"
	flash_node.color = Color(1, 1, 1, 0)
	flash_node.size = Vector2(1080, 1920)
	flash_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_node.position = Vector2.ZERO
	hud.add_child(flash_node)

func _process(delta: float) -> void:
	# Camera shake — base position is captured at shake() so per-frame camera
	# follow (Main._update_camera) keeps composing correctly between shakes.
	if shake_timer > 0 and camera:
		shake_timer -= delta
		var decay = shake_timer / shake_duration
		var intensity = shake_intensity * decay
		camera.position = shake_base_pos + Vector3(
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity),
			randf_range(-intensity * 0.5, intensity * 0.5)
		)
		if shake_timer <= 0:
			camera.position = shake_base_pos
	
	# Screen flash
	if flash_timer > 0 and flash_node:
		flash_timer -= delta
		var alpha = flash_timer / flash_duration
		flash_node.color = Color(flash_node.color.r, flash_node.color.g, flash_node.color.b, alpha * 0.3)
		if flash_timer <= 0:
			flash_node.color = Color(1, 1, 1, 0)

func shake(intensity: float, duration: float) -> void:
	if not camera:
		return
	shake_intensity = intensity
	shake_duration = duration
	shake_timer = duration
	shake_base_pos = camera.position

func flash(color: Color, duration: float) -> void:
	if not flash_node:
		return
	flash_node.color = Color(color.r, color.g, color.b, 0.3)
	flash_duration = duration
	flash_timer = duration

func _on_hit(_shooter_id: int, _shot_type: int, force: float) -> void:
	shake(0.02 + force * 0.03, 0.15 + force * 0.1)

func _on_bounce(_pos: Vector3, _side: int) -> void:
	shake(0.01, 0.08)

func _on_point_scored(_player_id: int, _score: int) -> void:
	flash(Color(1, 1, 0.5), 0.3)
	shake(0.05, 0.2)

func _on_net_hit() -> void:
	shake(0.03, 0.12)
