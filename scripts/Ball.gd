# Ball.gd
# Pickleball physics object with authentic wiffle ball drag
extends RigidBody3D

# Shot type enum (matches PRD/GDD spec)
enum ShotType { DINK, DRIVE, LOB, VOLLEY, ERNE, ATP }

# Export vars — tuneable in editor.
# Speeds are tuned for the in-engine court (~1.6 units long), NOT real-world
# pickleball metres. A real 13 m court at 30 mph drive would mean ~3.5 m/s
# in our scaled units; we round up slightly so shots feel snappy.
@export var base_speed: float = 5.0
@export var max_speed: float = 12.0
@export var spin_factor: float = 0.3
@export var drag_coefficient: float = 0.08  # ~4x tennis ball drag

# Ball state
var spin_vector: Vector3 = Vector3.ZERO  # Topspin/backspin/sidespin
var shot_type: ShotType = ShotType.DRIVE
var last_hitter_id: int = -1
var has_bounced_this_side: bool = false
var is_in_play: bool = false

# Signals
signal ball_landed(position: Vector3, side: int)  # side: 0=player, 1=opponent
signal ball_hit_net
signal ball_lost(was_out: bool)

func _ready():
	# Configure RigidBody3D for pickleball physics.
	# We use the default integrator for gravity + bounce, and add drag/Magnus
	# additively in _integrate_forces.
	gravity_scale = 1.0
	custom_integrator = false
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	can_sleep = false
	
	# Use a PhysicsMaterial for bounce/friction
	var mat = PhysicsMaterial.new()
	mat.bounce = 0.4
	mat.friction = 0.6
	physics_material_override = mat
	
	# Connect body_entered for collision detection
	body_entered.connect(_on_body_entered)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not is_in_play:
		return
	
	var velocity: Vector3 = state.linear_velocity
	var speed: float = velocity.length()
	
	if speed < 0.1:
		return
	
	# === Authentic Wiffle Ball Drag ===
	# Quadratic drag: F = -v * |v| * Cd
	# Pickleball drag coefficient is ~4x higher than a tennis ball
	# due to the holes in the wiffle ball
	var drag_force: Vector3 = -velocity.normalized() * speed * speed * drag_coefficient
	state.apply_central_force(drag_force)
	
	# Apply spin force (Magnus effect)
	if spin_vector.length() > 0.01:
		var magnus_force: Vector3 = spin_vector.cross(velocity) * spin_factor * 0.1
		state.apply_central_force(magnus_force)
	
	# Clamp speed
	if speed > max_speed:
		state.linear_velocity = velocity.normalized() * max_speed

func _on_body_entered(body: Node) -> void:
	# Detect net hits
	if body.is_in_group("net"):
		ball_hit_net.emit()
		EventBus.ball_net_hit.emit()
		is_in_play = false
	
	# Detect ground/floor bounces
	if body.is_in_group("court_floor"):
		has_bounced_this_side = true
		var side: int = 0 if global_position.z < 0 else 1
		ball_landed.emit(global_position, side)
		EventBus.ball_bounced.emit(global_position, side)

func serve(from_position: Vector3, target_position: Vector3, power: float = 1.0) -> void:
	global_position = from_position
	is_in_play = true
	has_bounced_this_side = false
	shot_type = ShotType.DRIVE
	
	# Calculate launch velocity toward target
	var direction: Vector3 = (target_position - from_position).normalized()
	var speed: float = base_speed * power
	linear_velocity = direction * speed
	
	# Add slight upward angle for net clearance
	linear_velocity.y = linear_velocity.length() * 0.15

func hit(force: float, direction: Vector3, shot: ShotType, spin: Vector3 = Vector3.ZERO) -> void:
	if not is_in_play:
		is_in_play = true

	shot_type = shot
	spin_vector = spin
	has_bounced_this_side = false

	# Speed and arc tuned per shot type. Net is ~0.16 tall, court half-length
	# is ~0.8 from baseline-ish position to net — without enough vertical
	# direction the ball clips the net or hits the floor first, especially
	# for slow dinks. Enforce a minimum arc here so callers can't underfly.
	var dir: Vector3 = direction
	var shot_speed: float = base_speed * force
	match shot:
		ShotType.DINK:
			shot_speed = 2.5 + (force * 1.0)         # Slow & arced: 2.5–3.5
			dir.y = maxf(dir.y, 0.55)
		ShotType.DRIVE:
			shot_speed = 4.0 + (force * 3.0)         # Fast: 4–7
			dir.y = maxf(dir.y, 0.20)
		ShotType.LOB:
			shot_speed = 3.0 + (force * 1.5)         # Medium: 3–4.5
			dir.y = 0.7 + (force * 0.3)              # High arc — overrides
		ShotType.VOLLEY:
			shot_speed = 3.0 + (force * 3.0)         # Fast: 3–6
			dir.y = maxf(dir.y, 0.15)
		ShotType.ERNE:
			shot_speed = 4.0 + (force * 2.5)         # Fast: 4–6.5
			dir.y = maxf(dir.y, 0.25)
		ShotType.ATP:
			shot_speed = 2.5 + (force * 3.0)         # Varied: 2.5–5.5
			dir.y = maxf(dir.y, 0.25)

	linear_velocity = dir.normalized() * shot_speed

func reset() -> void:
	is_in_play = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	spin_vector = Vector3.ZERO
	shot_type = ShotType.DRIVE
	has_bounced_this_side = false
	global_position = Vector3.ZERO
