# BallTrail.gd
# GPU particle trail VFX that follows the ball.
# Yellow/orange sparkle trail with emit rate proportional to ball speed
extends GPUParticles3D

@export var min_emit_rate: float = 10.0
@export var max_emit_rate: float = 100.0
@export var speed_threshold: float = 2.0
@export var move_speed: float = 30.0
@export var spin_influence: float = 0.5

var ball: RigidBody3D
var proc_mat: ParticleProcessMaterial
var sprite_mat: StandardMaterial3D
var quad_mesh: QuadMesh

func _ready() -> void:
	var parent = get_parent()
	while parent and not (parent is RigidBody3D):
		parent = parent.get_parent()
	if parent is RigidBody3D:
		ball = parent
	
	# Configure particle system (Godot 4 property names)
	one_shot = false
	emitting = true
	lifetime = 0.4
	preprocess = 0.0
	amount = 40
	fixed_fps = 0
	fract_delta = true
	interpolate = false
	draw_order = 1
	local_coords = true
	explosiveness = 0.0
	randomness = 0.2
	
	# Process material (controls particle behavior)
	proc_mat = ParticleProcessMaterial.new()
	proc_mat.gravity = Vector3(0, -0.3, 0)
	proc_mat.lifetime_randomness = 0.3
	proc_mat.initial_velocity_min = 0.3
	proc_mat.initial_velocity_max = 0.8
	proc_mat.direction = Vector3(0, 1, 0)
	proc_mat.spread = 45.0
	proc_mat.angular_velocity_min = 0.0
	proc_mat.angular_velocity_max = 360.0
	proc_mat.scale_min = 0.02
	proc_mat.scale_max = 0.08
	proc_mat.color = Color(1.0, 0.7, 0.1, 0.8)
	process_material = proc_mat
	
	# QuadMesh for particle sprite
	quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(0.06, 0.06)
	
	# Unshaded sprite material
	sprite_mat = StandardMaterial3D.new()
	sprite_mat.albedo_color = Color(1, 0.85, 0.2, 1)
	sprite_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sprite_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sprite_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_pass_1 = quad_mesh
	material_override = sprite_mat

func _process(delta: float) -> void:
	if not ball:
		return
	
	global_position = ball.global_position
	
	var speed: float = ball.linear_velocity.length()
	if speed < speed_threshold:
		emitting = false
		return
	
	emitting = true
	
	var t: float = clamp((speed - speed_threshold) / (move_speed - speed_threshold), 0.0, 1.0)
	var emit_factor: float = lerp(0.3, 1.0, t)
	amount = int(40 * emit_factor)
	
	# Adjust spread based on spin (trail curl effect)
	if "spin_vector" in ball:
		var spin_mag: float = ball.spin_vector.length()
		if spin_mag > 0.01 and proc_mat:
			var spin_factor: float = clamp(spin_mag * spin_influence, 0.0, 2.0)
			proc_mat.spread = 45.0 + spin_factor * 30.0
			proc_mat.initial_velocity_min = 0.3 + spin_factor * 0.5
			proc_mat.initial_velocity_max = 0.8 + spin_factor * 1.0
			
			if spin_mag > 0.5:
				var r = 1.0
				var g = 0.7 - spin_mag * 0.15
				var b = 0.1 - spin_mag * 0.05
				proc_mat.color = Color(clamp(r, 0.5, 1.0), clamp(g, 0.3, 0.7), clamp(b, 0.0, 0.1), 0.8)
			else:
				proc_mat.color = Color(1.0, 0.7, 0.1, 0.8)
	
	# Rotate to match ball direction for trail orientation
	if speed > 1.0:
		var dir = ball.linear_velocity.normalized()
		look_at(global_position + dir, Vector3.UP)
