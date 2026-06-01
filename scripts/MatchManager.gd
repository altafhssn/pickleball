# MatchManager.gd
# Match lifecycle, pickleball rules, scoring
extends Node

# Match types
enum MatchType { QUICK, RANKED, DOUBLES, PRACTICE }

# Scoring constants
const POINTS_TO_WIN: int = 11
const WIN_BY: int = 2

# Current match state
var match_type: MatchType = MatchType.QUICK
var is_doubles: bool = false
var player_scores: Array[int] = [0, 0]  # [player, opponent]
var current_server: int = 0  # 0=player, 1=opponent
var current_serve_side: int = 0  # 0=left, 1=right (for doubles)
var hits_in_rally: int = 0
var rally_number: int = 0
var ball_on_player_side: bool = false
var match_complete: bool = false
var winner_id: int = -1

# Signals
signal serve_ready(server_id: int, side: int)
signal point_awarded(scorer_id: int, reason: String)
signal match_over(winner_id: int, final_scores: Array)
signal fault_declared(player_id: int, reason: String)

func _ready():
	EventBus.ball_bounced.connect(_on_ball_bounced)
	EventBus.ball_net_hit.connect(_on_ball_net_hit)
	EventBus.ball_hit.connect(_on_ball_hit)
	EventBus.rally_began.connect(_on_rally_began)

func start_match(type: MatchType, doubles: bool = false) -> void:
	match_type = type
	is_doubles = doubles
	player_scores = [0, 0]
	current_server = 0
	current_serve_side = 0
	hits_in_rally = 0
	rally_number = 0
	match_complete = false
	winner_id = -1
	
	EventBus.match_started.emit(match_type)
	_prepare_serve()

func _prepare_serve() -> void:
	hits_in_rally = 0
	ball_on_player_side = current_server == 0
	EventBus.serve_ready.emit(current_server, current_serve_side)

# === PICKLEBALL RULES ===

# 1. TWO-BOUNCE RULE
# First two hits (serve + return of serve) must bounce
func must_ball_bounce() -> bool:
	return hits_in_rally < 2

# 2. KITCHEN ZONE (No Volley Zone)
func check_kitchen_violation(hitter_position: Vector3, player_is_hitter: bool) -> bool:
	# Player cannot volley while standing in the kitchen
	# Simplified: check if position is within kitchen bounds
	var in_kitchen: bool = _is_in_kitchen(hitter_position, player_is_hitter)
	return in_kitchen and not must_ball_bounce()

# 3. UNDERHAND SERVE VALIDATION
func validate_serve(swing_direction: String, contact_height: float) -> bool:
	if swing_direction != "up":
		return false  # Must be underhand (upward swing)
	if contact_height > 0.914:
		return false  # Waist height (36 inches = 0.914m) max
	return true

func _is_in_kitchen(position: Vector3, is_player_side: bool) -> bool:
	# Kitchen extends 0.2 units from net on each side
	# Net is at z=0, player side is z>0, opponent side is z<0
	var z_pos = position.z if is_player_side else -position.z
	return z_pos >= 0.0 and z_pos <= 0.2

# === EVENT HANDLERS ===

func _on_ball_bounced(_position: Vector3, side: int) -> void:
	# Ball bounced on one side
	if side == 0:
		ball_on_player_side = true
	else:
		ball_on_player_side = false

func _on_ball_net_hit() -> void:
	# Ball hit the net — fault if it was a serve, otherwise loss of point
	if hits_in_rally == 0:
		# Serve into net = fault
		_award_point(1 if current_server == 0 else 0, "Serve into net")
	else:
		_award_point(1 if ball_on_player_side else 0, "Ball hit net")

func _on_ball_hit(shooter_id: int, _shot_type: int, _force: float) -> void:
	hits_in_rally += 1
	
	# Check kitchen violation on volley
	if must_ball_bounce():
		# Player is volleying before the two-bounce — legal for non-first-two hits
		pass

func _on_rally_began() -> void:
	rally_number += 1

func record_hit() -> void:
	hits_in_rally += 1

func award_point_from_rally(loser_id: int, reason: String = "Rally lost") -> void:
	var winner_id_calc: int = 1 if loser_id == 0 else 0
	_award_point(winner_id_calc, reason)

func _award_point(scorer_id: int, reason: String = "") -> void:
	player_scores[scorer_id] += 1
	EventBus.point_scored.emit(scorer_id, player_scores[scorer_id])
	EventBus.point_awarded.emit(scorer_id, reason)
	
	# Check win condition
	if player_scores[scorer_id] >= POINTS_TO_WIN:
		var score_diff = player_scores[scorer_id] - player_scores[1 - scorer_id]
		if score_diff >= WIN_BY:
			_end_match(scorer_id)
			return
	
	# Switch server after losing a point (in traditional scoring)
	# In rally scoring, the scorer serves next
	current_server = scorer_id
	_prepare_serve()

func _end_match(winner: int) -> void:
	match_complete = true
	winner_id = winner
	EventBus.match_ended.emit(winner, {"player": player_scores[0], "opponent": player_scores[1]})
	EventBus.match_over.emit(winner, player_scores)

func reset_rally() -> void:
	hits_in_rally = 0
	ball_on_player_side = false

func get_score_text() -> String:
	return str(player_scores[0]) + " - " + str(player_scores[1])
