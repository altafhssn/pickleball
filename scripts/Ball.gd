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
# Quadratic drag only — linear was overkill and made shots die in flight.
# With mass 0.5 and these constants, a 5 m/s shot loses ~0.5 m/s over a
# typical 0.5s flight, which feels right without breaking the projectile
# math used by Ball.serve().
@export var drag_coefficient: float = 0.02
@export var linear_drag: float = 0.0
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
	# doesn't dribble forever after a soft bounce. The rally end-condition
	# (Main._check_ball_stuck) will end the point after BALL_REST_TIMEOUT.
	# We deliberately don't emit a synthetic bounce here — that previously
	# triggered the AI to apply a fresh velocity to a stationary ball, which
	# looked like a teleport.
	if speed < rest_speed_threshold and state.transform.origin.y <= rest_height_threshold:
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
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
		# Visible-bounce guarantee. The engine's bounce response only
		# preserves bounce * |incoming_vy|; for shallow-angle shots the
		# vy at impact is tiny and the ball appears to slide. If we have
		# meaningful horizontal speed but negligible post-bounce lift,
		# force a visible upward kick. Deferred so we run after the
		# engine has applied its own bounce response.
		call_deferred("_ensure_visible_bounce")

func _ensure_visible_bounce() -> void:
	const MIN_BOUNCE_VY: float = 0.9
	const HORIZ_THRESHOLD: float = 1.0
	var horiz_speed: float = Vector2(linear_velocity.x, linear_velocity.z).length()
	if linear_velocity.y >= 0.0 and linear_velocity.y < MIN_BOUNCE_VY and horiz_speed > HORIZ_THRESHOLD:
		linear_velocity.y = MIN_BOUNCE_VY

func hold_for_serve(at_position: Vector3) -> void:
	# Park the ball mid-air for the serve setup. Suspending gravity (rather
	# than using freeze) keeps the body fully dynamic, so the velocity we
	# assign in serve() applies immediately on the next physics tick.
	global_position = at_position
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	spin_vector = Vector3.ZERO
	has_bounced_this_side = false
	rest_fired = false
	is_in_play = false
	gravity_scale = 0.0

func serve(from_position: Vector3, target_position: Vector3, power: float = 1.0) -> void:
	gravity_scale = 1.0
	global_position = from_position
	is_in_play = true
	has_bounced_this_side = false
	rest_fired = false
	shot_type = ShotType.DRIVE

	# Solve projectile motion to land *exactly* at target_position.y = 0
	# starting from from_position with a chosen flight time. Higher power
	# = shorter flight time = flatter, faster shot. Long flight times so
	# the rally has a readable beat-beat-beat rhythm.
	var flight_time: float = lerpf(1.80, 1.20, clampf(power, 0.0, 1.0))
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

	# y(t) = from.y + vy*t - 0.5*g*t² = target.y
	var vy: float = (target_position.y - from_position.y + 0.5 * g * flight_time * flight_time) / flight_time

	# Horizontal — straight to target.
	var dx: float = target_position.x - from_position.x
	var dz: float = target_position.z - from_position.z
	var vx: float = dx / flight_time
	var vz: float = dz / flight_time

	linear_velocity = Vector3(vx, vy, vz)

func hit(force: float, direction: Vector3, shot: ShotType, spin: Vector3 = Vector3.ZERO) -> void:
	if not is_in_play:
		is_in_play = true

	shot_type = shot
	spin_vector = spin
	has_bounced_this_side = false
	rest_fired = false

	# Speed and arc tuned for the actual court: hitters sit at z ≈ ±0.8, the
	# net is at z=0 and 0.16 tall. Distance to net is short so the ball has
	# very little time to climb — flat shots from a low ball position clip
	# the net unless we enforce a healthy arc.
	#
	# These constants were chosen by trajectory-checking each shot type
	# against gravity (9.8) and the actual court geometry, picking values
	# that clear the net AND land in-bounds on the opposite side.
	var dir: Vector3 = direction
	var shot_speed: float = base_speed * force
	# Speeds reduced ~20% from previous tuning to give the player visible
	# reaction time. Combined with a shorter (0.10) net, all shots still
	# clear consistently.
	match shot:
		ShotType.DINK:
			shot_speed = 2.5 + (force * 0.8)         # 2.5–3.3
			dir.y = maxf(dir.y, 1.0)
		ShotType.DRIVE:
			shot_speed = 3.5 + (force * 1.7)         # 3.5–5.2
			dir.y = maxf(dir.y, 0.35)
		ShotType.LOB:
			shot_speed = 3.0 + (force * 1.3)         # 3.0–4.3
			dir.y = 1.5 + (force * 0.5)
		ShotType.VOLLEY:
			shot_speed = 3.0 + (force * 2.0)         # 3.0–5.0
			dir.y = maxf(dir.y, 0.30)
		ShotType.ERNE:
			shot_speed = 3.5 + (force * 1.7)
			dir.y = maxf(dir.y, 0.40)
		ShotType.ATP:
			shot_speed = 2.5 + (force * 1.7)
			dir.y = maxf(dir.y, 0.35)

	linear_velocity = dir.normalized() * shot_speed

func reset() -> void:
	gravity_scale = 1.0
	is_in_play = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	spin_vector = Vector3.ZERO
	shot_type = ShotType.DRIVE
	has_bounced_this_side = false
	rest_fired = false
	global_position = Vector3.ZERO
