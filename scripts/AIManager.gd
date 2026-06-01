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

# Signals
signal ai_movement_target(position: Vector3)
signal ai_shot_selected(shot_type: int, direction: Vector3, force: float)

func _ready():
	EventBus.ball_hit.connect(_on_ball_hit_opponent)

func set_difficulty(diff: Difficulty) -> void:
	difficulty = diff

func _process(delta: float) -> void:
	if not is_reacting:
		return
	
	reaction_timer -= delta
	if reaction_timer <= 0.0:
		is_reacting = false
		_make_decision()

func _on_ball_hit_opponent(shooter_id: int, _shot_type: int, _force: float) -> void:
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
	
	# 5. Add random variation (10-15% non-optimal for realism)
	if randf() < 0.12:
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
	EventBus.ai_shot_selected.emit(SHOT_TYPE.ShotType.DINK, direction, 0.5)

func _lob_shot() -> void:
	var config = DIFFICULTY_CONFIG[difficulty]
	var direction: Vector3 = _get_aimed_direction(config["shot_accuracy"], 0.3)
	EventBus.ai_shot_selected.emit(SHOT_TYPE.ShotType.LOB, direction, 0.7 + randf() * 0.3)

func _drive_shot() -> void:
	var direction: Vector3 = _get_aimed_direction(0.8, 0.2)
	EventBus.ai_shot_selected.emit(SHOT_TYPE.ShotType.DRIVE, direction, 0.6 + randf() * 0.4)

func _drive_cross_court() -> void:
	var side: float = 1.0 if randf() > 0.5 else -1.0
	var direction: Vector3 = Vector3(side, 0.0, -0.8).normalized()
	EventBus.ai_shot_selected.emit(SHOT_TYPE.ShotType.DRIVE, direction, 0.7 + randf() * 0.3)

func _make_desperate_return() -> void:
	var direction: Vector3 = Vector3(randf_range(-0.3, 0.3), 0.5, -1.0).normalized()
	EventBus.ai_shot_selected.emit(SHOT_TYPE.ShotType.DRIVE, direction, 0.3)

func _get_aimed_direction(accuracy: float, spread: float) -> Vector3:
	var target_side: float = randf_range(-spread, spread)
	var target_z: float = -1.0  # Toward opponent
	
	if randf() > accuracy:
		target_side += randf_range(-0.3, 0.3)
	
	return Vector3(target_side, 0.0, target_z).normalized()

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
