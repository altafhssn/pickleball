# PlayerController.gd
# Character controller shared by all four court characters (player, partner,
# opponent, opponent partner — they all instance Player.tscn).
#
# Visuals: tries to build an animated CharacterVisual from the FBX set in
# assets/Character. If those aren't imported yet, falls back to the original
# capsule + paddle placeholder with the idle-bob animation.
extends CharacterBody3D

const CharacterVisualRef = preload("res://scripts/CharacterVisual.gd")

# Placeholder idle bob parameters (fallback mode only)
const IDLE_AMPLITUDE: float = 0.01
const IDLE_PERIOD: float = 1.5

# Celebrate jump parameters (fallback mode only)
const CELEBRATE_JUMP_HEIGHT: float = 0.15
const CELEBRATE_JUMP_DURATION: float = 0.3

# Look-at rotation speed
const LOOK_AT_SPEED: float = 3.0
const MAX_YAW: float = 0.5  # ~28 degrees each way

@onready var body_mesh: MeshInstance3D = $Body
@onready var paddle: MeshInstance3D = $Paddle

# Animated visual (null → placeholder mode)
var visual: CharacterVisual = null

# State
var idle_time: float = 0.0
var is_celebrating: bool = false
var target_yaw: float = 0.0
var current_yaw: float = 0.0
var _last_position: Vector3 = Vector3.ZERO

func _ready() -> void:
	_last_position = global_position
	visual = CharacterVisualRef.new()
	visual.name = "Visual"
	add_child(visual)
	if visual.setup():
		# Rig active — hide placeholder primitives.
		if body_mesh:
			body_mesh.visible = false
		if paddle:
			paddle.visible = false
	else:
		visual.queue_free()
		visual = null

func is_animated() -> bool:
	return visual != null

func _process(delta: float) -> void:
	# Smoothly rotate body toward target yaw (both modes).
	current_yaw = move_toward(current_yaw, target_yaw, delta * LOOK_AT_SPEED)
	rotation.y = current_yaw

	if visual:
		_update_locomotion(delta)
		return

	# === Placeholder mode: idle bob ===
	if is_celebrating:
		return
	idle_time += delta
	var bob_offset = sin(idle_time * TAU / IDLE_PERIOD) * IDLE_AMPLITUDE
	if body_mesh:
		body_mesh.position.y = 0.1 + bob_offset

func _update_locomotion(delta: float) -> void:
	# Main.gd moves us by writing position directly, so derive velocity from
	# the position delta and feed it to the locomotion animations.
	var moved: Vector3 = global_position - _last_position
	_last_position = global_position
	if delta <= 0.0:
		return
	var vel: Vector3 = moved / delta
	# Character-local frame: facing_sign +1 when on the -z (player) side
	# facing the net, -1 when on the +z (opponent) side facing back.
	var facing_sign: float = 1.0 if global_position.z < 0.0 else -1.0
	var local_dir := Vector3(vel.x * facing_sign, 0, vel.z * facing_sign)
	visual.update_locomotion(local_dir, vel.length())

# === ACTIONS ===

# side > 0 → ball on the character's right.
func play_swing(side: float = 1.0) -> void:
	if visual:
		visual.play_smash(side)

func celebrate() -> void:
	if visual:
		visual.play_victory()
		return
	# Placeholder jump
	if is_celebrating:
		return
	is_celebrating = true
	if body_mesh:
		body_mesh.position.y = 0.1
	var tween = create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_method(_animate_celebrate_jump, 0.0, 1.0, CELEBRATE_JUMP_DURATION)
	tween.tween_callback(_finish_celebrate)

func play_defeat() -> void:
	if visual:
		visual.play_defeat()

func reset_pose() -> void:
	is_celebrating = false
	if visual:
		visual.reset_to_idle()

func _animate_celebrate_jump(progress: float) -> void:
	if not body_mesh:
		return
	var height: float
	if progress < 0.5:
		height = CELEBRATE_JUMP_HEIGHT * (progress * 2.0)
	else:
		height = CELEBRATE_JUMP_HEIGHT * (2.0 - progress * 2.0)
	body_mesh.position.y = 0.1 + height * 0.5

func _finish_celebrate() -> void:
	is_celebrating = false
	if body_mesh:
		body_mesh.position.y = 0.1

func look_at_ball(ball_position: Vector3) -> void:
	var relative_pos = ball_position - global_position
	var dir_2d = Vector2(relative_pos.x, relative_pos.z)
	if dir_2d.length() < 0.01:
		return
	# Absolute yaw that would point the node's +Z at the ball.
	var angle = atan2(relative_pos.x, relative_pos.z)
	# Each side has a natural facing: the player (-z side) faces +z (base 0),
	# the opponent (+z side) faces -z (base PI). Clamp the look-at to a small
	# turn around that base so both characters face each other across the
	# net instead of sharing one world direction.
	var base_yaw: float = 0.0 if global_position.z < 0.0 else PI
	var offset: float = wrapf(angle - base_yaw, -PI, PI)
	target_yaw = base_yaw + clampf(offset, -MAX_YAW, MAX_YAW)
