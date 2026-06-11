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
# Additive offset that Main applies on top of its own camera base position.
# Refreshed every frame while shake is active; zero otherwise.
var current_shake_offset: Vector3 = Vector3.ZERO

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
	# Compute additive shake offset; Main owns the camera base position
	# and combines it with this offset each frame.
	if shake_timer > 0:
		shake_timer -= delta
		var decay: float = shake_timer / shake_duration
		var intensity: float = shake_intensity * decay
		current_shake_offset = Vector3(
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity),
			randf_range(-intensity * 0.5, intensity * 0.5)
		)
	else:
		current_shake_offset = Vector3.ZERO
	
	# Screen flash
	if flash_timer > 0 and flash_node:
		flash_timer -= delta
		var alpha = flash_timer / flash_duration
		flash_node.color = Color(flash_node.color.r, flash_node.color.g, flash_node.color.b, alpha * 0.3)
		if flash_timer <= 0:
			flash_node.color = Color(1, 1, 1, 0)

# Hit-stop: freeze time for a beat on a strong contact. The classic
# "you really hit that" feedback. duration is in real seconds.
func hitstop(duration: float = 0.05, time_scale: float = 0.05) -> void:
	if Engine.time_scale < 1.0:
		return  # one at a time
	Engine.time_scale = time_scale
	# ignore_time_scale=true so the timer runs in real time while frozen.
	var timer := get_tree().create_timer(duration, true, false, true)
	timer.timeout.connect(func(): Engine.time_scale = 1.0)

func shake(intensity: float, duration: float) -> void:
	if not camera:
		return
	# If a shake is already running, take the stronger one rather than
	# stacking (prevents runaway intensity from rapid hit sequences).
	if intensity > shake_intensity or shake_timer <= 0.0:
		shake_intensity = intensity
		shake_duration = duration
		shake_timer = duration

func flash(color: Color, duration: float) -> void:
	if not flash_node:
		return
	flash_node.color = Color(color.r, color.g, color.b, 0.3)
	flash_duration = duration
	flash_timer = duration

func _on_hit(_shooter_id: int, _shot_type: int, force: float) -> void:
	shake(0.01 + force * 0.015, 0.10 + force * 0.06)

func _on_bounce(_pos: Vector3, _side: int) -> void:
	shake(0.005, 0.06)

func _on_point_scored(_player_id: int, _score: int) -> void:
	flash(Color(1, 1, 0.5), 0.3)
	shake(0.025, 0.15)

func _on_net_hit() -> void:
	shake(0.015, 0.10)
