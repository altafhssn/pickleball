# Ball.gd
# Pickleball physics object with authentic wiffle ball drag
extends RigidBody3D

# Shot type enum (matches PRD/GDD spec)
enum ShotType { DINK, DRIVE, LOB, VOLLEY, ERNE, ATP }

# Export vars — tuneable in editor.
# Speeds are tuned for the in-engine court (3 units long), NOT real-world
# pickleball metres. A real 13 m court at 30 mph drive scales to about
# 3 m/s in our units; we round up slightly so shots feel snappy.
@export var base_speed: float = 5.0
@export var max_speed: float = 12.0
@export var spin_factor: float = 0.3
# Quadratic drag dominates at high speeds; linear drag handles the slow,
# floaty tail so the wiffle ball decelerates the way it should.
@export var drag_coefficient: float = 0.08
@export var linear_drag: float = 0.45
# Ball stops when it's basically at rest on the floor — avoids endless
# micro-bouncing after a dink lands.
@export var rest_speed_threshold: float = 0.35
@export var rest_height_threshold: float = 0.08

# Ball state
var spin_vector: Vector3 = Vector3.ZERO  # Topspin/backspin/sidespin
var shot_type: ShotType = ShotType.DRIVE
var last_hitter_id: int = -1
var has_bounced_this_side: bool = false
var is_in_play: bool = false
# True once the rest-stop logic has fired its synthetic bounce for the
# current rally segment. Cleared on every hit() / serve() / reset().
var rest_fired: bool = false

# Signals
signal ball_landed(position: Vector3, side: int)  # side: 0=player, 1=opponent
signal ball_hit_net
signal ball_lost(was_out: bool)

func _ready():
	# RigidBody flags + PhysicsMaterial live in Ball.tscn so the engine sees
	# them on first physics tick. We only wire collisions here.
	body_entered.connect(_on_body_entered)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not is_in_play:
		return

	var velocity: Vector3 = state.linear_velocity
	var speed: float = velocity.length()

	# Rest-stop: ball nearly motionless near the floor → kill velocity so it
	# doesn't dribble forever after a soft bounce. Fire one synthetic bounce
	# event so Main's rally end-condition can count "dead ball" as a miss.
	if speed < rest_speed_threshold and state.transform.origin.y <= rest_height_threshold:
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		if not rest_fired:
			rest_fired = true
			var pos: Vector3 = state.transform.origin
			var side: int = 0 if pos.z < 0 else 1
			ball_landed.emit(pos, side)
			EventBus.ball_bounced.emit(pos, side)
		return

	if speed < 0.05:
		return

	# === Wiffle ball drag ===
	# Quadratic term dominates at high speeds (fast drives bleed off quickly);
	# linear term keeps the slow tail from feeling floaty (real wiffle balls
	# decelerate strongly even at low speed because of all the holes).
	var dir: Vector3 = velocity / speed
	var drag_force: Vector3 = -dir * (speed * speed * drag_coefficient + speed * linear_drag)
	state.apply_central_force(drag_force)

	# Magnus effect from spin.
	if spin_vector.length() > 0.01:
		var magnus_force: Vector3 = spin_vector.cross(velocity) * spin_factor * 0.1
		state.apply_central_force(magnus_force)

	# Hard cap so a runaway integrator can't punt the ball off the world.
	if speed > max_speed:
		state.linear_velocity = dir * max_speed

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

func hold_for_serve(at_position: Vector3) -> void:
	# Park the ball mid-air for the serve setup. Freeze so gravity doesn't
	# drop it while the server (or the user) is preparing.
	global_position = at_position
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	spin_vector = Vector3.ZERO
	has_bounced_this_side = false
	rest_fired = false
	is_in_play = false
	freeze = true

func serve(from_position: Vector3, target_position: Vector3, power: float = 1.0) -> void:
	freeze = false
	global_position = from_position
	is_in_play = true
	has_bounced_this_side = false
	rest_fired = false
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
	rest_fired = false

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
	freeze = false
	is_in_play = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	spin_vector = Vector3.ZERO
	shot_type = ShotType.DRIVE
	has_bounced_this_side = false
	rest_fired = false
	global_position = Vector3.ZERO
