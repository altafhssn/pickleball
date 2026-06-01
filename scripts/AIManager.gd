# AIManager.gd
# AI opponent behavior with difficulty levels
# Uses decision tree for shot selection
extends Node

const SHOT_TYPE = preload("res://scripts/Ball.gd")

# Difficulty levels
enum Difficulty {
	BEGINNER,
	CASUAL,
	PRO,
	ELITE,
	CHAMPION
}

# Difficulty configs
const DIFFICULTY_CONFIG = {
	Difficulty.BEGINNER: {
		"reaction_time": 0.8,
		"shot_accuracy": 0.6,
		"strategic_depth": 0.2,
		"name": "Beginner"
	},
	Difficulty.CASUAL: {
		"reaction_time": 0.6,
		"shot_accuracy": 0.7,
		"strategic_depth": 0.4,
		"name": "Casual"
	},
	Difficulty.PRO: {
		"reaction_time": 0.4,
		"shot_accuracy": 0.82,
		"strategic_depth": 0.6,
		"name": "Pro"
	},
	Difficulty.ELITE: {
		"reaction_time": 0.25,
		"shot_accuracy": 0.92,
		"strategic_depth": 0.8,
		"name": "Elite"
	},
	Difficulty.CHAMPION: {
		"reaction_time": 0.15,
		"shot_accuracy": 0.96,
		"strategic_depth": 1.0,
		"name": "Champion"
	}
}

# Current AI state
var difficulty: Difficulty = Difficulty.CASUAL
var reaction_timer: float = 0.0
var is_reacting: bool = false
var target_ball_position: Vector3 = Vector3.ZERO
var target_position: Vector3 = Vector3.ZERO
var player_position: Vector3 = Vector3.ZERO
var opponent_position: Vector3 = Vector3.ZERO
var last_ball_position: Vector3 = Vector3.ZERO
var ball_velocity: Vector3 = Vector3.ZERO

# Two-bounce rule tracking — mirrors Main's so the AI doesn't try to volley
# the serve. If the reaction timer expires before the required bounce has
# happened, we set awaiting_bounce and decide on the next ball_bounced event.
var bounces_since_last_hit: int = 0
var total_bounces: int = 0
var awaiting_bounce: bool = false

# Signals
signal ai_movement_target(position: Vector3)
signal ai_shot_selected(shot_type: int, direction: Vector3, force: float)

func _ready():
	EventBus.ball_hit.connect(_on_ball_hit_opponent)
	EventBus.ball_bounced.connect(_on_any_bounce)

func _on_any_bounce(_position: Vector3, _side: int) -> void:
	bounces_since_last_hit += 1
	total_bounces += 1
	# If we were holding back a decision waiting for the bounce, fire now.
	if awaiting_bounce:
		awaiting_bounce = false
		_make_decision()

func set_difficulty(diff: Difficulty) -> void:
	difficulty = diff

func _process(delta: float) -> void:
	if awaiting_bounce:
		return  # ball_bounced will trigger _make_decision
	if not is_reacting:
		return

	reaction_timer -= delta
	if reaction_timer <= 0.0:
		is_reacting = false
		# Two-bounce rule: until 2 total bounces, every hit must follow a
		# bounce. If we're not allowed to hit yet, defer until the next
		# bounce event.
		if total_bounces < 2 and bounces_since_last_hit < 1:
			awaiting_bounce = true
		else:
			_make_decision()

func _on_ball_hit_opponent(shooter_id: int, _shot_type: int, _force: float) -> void:
	# Any hit clears our "bounces since last hit" counter for the next
	# legality check.
	bounces_since_last_hit = 0
	# Player team = id 0 (player) or 2 (player partner); AI reacts to both.
	if shooter_id == 0 or shooter_id == 2:
		_start_reaction()

func _start_reaction() -> void:
	var config = DIFFICULTY_CONFIG[difficulty]
	reaction_timer = config["reaction_time"] + randf_range(-0.05, 0.05)
	is_reacting = true

func _make_decision() -> void:
	var config = DIFFICULTY_CONFIG[difficulty]
	
	# Decision tree from GDD spec:
	# 1. Can reach ball?
	var can_reach: bool = _can_reach_ball()
	if not can_reach:
		# Out of position — late weak return
		_make_desperate_return()
		return
	
	# 2. Is ball in kitchen?
	var ball_in_kitchen: bool = _is_ball_in_kitchen()
	if ball_in_kitchen:
		_dink_shot()
		return
	
	# 3. Is opponent at net?
	var opponent_at_net: bool = _is_opponent_at_net()
	if opponent_at_net:
		_lob_shot()
		return
	
	# 4. Player position-based decision
	var player_depth: String = _get_player_depth()
	match player_depth:
		"deep":
			_dink_shot()
		"mid":
			_drive_cross_court()
		"kitchen":
			_lob_shot()
		_:
			_drive_shot()
	
	# 5. Random variation — low-strategy AIs make more "non-optimal" choices
	# so BEGINNER feels spray-prone and CHAMPION feels disciplined.
	var strategy: float = config.get("strategic_depth", 0.5)
	var variation_chance: float = lerpf(0.35, 0.05, strategy)
	if randf() < variation_chance:
		_apply_random_variation()

func _can_reach_ball() -> bool:
	# Estimate if the AI can reach the ball before it arrives at its target.
	var distance: float = target_ball_position.distance_to(player_position)
	var time_to_ball: float = distance / 8.0  # AI moves at 8 units/s
	var ball_speed: float = maxf(ball_velocity.length(), 0.5)
	var time_until_arrival: float = distance / ball_speed

	return time_to_ball < time_until_arrival + 0.5

func _is_ball_in_kitchen() -> bool:
	return abs(target_ball_position.z) < 0.25 and target_ball_position.y < 0.3

func _is_opponent_at_net() -> bool:
	# Check if opponent is close to kitchen
	return abs(opponent_position.z) < 0.3

func _get_player_depth() -> String:
	var z: float = abs(player_position.z)
	if z > 0.6:
		return "deep"
	elif z > 0.25:
		return "mid"
	else:
		return "kitchen"

func _dink_shot() -> void:
	var config = DIFFICULTY_CONFIG[difficulty]
	var accuracy: float = config["shot_accuracy"]
	var direction: Vector3 = _get_aimed_direction(accuracy, 1.0 - accuracy)
	ai_shot_selected.emit(SHOT_TYPE.ShotType.DINK, direction, 0.5)

func _lob_shot() -> void:
	var config = DIFFICULTY_CONFIG[difficulty]
	var direction: Vector3 = _get_aimed_direction(config["shot_accuracy"], 0.3)
	ai_shot_selected.emit(SHOT_TYPE.ShotType.LOB, direction, 0.7 + randf() * 0.3)

func _drive_shot() -> void:
	var direction: Vector3 = _get_aimed_direction(0.8, 0.2)
	ai_shot_selected.emit(SHOT_TYPE.ShotType.DRIVE, direction, 0.6 + randf() * 0.4)

func _drive_cross_court() -> void:
	# Bias the cross-court target away from the human player when strategy is high.
	var config = DIFFICULTY_CONFIG[difficulty]
	var strategy: float = config.get("strategic_depth", 0.5)
	var away_side: float = -signf(opponent_position.x) if absf(opponent_position.x) > 0.05 else (1.0 if randf() > 0.5 else -1.0)
	var random_side: float = 1.0 if randf() > 0.5 else -1.0
	var side: float = away_side if randf() < strategy else random_side
	var direction: Vector3 = Vector3(side * 0.6, 0.0, -0.8).normalized()
	ai_shot_selected.emit(SHOT_TYPE.ShotType.DRIVE, direction, 0.7 + randf() * 0.3)

func _make_desperate_return() -> void:
	var direction: Vector3 = Vector3(randf_range(-0.3, 0.3), 0.5, -1.0).normalized()
	ai_shot_selected.emit(SHOT_TYPE.ShotType.DRIVE, direction, 0.3)

func _get_aimed_direction(accuracy: float, spread: float) -> Vector3:
	# Strategic aim: target the side of the court the player is NOT on.
	# At strategy=0 we ignore the player and spray randomly within `spread`;
	# at strategy=1 we aim sharply away from the player's current x.
	var config = DIFFICULTY_CONFIG[difficulty]
	var strategy: float = config.get("strategic_depth", 0.5)

	# Far-side target relative to the player; clamp to a sensible court band.
	var away_x: float = clampf(-opponent_position.x * 1.5, -0.4, 0.4)
	var random_x: float = randf_range(-spread, spread)
	var target_side: float = lerpf(random_x, away_x, strategy)

	# Inaccuracy: random offset if the accuracy roll fails.
	if randf() > accuracy:
		target_side += randf_range(-0.3, 0.3)

	return Vector3(target_side, 0.0, -1.0).normalized()

func _apply_random_variation() -> void:
	# 10-15% chance to do something unexpected
	var r: float = randf()
	if r < 0.3:
		_dink_shot()
	elif r < 0.6:
		_lob_shot()
	else:
		_drive_cross_court()

func update_ball_position(pos: Vector3) -> void:
	last_ball_position = target_ball_position
	target_ball_position = pos

func update_ball_velocity(vel: Vector3) -> void:
	ball_velocity = vel

func update_player_position(pos: Vector3) -> void:
	player_position = pos

func update_opponent_position(pos: Vector3) -> void:
	opponent_position = pos

func reset() -> void:
	is_reacting = false
	reaction_timer = 0.0
	awaiting_bounce = false
	bounces_since_last_hit = 0
	total_bounces = 0
