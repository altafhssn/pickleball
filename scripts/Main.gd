# Main.gd
# Game orchestrator — wires input, AI, ball physics, scoring into a playable loop
# Supports both singles and doubles (2v2) modes
extends Node

# Preload for enum access
const GameStateRef = preload("res://scripts/GameState.gd")
const MatchManagerRef = preload("res://scripts/MatchManager.gd")
const AIManagerRef = preload("res://scripts/AIManager.gd")
const BallRef = preload("res://scripts/Ball.gd")
const DoublesManagerRef = preload("res://scripts/DoublesManager.gd")

# Scene references (populated at runtime)
@onready var game_state: Node = $GameState
@onready var match_manager: Node = $MatchManager
@onready var input_handler: Node = $InputHandler
@onready var ai_manager: Node = $AIManager
@onready var doubles_manager: Node = $DoublesManager
@onready var court: Node3D = $Court
@onready var player: Node3D = $Player
@onready var player_partner: Node3D = $PlayerPartner
@onready var opponent: Node3D = $Opponent
@onready var opponent_partner: Node3D = $OpponentPartner
@onready var ball: RigidBody3D = $Ball
@onready var hud: CanvasLayer = $HUD
@onready var camera: Camera3D = $Camera3D
@onready var game_feel: Node = $GameFeel
@onready var hit_vfx_scene: PackedScene = preload("res://scenes/Gameplay/HitVFX.tscn")

# Gameplay state
var is_doubles: bool = false
var is_player_serving: bool = true
var can_hit_ball: bool = false
var player_serve_ready: bool = false
var rally_active: bool = false

# Power meter
var power_charge: float = 0.0
var is_charging: bool = false
var power_meter_visible: bool = false

# Challenge tracking
var last_player_shot_type: int = -1

# Paddle animation
var paddle_swing_timer: float = 0.0
const PADDLE_SWING_DURATION: float = 0.2

# Doubles positions
const PLAYER_LEFT: float = -0.5
const PLAYER_RIGHT: float = 0.5
const PLAYER_BASELINE: float = -0.8
const OPPONENT_BASELINE: float = 0.8

func _ready():
	EventBus.swipe_detected.connect(_on_swipe_detected)
	EventBus.tap_detected.connect(_on_tap_detected)
	EventBus.double_tap_detected.connect(_on_double_tap)
	EventBus.drag_detected.connect(_on_drag)
	ai_manager.ai_shot_selected.connect(_on_ai_shot_selected)
	match_manager.point_awarded.connect(_on_point_awarded)
	match_manager.serve_ready.connect(_on_serve_ready)
	match_manager.match_over.connect(_on_match_over)
	doubles_manager.point_awarded.connect(_on_doubles_point_awarded)
	doubles_manager.serve_ready.connect(_on_doubles_serve_ready)
	doubles_manager.match_over.connect(_on_doubles_match_over)
	
	ball.ball_landed.connect(_on_ball_landed)
	ball.ball_hit_net.connect(_on_ball_hit_net)
	
	# Initialize game feel
	game_feel.setup(camera, hud)
	
	# Connect hit VFX
	EventBus.ball_hit.connect(_spawn_hit_vfx)
	
	# Pass ball reference to doubles manager
	doubles_manager.ball_ref = ball
	
	# Initially hide partner nodes
	_hide_doubles_characters()
	
	_show_menu()

# === HIT VFX ===

func _spawn_hit_vfx(_shooter_id: int, _shot_type: int, _force: float) -> void:
	var vfx = hit_vfx_scene.instantiate()
	add_child(vfx)
	vfx.global_position = ball.global_position
	vfx.emitting = true
	# Auto-cleanup
	await get_tree().create_timer(0.5).timeout
	vfx.queue_free()

func _show_menu() -> void:
	var menu_scene = load("res://scenes/Menus/MainMenu.tscn")
	var menu = menu_scene.instantiate()
	add_child(menu)
	menu.start_quick_match.connect(_on_menu_start_quick)
	menu.start_practice.connect(_on_menu_start_practice)
	menu.start_doubles.connect(_on_menu_start_doubles)
	menu.open_shop.connect(_on_open_shop)
	menu.start_tournament.connect(_on_menu_start_tournament)
	menu.open_challenges.connect(_on_menu_open_challenges)
	game_state.transition_to(GameStateRef.State.MENU)

func _on_menu_start_quick() -> void:
	_remove_menu()
	start_quick_match()

func _on_menu_start_practice() -> void:
	_remove_menu()
	_start_practice_match()

func _on_menu_start_doubles() -> void:
	_remove_menu()
	start_doubles_match()

func _on_open_shop() -> void:
	_remove_menu()
	_open_shop()

func _on_menu_start_tournament() -> void:
	_remove_menu()
	_open_tournament()

func _on_menu_open_challenges() -> void:
	_remove_menu()
	_open_challenges()

func _open_shop() -> void:
	var shop_scene = load("res://scenes/Menus/Shop.tscn")
	var shop = shop_scene.instantiate()
	shop.shop_closed.connect(_on_shop_closed)
	add_child(shop)
	
func _on_shop_closed() -> void:
	_remove_menu_name("Shop")
	_show_menu()

func _open_tournament() -> void:
	var tournament_scene = load("res://scenes/Menus/Tournament.tscn")
	var tournament = tournament_scene.instantiate()
	tournament.setup($TournamentManager if has_node("TournamentManager") else null)
	tournament.play_tournament_round.connect(_on_tournament_play_round)
	tournament.tournament_closed.connect(_on_tournament_closed)
	add_child(tournament)

func _open_challenges() -> void:
	var challenges_scene = load("res://scenes/Menus/Challenges.tscn")
	var challenges = challenges_scene.instantiate()
	challenges.setup($ChallengeManager if has_node("ChallengeManager") else null)
	challenges.challenges_closed.connect(_on_challenges_closed)
	add_child(challenges)

func _on_tournament_play_round(_opponent_name: String, difficulty: int) -> void:
	# Start a match with tournament AI difficulty
	_hide_doubles_characters()
	_reset_rally()
	match_manager.start_match(MatchManagerRef.MatchType.QUICK)
	game_state.transition_to(GameStateRef.State.SERVE_WAIT)
	ai_manager.set_difficulty(difficulty)
	player.position = Vector3(0, 0, PLAYER_BASELINE)
	opponent.position = Vector3(0, 0, OPPONENT_BASELINE)
	hud.update_score(0, 0)
	hud.show_serve_indicator("Tournament match — " + _opponent_name)
	_on_serve_ready(0, 0)

func _on_tournament_closed() -> void:
	_remove_menu_name("Tournament")
	_show_menu()

func _on_challenges_closed() -> void:
	_remove_menu_name("Challenges")
	_show_menu()

func _remove_menu() -> void:
	for child in get_children():
		if child is CanvasLayer and child.name != "HUD":
			remove_child(child)
			child.queue_free()

func _remove_menu_name(name: String) -> void:
	for child in get_children():
		if child.name == name:
			remove_child(child)
			child.queue_free()

func _start_practice_match() -> void:
	_hide_doubles_characters()
	match_manager.start_match(MatchManagerRef.MatchType.PRACTICE)
	game_state.transition_to(GameStateRef.State.SERVE_WAIT)
	ai_manager.set_difficulty(AIManagerRef.Difficulty.CASUAL)
	
	player.position = Vector3(0, 0, PLAYER_BASELINE)
	opponent.position = Vector3(0, 0, OPPONENT_BASELINE)
	
	ball.reset()
	ball.position = Vector3(0, 0.05, 0)
	
	_update_camera()

func _hide_doubles_characters() -> void:
	is_doubles = false
	if player_partner:
		player_partner.visible = false
	if opponent_partner:
		opponent_partner.visible = false

func _show_doubles_characters() -> void:
	is_doubles = true
	if player_partner:
		player_partner.visible = true
	if opponent_partner:
		opponent_partner.visible = true

func _process(delta: float) -> void:
	EventBus.frame_update.emit(delta)
	
	if ball.is_in_play:
		ai_manager.update_ball_position(ball.position)
		ai_manager.update_player_position(opponent.position)
		ai_manager.update_opponent_position(player.position)
		
		if is_doubles:
			# Update doubles partner AI
			doubles_manager.process_partner_ai(delta, player_partner, ball.position, ball.is_in_play)
			doubles_manager.process_opponent_partner_ai(delta, opponent_partner, ball.position, ball.is_in_play)
	
	_update_player_auto_move(delta)
	_update_paddle_swing(delta)
	_update_power_meter(delta)
	_update_screen_effects(delta)
	
	# Make characters look toward the ball each frame
	_update_characters_look_at_ball()

func _update_player_auto_move(delta: float) -> void:
	var player_target_z = PLAYER_BASELINE
	var opp_target_z = OPPONENT_BASELINE
	var player_target_x = 0.0
	var opp_target_x = 0.0
	
	if ball.is_in_play:
		if ball.position.z < 0:
			# Ball on player's side
			if is_doubles:
				# Player covers left half (x < 0), partner covers right half (x > 0)
				if ball.position.x < 0:
					player_target_z = clampf(ball.position.z + 0.1, -0.9, -0.1)
					player_target_x = clampf(ball.position.x, -0.5, 0.0)
				else:
					# Ball on partner's side — stay in position
					player_target_z = PLAYER_BASELINE
					player_target_x = PLAYER_LEFT
			else:
				player_target_z = clampf(ball.position.z + 0.1, -0.9, -0.1)
			# Opponent side auto-move (singles)
			if not is_doubles:
				opp_target_z = clampf(ball.position.z - 0.1, 0.1, 0.9)
		else:
			# Ball on opponent's side
			if not is_doubles:
				opp_target_z = clampf(ball.position.z - 0.1, 0.1, 0.9)
		
		# Opponent partner covers left opponent side in doubles
		if is_doubles and ball.position.z > 0:
			if ball.position.x < 0:
				opp_target_z = clampf(ball.position.z - 0.1, 0.1, 0.9)
	
	player.position.x = move_toward(player.position.x, player_target_x if is_doubles else 0.0, delta * 2.0)
	player.position.z = move_toward(player.position.z, player_target_z, delta * 2.0)
	
	if not is_doubles:
		opponent.position.z = move_toward(opponent.position.z, opp_target_z, delta * 2.0)

func _update_camera() -> void:
	var target_z = ball.position.z * 0.3
	if is_doubles:
		# Slightly wider camera for doubles
		camera.position.z = move_toward(camera.position.z, 2.8 + target_z, 0.5)
	else:
		camera.position.z = move_toward(camera.position.z, 2.5 + target_z, 0.5)

# === POWER METER ===

func _update_power_meter(delta: float) -> void:
	if not is_charging:
		if power_meter_visible:
			hud.set_power_charge(0.0)
			hud.show_power_meter(false)
			power_meter_visible = false
		return
	
	power_charge = clamp(power_charge + delta * 0.8, 0.0, 1.0)
	hud.set_power_charge(power_charge)
	hud.show_power_meter(true)
	power_meter_visible = true

func start_power_charge() -> void:
	if rally_active and ball.position.z < 0 and ball.is_in_play:
		is_charging = true
		power_charge = 0.0

func release_power_shot() -> void:
	if not is_charging:
		return
	is_charging = false
	hud.show_power_meter(false)
	power_meter_visible = false
	
	if power_charge > 0.1 and rally_active and ball.position.z < 0 and ball.is_in_play:
		var direction = Vector3(0, 0.1, -1.0).normalized()
		ball.hit(power_charge, direction, BallRef.ShotType.DRIVE)
		ball.last_hitter_id = 0
		last_player_shot_type = BallRef.ShotType.DRIVE
		EventBus.ball_hit.emit(0, BallRef.ShotType.DRIVE, power_charge)
		match_manager.record_hit()
		_animate_paddle_swing(player)

# === PADDLE SWING ===

func _animate_paddle_swing(character: Node3D) -> void:
	var paddle = character.get_node("Paddle") if character.has_node("Paddle") else null
	if not paddle:
		return
	paddle.rotation.x = -1.5  # Swing back
	paddle_swing_timer = PADDLE_SWING_DURATION

func _update_paddle_swing(delta: float) -> void:
	if paddle_swing_timer <= 0:
		return
	
	paddle_swing_timer -= delta
	var progress = paddle_swing_timer / PADDLE_SWING_DURATION
	
	# Animate paddles for all relevant characters
	var chars = [player, opponent]
	if is_doubles:
		chars = [player, player_partner, opponent, opponent_partner]
	
	for character in chars:
		var paddle = character.get_node("Paddle") if character.has_node("Paddle") else null
		if paddle:
			paddle.rotation.x = lerpf(-1.5, 0.0, 1.0 - progress)
	
	if paddle_swing_timer <= 0:
		paddle_swing_timer = 0.0
		for character in chars:
			var paddle = character.get_node("Paddle") if character.has_node("Paddle") else null
			if paddle:
				paddle.rotation.x = 0.0

func _update_screen_effects(_delta: float) -> void:
	pass  # GameFeel handles shake and flash in its own _process

func _update_characters_look_at_ball() -> void:
	if not ball:
		return
	
	var ball_pos = ball.global_position
	
	# All characters look toward the ball
	if player and player.has_method("look_at_ball"):
		player.look_at_ball(ball_pos)
	if opponent and opponent.has_method("look_at_ball"):
		opponent.look_at_ball(ball_pos)
	if is_doubles:
		if player_partner and player_partner.has_method("look_at_ball"):
			player_partner.look_at_ball(ball_pos)
		if opponent_partner and opponent_partner.has_method("look_at_ball"):
			opponent_partner.look_at_ball(ball_pos)

# === SERVE FLOW (Singles) ===

func _on_serve_ready(server_id: int, _side: int) -> void:
	is_player_serving = (server_id == 0)
	
	if is_player_serving:
		player_serve_ready = true
		hud.show_serve_indicator("Your serve — Swipe up to serve")
		ball.reset()
		ball.position = Vector3(0, 0.5, PLAYER_BASELINE + 0.05)
	else:
		hud.show_serve_indicator("Opponent serving...")
		_reset_for_ai_serve()

# === SERVE FLOW (Doubles) ===

func _on_doubles_serve_ready(server_team: int, server_pos: int, _side: int) -> void:
	is_player_serving = (server_team == 0)
	
	if is_player_serving:
		player_serve_ready = true
		var serve_x = PLAYER_LEFT if server_pos == 0 else PLAYER_RIGHT
		var player_name = "Your" if server_pos == 0 else "Partner's"
		hud.show_serve_indicator(player_name + " serve — Swipe up to serve")
		ball.reset()
		ball.position = Vector3(serve_x, 0.5, PLAYER_BASELINE + 0.05)
	else:
		hud.show_serve_indicator("Opponent team serving...")
		_reset_for_doubles_ai_serve(server_pos)

func _reset_for_ai_serve() -> void:
	ball.reset()
	ball.position = Vector3(0, 0.5, OPPONENT_BASELINE - 0.05)
	ball.is_in_play = true
	
	await get_tree().create_timer(0.8).timeout
	if not match_manager.match_complete:
		_ai_serve()

func _reset_for_doubles_ai_serve(server_pos: int) -> void:
	var serve_x = PLAYER_RIGHT if server_pos == 0 else PLAYER_LEFT
	ball.reset()
	ball.position = Vector3(serve_x, 0.5, OPPONENT_BASELINE - 0.05)
	ball.is_in_play = true
	
	await get_tree().create_timer(0.8).timeout
	if not doubles_manager.match_complete:
		_doubles_ai_serve(server_pos)

func _ai_serve() -> void:
	var target = Vector3(randf_range(-0.3, 0.3), 0, PLAYER_BASELINE + 0.3)
	ball.serve(ball.position, target, 0.6)
	ball.last_hitter_id = 1
	EventBus.ball_served.emit(ball.position, target)
	EventBus.ball_hit.emit(1, BallRef.ShotType.DRIVE, 0.6)
	
	rally_active = true
	game_state.transition_to(GameStateRef.State.PLAY)
	hud.show_serve_indicator("")
	hud.show_gesture_guide(true)

func _doubles_ai_serve(server_pos: int) -> void:
	# Server is opponent (id=1) or opponent partner (id=3)
	var hitter_id = 1 if server_pos == 0 else 3
	var target = Vector3(randf_range(-0.3, 0.3), 0, PLAYER_BASELINE + 0.3)
	
	ball.serve(ball.position, target, 0.6)
	ball.last_hitter_id = hitter_id
	EventBus.ball_served.emit(ball.position, target)
	EventBus.ball_hit.emit(hitter_id, BallRef.ShotType.DRIVE, 0.6)
	
	rally_active = true
	game_state.transition_to(GameStateRef.State.PLAY)
	hud.show_serve_indicator("")
	hud.show_gesture_guide(true)

# === PLAYER INPUT ===

func _on_swipe_detected(velocity: Vector2, _distance: float) -> void:
	# If charging, release power shot first
	if is_charging:
		release_power_shot()
		return
	
	if not game_state.can_serve() and not rally_active:
		return
	
	var dir_name = input_handler.get_swipe_direction_name(velocity)
	
	if game_state.can_serve() and is_player_serving:
		if is_doubles:
			_handle_doubles_player_serve(dir_name, velocity)
		else:
			_handle_player_serve(dir_name, velocity)
		return
	
	if rally_active and ball.position.z < 0 and ball.is_in_play:
		_handle_player_shot(dir_name, velocity)

func _handle_player_serve(swipe_dir: String, velocity: Vector2) -> void:
	if swipe_dir != "up":
		hud.show_serve_indicator("Swipe UP to serve!")
		return
	
	if not match_manager.validate_serve(swipe_dir, 0.5):
		hud.show_serve_indicator("Serve must be underhand!")
		return
	
	player_serve_ready = false
	game_state.transition_to(GameStateRef.State.SERVE_ACTIVE)
	
	var power = clampf(velocity.length() / 300.0, 0.3, 1.0)
	var target_x = 0.0
	if abs(velocity.x) > 30:
		target_x = sign(velocity.x) * 0.2
	
	var target = Vector3(target_x, 0, OPPONENT_BASELINE - 0.2)
	ball.position = Vector3(0, 0.5, PLAYER_BASELINE + 0.05)
	ball.serve(ball.position, target, power)
	ball.last_hitter_id = 0
	
	EventBus.ball_served.emit(ball.position, target)
	EventBus.ball_hit.emit(0, BallRef.ShotType.DRIVE, power)
	
	rally_active = true
	game_state.transition_to(GameStateRef.State.PLAY)
	hud.show_serve_indicator("")
	hud.show_gesture_guide(false)

func _handle_doubles_player_serve(swipe_dir: String, velocity: Vector2) -> void:
	if swipe_dir != "up":
		hud.show_serve_indicator("Swipe UP to serve!")
		return
	
	if not match_manager.validate_serve(swipe_dir, 0.5):
		hud.show_serve_indicator("Serve must be underhand!")
		return
	
	player_serve_ready = false
	game_state.transition_to(GameStateRef.State.SERVE_ACTIVE)
	
	var power = clampf(velocity.length() / 300.0, 0.3, 1.0)
	var target_x = 0.0
	if abs(velocity.x) > 30:
		target_x = sign(velocity.x) * 0.2
	
	# Serve from current server's position
	var serve_x = ball.position.x
	var target = Vector3(target_x, 0, OPPONENT_BASELINE - 0.2)
	ball.position = Vector3(serve_x, 0.5, PLAYER_BASELINE + 0.05)
	ball.serve(ball.position, target, power)
	ball.last_hitter_id = 0
	
	EventBus.ball_served.emit(ball.position, target)
	EventBus.ball_hit.emit(0, BallRef.ShotType.DRIVE, power)
	
	rally_active = true
	game_state.transition_to(GameStateRef.State.PLAY)
	hud.show_serve_indicator("")
	hud.show_gesture_guide(false)

func _handle_player_shot(swipe_dir: String, velocity: Vector2) -> void:
	var power = clampf(velocity.length() / 400.0, 0.3, 1.0)
	var shot_type: int
	var direction: Vector3
	
	match swipe_dir:
		"up":
			shot_type = BallRef.ShotType.LOB
			direction = Vector3(0, 0.7, -1.0).normalized()
		"down":
			shot_type = BallRef.ShotType.DINK
			direction = Vector3(0, 0.3, -0.8).normalized()
		"left":
			shot_type = BallRef.ShotType.DRIVE
			direction = Vector3(-0.5, 0.1, -0.9).normalized()
		"right":
			shot_type = BallRef.ShotType.DRIVE
			direction = Vector3(0.5, 0.1, -0.9).normalized()
		_:
			shot_type = BallRef.ShotType.DRIVE
			direction = Vector3(0, 0.2, -1.0).normalized()
	
	ball.hit(power, direction, shot_type)
	ball.last_hitter_id = 0
	last_player_shot_type = shot_type
	EventBus.ball_hit.emit(0, shot_type, power)
	if match_manager:
		match_manager.record_hit()

func _on_tap_detected(_position: Vector2) -> void:
	# If charging, release power shot
	if is_charging:
		release_power_shot()
		return
	
	# Tap = volley if ball on player side and in air
	if rally_active and ball.position.z < 0 and ball.position.y > 0.1 and ball.is_in_play:
		var power = 0.7
		var direction = Vector3(0, -0.1, -1.0).normalized()
		
		if match_manager.check_kitchen_violation(player.position, true):
			EventBus.kitchen_violation.emit(0)
			if is_doubles:
				doubles_manager.award_point_from_rally(0, "Kitchen violation")
			else:
				match_manager.award_point_from_rally(0, "Kitchen violation")
			return
		
		ball.hit(power, direction, BallRef.ShotType.VOLLEY)
		ball.last_hitter_id = 0
		last_player_shot_type = BallRef.ShotType.VOLLEY
		EventBus.ball_hit.emit(0, BallRef.ShotType.VOLLEY, power)
		match_manager.record_hit()

func _on_double_tap(_position: Vector2) -> void:
	# Double tap starts power charge
	start_power_charge()

func _on_drag(from: Vector2, to: Vector2) -> void:
	if rally_active and ball.position.z < 0 and ball.is_in_play:
		var drag_vector = to - from
		var power = clampf(drag_vector.length() / 500.0, 0.3, 0.9)
		var target_x = clampf((to.x - 540) / 540.0, -0.5, 0.5)
		var direction = Vector3(target_x, 0.3, -0.9).normalized()
		ball.hit(power, direction, BallRef.ShotType.DRIVE)
		ball.last_hitter_id = 0
		EventBus.ball_hit.emit(0, BallRef.ShotType.DRIVE, power)
		match_manager.record_hit()

# === AI SHOT ===

func _on_ai_shot_selected(shot_type: int, direction: Vector3, force: float) -> void:
	if not rally_active:
		return
	
	# Use the correct opponent character for kitchen check (doubles support)
	var hitter: Node3D = opponent
	if is_doubles and ball.last_hitter_id == 3:
		hitter = opponent_partner
	
	if match_manager.check_kitchen_violation(hitter.position, false):
		EventBus.kitchen_violation.emit(1)
		if is_doubles:
			doubles_manager.award_point_from_rally(1, "Opponent kitchen violation")
		else:
			match_manager.award_point_from_rally(0, "Opponent kitchen violation")
		return
	
	ball.hit(force, direction, shot_type)
	ball.last_hitter_id = 1
	EventBus.ball_hit.emit(1, shot_type, force)
	match_manager.record_hit()
	_animate_paddle_swing(opponent)

# === BALL EVENTS ===

func _on_ball_landed(position: Vector3, _side: int) -> void:
	if not rally_active:
		return
	
	var landed_on_player_side = position.z < 0
	if landed_on_player_side:
		if match_manager.must_ball_bounce():
			pass
	else:
		if match_manager.must_ball_bounce():
			pass

func _on_ball_hit_net() -> void:
	if rally_active:
		rally_active = false
		var loser = ball.last_hitter_id
		if is_doubles:
			# Determine which team lost based on hitter ID
			# 0=player, 1=opponent, 2=player_partner, 3=opponent_partner
			var loser_team = 1 if loser in [1, 3] else 0
			doubles_manager.award_point_from_rally(loser_team, "Net fault")
		else:
			match_manager.award_point_from_rally(loser, "Net fault")
		_reset_rally()

# === MATCH EVENTS (Singles) ===

func _on_point_awarded(scorer_id: int, reason: String) -> void:
	rally_active = false
	
	# Celebrate if the player or player's partner (in doubles) scored
	if scorer_id == 0:
		if player and player.has_method("celebrate"):
			player.celebrate()
	elif scorer_id == 2:
		if player_partner and player_partner.has_method("celebrate"):
			player_partner.celebrate()
	
	# Report to challenge manager
	_challenge_report_rally(scorer_id)
	
	hud.update_score(match_manager.player_scores[0], match_manager.player_scores[1])
	hud.show_message(str("Point! ", reason))
	
	await get_tree().create_timer(1.5).timeout
	
	if not match_manager.match_complete:
		_reset_rally()
		game_state.transition_to(GameStateRef.State.SERVE_WAIT)
		_on_serve_ready(scorer_id, 0)

func _on_match_over(winner_id: int, final_scores: Array) -> void:
	var player_won = winner_id == 0
	var msg = "You win!" if player_won else "Opponent wins!"
	
	# Grant progression rewards
	var perf_score = 1.0 if player_won else 0.3
	var rewards = PlayerData.grant_match_rewards(perf_score)
	if player_won:
		PlayerData.grant_match_win()
		# Report to challenge manager
		_challenge_report_result(true, final_scores)
	else:
		_challenge_report_result(false, final_scores)
	
	# Handle tournament match result
	if has_node("TournamentManager"):
		var tm = $TournamentManager
		if tm.tournament_active:
			if player_won:
				tm.record_win()
				msg = "🏆 " + msg + " Advancing to next round!"
				await get_tree().create_timer(4.0).timeout
				_show_menu()
				return
			else:
				tm.record_loss()
				msg = "❌ " + msg + " Tournament over!"
	
	hud.show_message(str("Game Over! ", msg))
	hud.update_score(final_scores[0], final_scores[1])
	hud.show_rewards(rewards)
	game_state.transition_to(GameStateRef.State.GAME_OVER)
	
	# Show a "Play Again" option after 3 seconds
	await get_tree().create_timer(3.0).timeout
	_show_menu()

# === MATCH EVENTS (Doubles) ===

func _on_doubles_point_awarded(team_id: int, reason: String) -> void:
	rally_active = false
	
	# Celebrate if player team (team 0) scored
	if team_id == 0:
		if player and player.has_method("celebrate"):
			player.celebrate()
		if player_partner and player_partner.has_method("celebrate"):
			player_partner.celebrate()
	
	hud.update_score(doubles_manager.team_scores[0], doubles_manager.team_scores[1])
	hud.show_message(str("Point! Team ", team_id + 1, " — ", reason))
	
	await get_tree().create_timer(1.5).timeout
	
	if not doubles_manager.match_complete:
		_reset_rally()
		game_state.transition_to(GameStateRef.State.SERVE_WAIT)
		var current_server = doubles_manager.get_current_server()
		_on_doubles_serve_ready(current_server[0], current_server[1], 0)

func _on_doubles_match_over(winner_team: int, scores: Array) -> void:
	var player_team_won = winner_team == 0
	var msg = "Your team wins!" if player_team_won else "Opponent team wins!"
	
	# Grant progression rewards
	var perf_score = 1.0 if player_team_won else 0.3
	var rewards = PlayerData.grant_match_rewards(perf_score)
	if player_team_won:
		PlayerData.grant_match_win()
	
	hud.show_message(str("Game Over! ", msg))
	hud.update_score(scores[0], scores[1])
	hud.show_rewards(rewards)
	game_state.transition_to(GameStateRef.State.GAME_OVER)
	
	# Show a "Play Again" option after 3 seconds
	await get_tree().create_timer(3.0).timeout
	_show_menu()

func _challenge_report_result(player_won: bool, _final_scores: Array) -> void:
	if not has_node("ChallengeManager"):
		return
	# Match tracking happens via EventBus.match_ended in ChallengeManager
	pass

func _challenge_report_rally(scorer_id: int) -> void:
	if not has_node("ChallengeManager"):
		return
	var cm = $ChallengeManager
	
	if scorer_id == 0:
		# Player won the rally — report the shot type
		var shot_name: String = ""
		match last_player_shot_type:
			BallRef.ShotType.DINK:
				shot_name = "dink"
			BallRef.ShotType.LOB:
				shot_name = "lob"
			BallRef.ShotType.VOLLEY:
				shot_name = "volley"
			BallRef.ShotType.DRIVE:
				shot_name = "drive"
			_:
				shot_name = ""
		
		if shot_name != "" and cm.has_method("report_rally_won"):
			cm.report_rally_won(shot_name)
		
		# Report rally length
		if cm.has_method("report_rally_length"):
			cm.report_rally_length(match_manager.hits_in_rally if match_manager else 0)

func _challenge_report_ace() -> void:
	if not has_node("ChallengeManager"):
		return
	var cm = $ChallengeManager
	if cm.has_method("report_ace"):
		cm.report_ace()

func _reset_rally() -> void:
	rally_active = false
	match_manager.reset_rally()
	ball.reset()
	ball.position = Vector3(0, 0.05, 0)

# === PUBLIC API ===

func start_quick_match() -> void:
	_hide_doubles_characters()
	_reset_rally()
	match_manager.start_match(MatchManagerRef.MatchType.QUICK)
	game_state.transition_to(GameStateRef.State.SERVE_WAIT)
	ai_manager.set_difficulty(AIManagerRef.Difficulty.CASUAL)
	player.position = Vector3(0, 0, PLAYER_BASELINE)
	opponent.position = Vector3(0, 0, OPPONENT_BASELINE)
	hud.update_score(0, 0)
	hud.show_serve_indicator("Starting match...")
	_on_serve_ready(0, 0)

func start_doubles_match() -> void:
	_show_doubles_characters()
	_reset_rally()
	doubles_manager.start_doubles_match()
	game_state.transition_to(GameStateRef.State.SERVE_WAIT)
	
	# Position all 4 players
	player.position = Vector3(PLAYER_LEFT, 0, PLAYER_BASELINE)
	player_partner.position = Vector3(PLAYER_RIGHT, 0, PLAYER_BASELINE)
	opponent.position = Vector3(PLAYER_RIGHT, 0, OPPONENT_BASELINE)
	opponent_partner.position = Vector3(PLAYER_LEFT, 0, OPPONENT_BASELINE)
	
	# Set AI difficulty
	ai_manager.set_difficulty(AIManagerRef.Difficulty.CASUAL)
	
	hud.update_score(0, 0)
	hud.show_serve_indicator("Starting doubles match...")
	_on_doubles_serve_ready(0, 0, 0)
