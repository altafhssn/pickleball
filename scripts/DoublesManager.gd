# DoublesManager.gd
# Manages 2v2 doubles match logic — partner AI, service rotation, scoring
extends Node

const BallRef = preload("res://scripts/Ball.gd")

# Scoring constants
const POINTS_TO_WIN: int = 11
const WIN_BY: int = 2

# Global serve rotation order: [team, position]
# Team 0 = player team, Team 1 = opponent team
# Position 0 = left, Position 1 = right
const SERVE_ROTATION: Array = [
	[0, 0],  # Player (team 0, left)
	[0, 1],  # Player Partner (team 0, right)
	[1, 1],  # Opponent (team 1, right)
	[1, 0],  # Opponent Partner (team 1, left)
]

# Match state
var is_active: bool = false
var team_scores: Array[int] = [0, 0]  # [player_team, opponent_team]
var serve_rotation_index: int = 0     # Index into SERVE_ROTATION
var serves_in_current_slot: int = 0   # Count of serves in current slot (max 2)
var match_complete: bool = false
var winner_team: int = -1

# References (set externally by Main.gd)
var ball_ref: RigidBody3D = null

# Partner AI state
var partner_reaction_timer: float = 0.0
var partner_is_reacting: bool = false
const PARTNER_REACTION_TIME: float = 0.4
const PARTNER_MOVE_SPEED: float = 2.5

# Signals
signal match_over(winner_team: int, scores: Array)
signal point_awarded(team_id: int, reason: String)
signal serve_ready(server_team: int, server_pos: int, side: int)

func start_doubles_match():
	is_active = true
	team_scores = [0, 0]
	serve_rotation_index = 0
	serves_in_current_slot = 0
	match_complete = false
	winner_team = -1
	partner_is_reacting = false
	partner_reaction_timer = 0.0
	
	EventBus.match_started.emit(2)  # match_type 2 = DOUBLES
	_prepare_serve()

func _prepare_serve():
	var current = SERVE_ROTATION[serve_rotation_index]
	serve_ready.emit(current[0], current[1], 0)

# Returns the current server info as [team, position]
func get_current_server() -> Array:
	return SERVE_ROTATION[serve_rotation_index].duplicate()

# Advances serve rotation to the next slot (after 2 serves)
func _advance_serve_rotation():
	serves_in_current_slot = 0
	serve_rotation_index = (serve_rotation_index + 1) % SERVE_ROTATION.size()

# === PARTNER AI ===

# Called each frame by Main.gd to update partner AI
func process_partner_ai(delta: float, partner_node: Node3D, ball_pos: Vector3, ball_in_play: bool):
	if not is_active or not ball_in_play or match_complete:
		return
	
	# Partner only reacts if ball is in their zone (right half, x > 0) AND on player's side (z < 0)
	if ball_pos.x > 0.05 and ball_pos.z < 0:
		if not partner_is_reacting:
			partner_is_reacting = true
			partner_reaction_timer = PARTNER_REACTION_TIME
		
		if partner_reaction_timer > 0:
			partner_reaction_timer -= delta
			# Move toward ball while reacting
			partner_node.position.x = move_toward(partner_node.position.x, ball_pos.x * 0.5, delta * PARTNER_MOVE_SPEED)
			partner_node.position.z = move_toward(partner_node.position.z, ball_pos.z + 0.1, delta * PARTNER_MOVE_SPEED)
		else:
			# Time to hit! Make a simple return shot
			partner_is_reacting = false
			_partner_hit_ball(partner_node, ball_pos)
	else:
		# Ball not in partner's zone — move back to default position
		partner_is_reacting = false
		partner_reaction_timer = 0.0
		partner_node.position.z = move_toward(partner_node.position.z, -0.8, delta * 1.5)
		if partner_node.position.x > 0.3:
			partner_node.position.x = move_toward(partner_node.position.x, 0.5, delta * 1.5)

func _partner_hit_ball(partner_node: Node3D, ball_pos: Vector3):
	if not ball_ref or not ball_ref.is_in_play:
		return
	
	# Simple shot selection: aim toward opponent's side with some spread
	var target_x = randf_range(-0.4, 0.4)
	var direction = Vector3(target_x, 0.2, 1.0).normalized()  # Hit toward opponent side
	var force = randf_range(0.4, 0.7)
	
	ball_ref.hit(force, direction, BallRef.ShotType.DRIVE)
	ball_ref.last_hitter_id = 2  # Partner hitter ID
	EventBus.ball_hit.emit(2, BallRef.ShotType.DRIVE, force)
	
	# Animate paddle swing
	_animate_partner_paddle(partner_node)

func _animate_partner_paddle(character: Node3D):
	var paddle = character.get_node("Paddle") if character.has_node("Paddle") else null
	if paddle:
		var tween = create_tween()
		tween.tween_property(paddle, "rotation:x", -1.5, 0.05)
		tween.tween_property(paddle, "rotation:x", 0.0, 0.2)

# Process opponent partner AI (the second opponent)
func process_opponent_partner_ai(delta: float, opp_partner_node: Node3D, ball_pos: Vector3, ball_in_play: bool):
	if not is_active or not ball_in_play or match_complete:
		return
	
	# Opponent partner covers left side (x < 0) on opponent's side (z > 0)
	if ball_pos.x < -0.05 and ball_pos.z > 0:
		if not opp_partner_node.has_meta("reacting") or not opp_partner_node.get_meta("reacting"):
			opp_partner_node.set_meta("reacting", true)
			opp_partner_node.set_meta("reaction_timer", 0.5)
		
		var timer = opp_partner_node.get_meta("reaction_timer", 0.0)
		timer -= delta
		opp_partner_node.set_meta("reaction_timer", timer)
		
		# Move toward ball
		opp_partner_node.position.x = move_toward(opp_partner_node.position.x, ball_pos.x * 0.5, delta * PARTNER_MOVE_SPEED)
		opp_partner_node.position.z = move_toward(opp_partner_node.position.z, ball_pos.z - 0.1, delta * PARTNER_MOVE_SPEED)
		
		if timer <= 0:
			# Hit the ball
			opp_partner_node.set_meta("reacting", false)
			_opponent_partner_hit(opp_partner_node, ball_pos)
	else:
		opp_partner_node.set_meta("reacting", false)
		opp_partner_node.set_meta("reaction_timer", 0.0)
		opp_partner_node.position.z = move_toward(opp_partner_node.position.z, 0.8, delta * 1.5)
		if opp_partner_node.position.x < -0.3:
			opp_partner_node.position.x = move_toward(opp_partner_node.position.x, -0.5, delta * 1.5)

func _opponent_partner_hit(opp_partner_node: Node3D, ball_pos: Vector3):
	if not ball_ref or not ball_ref.is_in_play:
		return
	
	var target_x = randf_range(-0.4, 0.4)
	var direction = Vector3(target_x, 0.2, -1.0).normalized()  # Hit toward player side
	var force = randf_range(0.4, 0.7)
	
	ball_ref.hit(force, direction, BallRef.ShotType.DRIVE)
	ball_ref.last_hitter_id = 3  # Opponent partner hitter ID
	EventBus.ball_hit.emit(3, BallRef.ShotType.DRIVE, force)
	
	_animate_partner_paddle(opp_partner_node)

# === SCORING ===

func award_point(scoring_team: int, reason: String = "") -> void:
	if match_complete:
		return
	
	team_scores[scoring_team] += 1
	point_awarded.emit(scoring_team, reason)
	
	# Check win condition
	if team_scores[scoring_team] >= POINTS_TO_WIN:
		var diff = team_scores[scoring_team] - team_scores[1 - scoring_team]
		if diff >= WIN_BY:
			_end_match(scoring_team)
			return
	
	# Service rotation: each player serves 2 points, then rotates
	serves_in_current_slot += 1
	if serves_in_current_slot >= 2:
		_advance_serve_rotation()
	
	_prepare_serve()

func award_point_from_rally(loser_team: int, reason: String = "Rally lost") -> void:
	var winner_team_calc = 1 if loser_team == 0 else 0
	award_point(winner_team_calc, reason)

func _end_match(team: int):
	match_complete = true
	winner_team = team
	EventBus.match_ended.emit(team, {"player_team": team_scores[0], "opponent_team": team_scores[1]})
	match_over.emit(team, team_scores)

func reset():
	is_active = false
	team_scores = [0, 0]
	serve_rotation_index = 0
	serves_in_current_slot = 0
	match_complete = false
	winner_team = -1
	partner_is_reacting = false
	partner_reaction_timer = 0.0
