# PlayerController.gd
# Player character controller with idle animation, celebrate, and ball-tracking
extends CharacterBody3D

# Idle bob parameters
const IDLE_AMPLITUDE: float = 0.01
const IDLE_PERIOD: float = 1.5

# Celebrate jump parameters
const CELEBRATE_JUMP_HEIGHT: float = 0.15
const CELEBRATE_JUMP_DURATION: float = 0.3

# Look-at rotation speed
const LOOK_AT_SPEED: float = 3.0

# Body rotation limits
const MAX_YAW: float = 0.5  # ~28 degrees each way

# References
@onready var body_mesh: MeshInstance3D = $Body
@onready var paddle: MeshInstance3D = $Paddle

# State
var idle_time: float = 0.0
var is_celebrating: bool = false
var target_yaw: float = 0.0
var current_yaw: float = 0.0

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	if is_celebrating:
		return  # Don't idle bob while celebrating
	
	# Idle bob animation: gentle y-axis sine wave
	idle_time += delta
	var bob_offset = sin(idle_time * TAU / IDLE_PERIOD) * IDLE_AMPLITUDE
	
	if body_mesh:
		body_mesh.position.y = 0.1 + bob_offset
	
	# Smoothly rotate body toward target yaw
	current_yaw = move_toward(current_yaw, target_yaw, delta * LOOK_AT_SPEED)
	rotation.y = current_yaw

func celebrate() -> void:
	if is_celebrating:
		return
	
	is_celebrating = true
	
	# Reset body position to base
	if body_mesh:
		body_mesh.position.y = 0.1
	
	# Create tween for jump animation
	var tween = create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_method(_animate_celebrate_jump, 0.0, 1.0, CELEBRATE_JUMP_DURATION)
	tween.tween_callback(_finish_celebrate)

func _animate_celebrate_jump(progress: float) -> void:
	if not body_mesh:
		return
	
	# Jump up then come back down
	var height: float
	if progress < 0.5:
		# Going up (first half)
		height = CELEBRATE_JUMP_HEIGHT * (progress * 2.0)
	else:
		# Coming down (second half)
		height = CELEBRATE_JUMP_HEIGHT * (2.0 - progress * 2.0)
	
	body_mesh.position.y = 0.1 + height * 0.5  # Scale down for subtlety

func _finish_celebrate() -> void:
	is_celebrating = false
	if body_mesh:
		body_mesh.position.y = 0.1

func look_at_ball(ball_position: Vector3) -> void:
	# Calculate relative direction from this character to the ball
	var relative_pos = ball_position - global_position
	
	# Only rotate on yaw (y-axis), ignore height
	var dir_2d = Vector2(relative_pos.x, relative_pos.z)
	if dir_2d.length() < 0.01:
		return
	
	var angle = atan2(relative_pos.x, relative_pos.z)
	
	# Clamp the rotation so the character doesn't fully turn around
	target_yaw = clampf(angle, -MAX_YAW, MAX_YAW)
