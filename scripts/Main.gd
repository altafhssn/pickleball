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
const PLAYER_LEFT: float = -0.75
const PLAYER_RIGHT: float = 0.75
# Real baselines — players stand just inside the back baseline (z = ±2.25).
const PLAYER_BASELINE: float = -1.95
const OPPONENT_BASELINE: float = 1.95

# On-screen touch controls — all built programmatically in _ready so they
# can't be foiled by .tscn loading issues.
var touch_layer: CanvasLayer = null
var touch_btn_serve: Button = null
var touch_btn_lob: Button = null
var touch_btn_drive: Button = null
var touch_btn_dink: Button = null
var touch_btn_up: Button = null
var touch_btn_down: Button = null
var touch_btn_left: Button = null
var touch_btn_right: Button = null
var touch_move_dir: Vector2 = Vector2.ZERO
# Wii-Sports-style one-button gameplay state. Two trackers because serve
# and rally share the Space key and we want both to edge-detect cleanly.
var was_serve_space_pressed: bool = false
var was_rally_space_pressed: bool = false
var was_lob_key_pressed: bool = false
var was_dink_key_pressed: bool = false
# === COMMIT-AND-CONTACT SWING SYSTEM ===
# The player commits to a shot type ANY time while the ball approaches.
# The character auto-runs to the intercept; when the ball gets close the
# swing animation starts, and CONTACT_DELAY later the bat "meets" the ball
# and it launches toward the aim. Earlier commit = tighter placement.
var pending_shot: int = -1          # committed ShotType, -1 = none
var commit_time_ms: int = 0         # when the player committed (msec ticks)
var swing_contact_timer: float = 0.0  # counts down from swing start to contact
var swing_in_progress: bool = false
var player_swung_this_approach: bool = false  # one swing per incoming ball

const SWING_TRIGGER_RANGE: float = 1.5  # start the swing when ball is this close
const CONTACT_DELAY: float = 0.32       # swing start → bat-meets-ball moment
const CONTACT_REACH: float = 2.2        # max distance at contact for a connect

# AI mirror of the same system: windup anim first, launch at contact.
var ai_ready_to_swing: bool = false
var ai_swing_timer: float = 0.0
var ai_contact_timer: float = 0.0
var ai_winding_up: bool = false
# Flag set when AI just swung; cleared when the ball crosses back to the
# player's side. Prevents the AI from re-hitting its own outgoing ball.
var ai_just_swung: bool = false
const AI_REACTION_TIME: float = 0.25
# Tighter than the player's reach — the AI has to actually be near the ball
# to connect, so well-placed shots into the corners win the rally outright.
const AI_HIT_RANGE: float = 1.20
const AI_CONTACT_REACH: float = 1.70

# Camera base (Main owns this; GameFeel adds a shake offset on top each frame).
var camera_base_pos: Vector3 = Vector3.ZERO

# Landing marker — a flat ring on the court showing where the ball will bounce.
var landing_marker: MeshInstance3D = null
# Swing-zone ring around the player character: colour-coded by how perfect
# a swing would be right now.
var swing_zone_ring: MeshInstance3D = null
const PERFECT_DIST: float = 0.7
const GOOD_DIST: float = 1.3

# Rally end-condition tracking
var bounces_since_last_hit: int = 0
# Used to enforce the two-bounce rule (until 2 total bounces, every hit must
# follow a bounce) and to flag serve faults on the first bounce.
var total_bounces_in_rally: int = 0
# Detect a ball that's come to rest in the middle of a rally (rare with
# proper physics, but a real bug-prevention belt-and-suspenders).
var ball_rest_timer: float = 0.0
const BALL_REST_TIMEOUT: float = 0.8
# Court extends x ∈ [-1.5, 1.5] (sidelines), z ∈ [-2.25, 2.25] (baselines).
# Allow a small "in" margin so close shots don't get incorrectly called out.
const OUT_X_LIMIT: float = 1.70
const OUT_Z_LIMIT: float = 2.55
const FLOOR_Y_LIMIT: float = -0.3
const PLAYER_MOVE_SPEED: float = 3.8
const PLAYER_ASSIST_SPEED: float = 1.25
const PLAYER_RETURN_SPEED: float = 1.6
const OPPONENT_MOVE_SPEED: float = 2.35
const COURT_X_LIMIT: float = 1.35
const PLAYER_MIN_Z: float = -2.12
const PLAYER_MAX_Z: float = -0.58
const OPPONENT_MIN_Z: float = 0.72
const OPPONENT_MAX_Z: float = 2.12

func _ready():
	EventBus.swipe_detected.connect(_on_swipe_detected)
	EventBus.tap_detected.connect(_on_tap_detected)
	EventBus.double_tap_detected.connect(_on_double_tap)
	EventBus.drag_detected.connect(_on_drag)
	# AIManager (decision-tree based) is disabled for the Wii-Sports rework.
	# AI swing logic now lives inline in Main._process_ai_swing.
	# ai_manager.ai_shot_selected.connect(_on_ai_shot_selected)
	match_manager.point_awarded.connect(_on_point_awarded)
	match_manager.side_out.connect(_on_side_out)
	match_manager.serve_ready.connect(_on_serve_ready)
	match_manager.match_over.connect(_on_match_over)
	doubles_manager.point_awarded.connect(_on_doubles_point_awarded)
	doubles_manager.serve_ready.connect(_on_doubles_serve_ready)
	doubles_manager.match_over.connect(_on_doubles_match_over)
	
	ball.ball_landed.connect(_on_ball_landed)
	ball.ball_hit_net.connect(_on_ball_hit_net)
	EventBus.ball_hit.connect(_on_any_ball_hit_for_rally_tracking)
	
	# Place the camera behind the player (player is at -z) so the human
	# sees their own (blue) character in the foreground. Closer position
	# and narrower FOV make the court fill more of the screen.
	# Broadcast-style framing: high and pulled back, narrow FOV so the court
	# reads flat and produced rather than fisheye, both characters in frame.
	camera.position = Vector3(0, 3.4, -5.0)
	camera.look_at(Vector3(0, 0.2, 0.5), Vector3.UP)
	camera.fov = 50

	# Initialize game feel and capture the (new) camera position as our base.
	game_feel.setup(camera, hud)
	camera_base_pos = camera.position

	# Team coloring so the player can tell themselves apart from the AI.
	_apply_team_colors()

	# Spawn the landing marker (hidden until first serve).
	_spawn_landing_marker()
	_spawn_swing_zone_ring()

	# Spawn the on-screen touch controls overlay.
	_spawn_touch_controls()
	
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
	# (start_match already emitted serve_ready — no direct call, or the
	# serve gets scheduled twice.)

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

const PLAYER_TEAM_COLOR := Color(0.25, 0.55, 1.0)   # Blue — that's you.
const OPPONENT_TEAM_COLOR := Color(1.0, 0.45, 0.15)  # Orange — the AI.

func _process_serve_input(_delta: float) -> void:
	# Wii-Sports serve: one tap of Space serves the ball. No aim, no charge.
	var space_now: bool = Input.is_key_pressed(KEY_SPACE)
	if game_state.can_serve() and is_player_serving and player_serve_ready:
		if space_now and not was_serve_space_pressed:
			_launch_player_serve(0.65)
	was_serve_space_pressed = space_now

func _process_rally_input() -> void:
	# Shot buttons commit intent, while movement stays independent.
	# Space/tap = drive, W/double-tap = lob, S = dink.
	var space_now: bool = Input.is_key_pressed(KEY_SPACE)
	var lob_now: bool = Input.is_key_pressed(KEY_W)
	var dink_now: bool = Input.is_key_pressed(KEY_S)
	if not game_state.can_serve():
		if space_now and not was_rally_space_pressed:
			_commit_shot(BallRef.ShotType.DRIVE)
		if lob_now and not was_lob_key_pressed:
			_commit_shot(BallRef.ShotType.LOB)
		if dink_now and not was_dink_key_pressed:
			_commit_shot(BallRef.ShotType.DINK)
	was_rally_space_pressed = space_now
	was_lob_key_pressed = lob_now
	was_dink_key_pressed = dink_now

# === COMMIT-AND-CONTACT (player) ===

# Record the player's shot choice. The actual contact happens later, timed
# to the swing animation, in _process_commit_swing. Pressing again before
# the swing starts switches the pending shot (e.g. DRIVE → LOB).
func _commit_shot(shot_type: int) -> void:
	if not (rally_active and ball.is_in_play):
		return
	if player_swung_this_approach or swing_in_progress:
		return
	if ball.last_hitter_id == 0:
		return  # we hit it last; it's the AI's ball
	var first_commit: bool = pending_shot == -1
	pending_shot = shot_type
	if first_commit:
		commit_time_ms = Time.get_ticks_msec()
	var shot_name: String = "DRIVE"
	match shot_type:
		BallRef.ShotType.LOB: shot_name = "LOB"
		BallRef.ShotType.DINK: shot_name = "DINK"
	hud.show_message(shot_name + " locked ✓", Color(0.75, 0.9, 1.0))

# Runs every frame: starts the swing when the inbound ball gets close, then
# launches the ball at the animation's contact moment.
func _process_commit_swing(delta: float) -> void:
	# Reset for the next approach once the ball is heading away again.
	if not (rally_active and ball.is_in_play) or ball.last_hitter_id == 0:
		pending_shot = -1
		swing_in_progress = false
		swing_contact_timer = 0.0
		player_swung_this_approach = false
		return

	# Mid-swing: count down to the bat-meets-ball moment. The two-bounce
	# rule gates only the CONTACT — if the required bounce hasn't landed
	# yet, the contact holds until it does (mirrors the AI's swing).
	if swing_in_progress:
		swing_contact_timer -= delta
		if swing_contact_timer <= 0.0:
			if total_bounces_in_rally < 2 and bounces_since_last_hit < 1:
				swing_contact_timer = 0.05
				return
			swing_in_progress = false
			_launch_committed_shot()
		return

	if pending_shot == -1 or player_swung_this_approach:
		return
	# Trigger conditions: ball solidly on our side, within swing-trigger
	# range of the character (windup may start before the bounce).
	if ball.position.z > -0.1:
		return
	var dist: float = Vector2(player.position.x - ball.position.x, player.position.z - ball.position.z).length()
	if dist <= SWING_TRIGGER_RANGE:
		swing_in_progress = true
		player_swung_this_approach = true
		swing_contact_timer = CONTACT_DELAY
		_animate_paddle_swing(player)

func _launch_committed_shot() -> void:
	var shot_type: int = pending_shot
	pending_shot = -1
	if not (rally_active and ball.is_in_play):
		return
	# Generous reach at contact — the trigger already required proximity.
	var dist: float = Vector2(player.position.x - ball.position.x, player.position.z - ball.position.z).length()
	if dist > CONTACT_REACH or ball.position.z > -0.05:
		hud.show_message("Missed!", Color(1, 0.4, 0.4))
		return
	# Quality is mostly body position at contact, with early intent as a
	# small stabilizer. This makes footwork matter and cuts down on random
	# haphazard placement.
	var early_sec: float = float(Time.get_ticks_msec() - commit_time_ms) / 1000.0
	var spread: float
	if dist <= PERFECT_DIST:
		hud.show_message("CLEAN!", Color(0.2, 1.0, 0.4))
		spread = 0.08
	elif dist <= GOOD_DIST:
		hud.show_message("GOOD!", Color(1.0, 0.95, 0.2))
		spread = 0.18
	else:
		hud.show_message("REACH", Color(1.0, 0.6, 0.2))
		spread = 0.34
	if early_sec >= 0.55:
		spread *= 0.75

	var move_input: Vector2 = _get_player_move_input()
	var aim_x: float = move_input.x * 0.35
	var away_x: float = clampf(-opponent.position.x * 0.65, -0.85, 0.85)
	var target_x: float = clampf(away_x + aim_x + randf_range(-spread, spread), -1.15, 1.15)
	var target_z: float
	var flight_time: float
	match shot_type:
		BallRef.ShotType.LOB:
			target_z = OPPONENT_BASELINE - randf_range(0.12, 0.38)
			flight_time = 1.10
		BallRef.ShotType.DINK:
			target_z = randf_range(0.38, 0.70)
			flight_time = 0.90
		_:
			target_z = OPPONENT_BASELINE - randf_range(0.48, 0.82)
			flight_time = 0.70
	ball.launch_at_target(ball.position, Vector3(target_x, 0, target_z), flight_time)
	ball.last_hitter_id = 0
	last_player_shot_type = shot_type
	var emit_power: float = 1.0 - clampf(spread / 0.45, 0.0, 1.0) * 0.5
	EventBus.ball_hit.emit(0, shot_type, emit_power)
	match_manager.record_hit()

# === COMMIT-AND-CONTACT (AI mirror) ===
# Two-phase like the player: reaction → windup (swing anim plays) →
# contact (ball launches), so the bat visually meets the ball.
func _process_ai_swing(delta: float) -> void:
	# The ball is "the AI's problem" whenever the player hit it last —
	# reaction starts at the player's hit, not at the net crossing. (The
	# playtest showed net-crossing-gated reactions finish ~0.1s after the
	# second bounce, every time: the AI could never legally swing.)
	if not (rally_active and ball.is_in_play) or ball.last_hitter_id != 0:
		ai_ready_to_swing = false
		ai_swing_timer = 0.0
		ai_winding_up = false
		ai_contact_timer = 0.0
		ai_just_swung = false
		return
	# Don't re-hit a ball we just sent away.
	if ai_just_swung:
		return

	# Windup phase: swing anim already playing; launch at the contact moment.
	# The two-bounce rule gates only the CONTACT, not the windup — the AI
	# reads the ball in flight like a real player and swings through right
	# after the bounce. (Gating the whole pipeline on the bounce left only
	# 0.4s to react+windup; every rally died at 1 hit.)
	if ai_winding_up:
		ai_contact_timer -= delta
		if ai_contact_timer <= 0.0:
			if total_bounces_in_rally < 2 and bounces_since_last_hit < 1:
				ai_contact_timer = 0.05  # hold the contact until the bounce lands
				return
			ai_winding_up = false
			var dist_now: float = Vector2(opponent.position.x - ball.position.x, opponent.position.z - ball.position.z).length()
			if dist_now <= AI_CONTACT_REACH:
				ai_just_swung = true
				_ai_launch()
		return

	# Reaction phase: ball entered range → wait the reaction time, then
	# start the windup early enough that contact lands when the ball is in.
	if ai_ready_to_swing:
		ai_swing_timer -= delta
		if ai_swing_timer <= 0.0:
			ai_ready_to_swing = false
			ai_winding_up = true
			ai_contact_timer = CONTACT_DELAY
			_animate_paddle_swing(opponent)
		return
	# Arm immediately at the player's hit — reaction + windup overlap the
	# ball's whole flight; the contact gate above waits for the bounce.
	ai_ready_to_swing = true
	ai_swing_timer = _get_inline_ai_reaction_time()

func _ai_launch() -> void:
	if not rally_active or not ball.is_in_play:
		return
	var spread: float = _get_inline_ai_spread()
	var target_x: float = clampf(player.position.x + randf_range(-spread, spread), -1.05, 1.05)
	var target_z: float = clampf(player.position.z + randf_range(0.35, 0.82), PLAYER_MIN_Z + 0.20, PLAYER_MAX_Z - 0.05)
	var target := Vector3(target_x, 0, target_z)
	ball.launch_at_target(ball.position, target, 0.90)
	ball.last_hitter_id = 1
	EventBus.ball_hit.emit(1, BallRef.ShotType.DRIVE, 0.75)
	match_manager.record_hit()

func _get_inline_ai_reaction_time() -> float:
	var difficulty: int = int(ai_manager.get("difficulty"))
	match difficulty:
		AIManagerRef.Difficulty.BEGINNER:
			return 0.52
		AIManagerRef.Difficulty.CASUAL:
			return 0.42
		AIManagerRef.Difficulty.PRO:
			return 0.32
		AIManagerRef.Difficulty.ELITE:
			return 0.25
		AIManagerRef.Difficulty.CHAMPION:
			return 0.20
		_:
			return AI_REACTION_TIME

func _get_inline_ai_spread() -> float:
	var difficulty: int = int(ai_manager.get("difficulty"))
	match difficulty:
		AIManagerRef.Difficulty.BEGINNER:
			return 0.42
		AIManagerRef.Difficulty.CASUAL:
			return 0.32
		AIManagerRef.Difficulty.PRO:
			return 0.24
		AIManagerRef.Difficulty.ELITE:
			return 0.18
		AIManagerRef.Difficulty.CHAMPION:
			return 0.13
		_:
			return 0.32

func _launch_player_serve(power: float) -> void:
	if not player_serve_ready:
		return
	player_serve_ready = false
	game_state.transition_to(GameStateRef.State.SERVE_ACTIVE)

	# Wii-Sports serve: deep target past the opponent's kitchen with a
	# small random nudge, giving them a real return window.
	var target := Vector3(randf_range(-0.5, 0.5), 0, 1.3)
	ball.serve(ball.position, target, power)
	ball.last_hitter_id = 0
	_animate_paddle_swing(player)

	EventBus.ball_served.emit(ball.position, target)
	EventBus.ball_hit.emit(0, BallRef.ShotType.DRIVE, power)

	rally_active = true
	game_state.transition_to(GameStateRef.State.PLAY)
	hud.show_serve_indicator("")
	hud.show_gesture_guide(true)
	_set_touch_serve_button_visible(false)
	_set_touch_shot_buttons_visible(true)

func _spawn_touch_controls() -> void:
	# Built programmatically with PERCENTAGE-BASED anchors so the buttons
	# land in the corners regardless of viewport aspect ratio.
	touch_layer = CanvasLayer.new()
	touch_layer.name = "TouchControls"
	touch_layer.layer = 10
	add_child(touch_layer)

	# SERVE: big button center-right, ~25% wide, ~12% tall.
	touch_btn_serve = _make_percent_button("SERVE", 0.70, 0.72, 0.95, 0.88, 56, Color(1.0, 0.55, 0.1, 0.95))
	touch_btn_serve.pressed.connect(_on_touch_serve)
	touch_btn_serve.visible = false

	# Shot buttons: stacked vertically on the right edge.
	touch_btn_lob = _make_percent_button("LOB", 0.80, 0.58, 0.97, 0.70, 40, Color(0.1, 0.1, 0.15, 0.9))
	touch_btn_lob.pressed.connect(_on_touch_lob)
	touch_btn_drive = _make_percent_button("DRIVE", 0.80, 0.72, 0.97, 0.84, 40, Color(0.1, 0.1, 0.15, 0.9))
	touch_btn_drive.pressed.connect(_on_touch_drive)
	touch_btn_dink = _make_percent_button("DINK", 0.80, 0.86, 0.97, 0.98, 40, Color(0.1, 0.1, 0.15, 0.9))
	touch_btn_dink.pressed.connect(_on_touch_dink)
	_set_touch_shot_buttons_visible(false)

	# D-pad on the bottom-left in a + cross layout.
	touch_btn_up    = _make_percent_button("▲", 0.08, 0.58, 0.16, 0.68, 44, Color(0.1, 0.1, 0.15, 0.9))
	touch_btn_left  = _make_percent_button("◀", 0.02, 0.70, 0.10, 0.80, 44, Color(0.1, 0.1, 0.15, 0.9))
	touch_btn_right = _make_percent_button("▶", 0.14, 0.70, 0.22, 0.80, 44, Color(0.1, 0.1, 0.15, 0.9))
	touch_btn_down  = _make_percent_button("▼", 0.08, 0.82, 0.16, 0.92, 44, Color(0.1, 0.1, 0.15, 0.9))
	touch_btn_up.button_down.connect(_on_touch_move.bind(Vector2(0, 1)))
	touch_btn_up.button_up.connect(_on_touch_move.bind(Vector2.ZERO))
	touch_btn_down.button_down.connect(_on_touch_move.bind(Vector2(0, -1)))
	touch_btn_down.button_up.connect(_on_touch_move.bind(Vector2.ZERO))
	touch_btn_left.button_down.connect(_on_touch_move.bind(Vector2(-1, 0)))
	touch_btn_left.button_up.connect(_on_touch_move.bind(Vector2.ZERO))
	touch_btn_right.button_down.connect(_on_touch_move.bind(Vector2(1, 0)))
	touch_btn_right.button_up.connect(_on_touch_move.bind(Vector2.ZERO))

# Place a button using percentage-of-viewport anchors.
# x/y ranges should be in [0, 1]. Resulting rect fits regardless of aspect.
func _make_percent_button(text: String, ax: float, ay: float, bx: float, by: float, font_size: int, bg: Color) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.anchor_left = ax
	b.anchor_top = ay
	b.anchor_right = bx
	b.anchor_bottom = by
	b.offset_left = 0
	b.offset_top = 0
	b.offset_right = 0
	b.offset_bottom = 0
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_apply_touch_button_style(b, bg)
	touch_layer.add_child(b)
	return b

func _apply_touch_button_style(b: Button, bg: Color) -> void:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(1, 1, 1, 0.85)
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.corner_radius_top_left = 16
	sb.corner_radius_top_right = 16
	sb.corner_radius_bottom_left = 16
	sb.corner_radius_bottom_right = 16
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("focus", sb)

func _set_touch_serve_button_visible(yes: bool) -> void:
	if touch_btn_serve:
		touch_btn_serve.visible = yes

func _set_touch_shot_buttons_visible(yes: bool) -> void:
	if touch_btn_lob:
		touch_btn_lob.visible = yes
	if touch_btn_drive:
		touch_btn_drive.visible = yes
	if touch_btn_dink:
		touch_btn_dink.visible = yes

func _on_touch_serve() -> void:
	if game_state.can_serve() and is_player_serving and player_serve_ready:
		_launch_player_serve(0.65)

func _on_touch_lob() -> void:
	_touch_hit(BallRef.ShotType.LOB)

func _on_touch_drive() -> void:
	_touch_hit(BallRef.ShotType.DRIVE)

func _on_touch_dink() -> void:
	_touch_hit(BallRef.ShotType.DINK)

func _touch_hit(shot_type: int) -> void:
	# Touch buttons commit a shot; contact is timed to the swing animation.
	_commit_shot(shot_type)

func _on_touch_move(direction: Vector2) -> void:
	touch_move_dir = direction

func _spawn_swing_zone_ring() -> void:
	swing_zone_ring = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.11
	torus.outer_radius = 0.14
	torus.rings = 24
	torus.ring_segments = 8
	swing_zone_ring.mesh = torus
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 1.0, 0.2, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 1.0, 0.2)
	mat.emission_energy_multiplier = 0.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	swing_zone_ring.material_override = mat
	swing_zone_ring.visible = false
	add_child(swing_zone_ring)

func _update_swing_zone_ring() -> void:
	if swing_zone_ring == null:
		return
	# Commit-state indicator: show while the ball is ours to play.
	#   pulsing white — ball inbound, no shot locked yet (press something!)
	#   green        — shot locked, character will swing automatically
	if not (rally_active and ball.is_in_play) or ball.last_hitter_id == 0:
		swing_zone_ring.visible = false
		return
	swing_zone_ring.visible = true
	swing_zone_ring.global_position = Vector3(player.position.x, 0.015, player.position.z)
	var color: Color
	if pending_shot == -1 and not player_swung_this_approach:
		var pulse: float = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 180.0)
		color = Color(1.0, 1.0, 1.0, pulse)
	else:
		color = Color(0.15, 1.0, 0.35, 1.0)
	var mat: StandardMaterial3D = swing_zone_ring.material_override as StandardMaterial3D
	mat.albedo_color = color
	mat.emission = Color(color.r, color.g, color.b)

func _spawn_landing_marker() -> void:
	landing_marker = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.06
	torus.outer_radius = 0.10
	torus.rings = 24
	torus.ring_segments = 8
	landing_marker.mesh = torus
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.1, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.1)
	mat.emission_energy_multiplier = 0.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	landing_marker.material_override = mat
	landing_marker.visible = false
	add_child(landing_marker)

func _update_landing_marker() -> void:
	if landing_marker == null:
		return
	if not ball.is_in_play or ball.linear_velocity.length() < 0.5:
		landing_marker.visible = false
		return
	var landing: Vector3 = _predict_ball_landing()
	# Only show if landing is plausibly on the court.
	if absf(landing.x) > 1.3 or absf(landing.z) > 1.8:
		landing_marker.visible = false
		return
	landing_marker.visible = true
	landing_marker.global_position = Vector3(landing.x, 0.012, landing.z)

func _announce_shot(shot_type: int) -> void:
	var name: String = ""
	match shot_type:
		BallRef.ShotType.DINK: name = "Dink!"
		BallRef.ShotType.DRIVE: name = "Drive!"
		BallRef.ShotType.LOB: name = "Lob!"
		BallRef.ShotType.VOLLEY: name = "Volley!"
		BallRef.ShotType.ERNE: name = "Erne!"
		BallRef.ShotType.ATP: name = "ATP!"
	if name != "":
		hud.show_message(name)

func _apply_team_colors() -> void:
	_tint_character(player, PLAYER_TEAM_COLOR)
	_tint_character(player_partner, PLAYER_TEAM_COLOR)
	_tint_character(opponent, OPPONENT_TEAM_COLOR)
	_tint_character(opponent_partner, OPPONENT_TEAM_COLOR)

func _tint_character(character: Node3D, color: Color) -> void:
	if character == null:
		return
	# Paint the placeholder capsule if it's still visible (pre-rig fallback).
	var body: MeshInstance3D = character.get_node_or_null("Body") as MeshInstance3D
	if body != null and body.visible:
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.5
		body.material_override = mat
	# Rigged model: soft pastel team tint over the whole (untextured white)
	# body. Featureless white mannequins are unreadable — you can't tell
	# front from back or whose side anyone is on.
	var visual: Node = character.get_node_or_null("Visual")
	if visual != null:
		var pastel: Color = color.lerp(Color.WHITE, 0.55)
		var rig_mat: StandardMaterial3D = StandardMaterial3D.new()
		rig_mat.albedo_color = pastel
		rig_mat.roughness = 0.7
		for mesh_node: Node in visual.find_children("*", "MeshInstance3D", true, false):
			(mesh_node as MeshInstance3D).material_override = rig_mat
	# Team ring on the floor under the character — works for both the rigged
	# model (which we don't want to paint blue/orange) and the placeholder.
	if character.get_node_or_null("TeamRing") != null:
		return
	var ring: MeshInstance3D = MeshInstance3D.new()
	ring.name = "TeamRing"
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.16
	torus.outer_radius = 0.20
	torus.rings = 24
	torus.ring_segments = 8
	ring.mesh = torus
	var ring_mat: StandardMaterial3D = StandardMaterial3D.new()
	ring_mat.albedo_color = Color(color.r, color.g, color.b, 0.85)
	ring_mat.emission_enabled = true
	ring_mat.emission = color
	ring_mat.emission_energy_multiplier = 0.5
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = ring_mat
	ring.position = Vector3(0, 0.02, 0)
	character.add_child(ring)

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
		ai_manager.update_ball_velocity(ball.linear_velocity)
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
	_update_camera()
	_check_ball_out_of_bounds()
	_update_turn_indicator()
	_update_landing_marker()
	_update_swing_zone_ring()
	_process_serve_input(delta)
	_process_rally_input()
	_process_commit_swing(delta)
	_process_ai_swing(delta)
	_check_ball_stuck(delta)

	# Make characters look toward the ball each frame
	_update_characters_look_at_ball()

func _update_player_auto_move(delta: float) -> void:
	# Player movement should feel owned by the player. We only add a small
	# assist when they are idle or the ball is close enough that footwork
	# should naturally shade toward contact.
	if not ball.is_in_play:
		return

	var move_input: Vector2 = _get_player_move_input()
	if move_input.length_squared() > 1.0:
		move_input = move_input.normalized()

	if move_input.length_squared() > 0.01:
		player.position.x += move_input.x * PLAYER_MOVE_SPEED * delta
		player.position.z += move_input.y * PLAYER_MOVE_SPEED * delta
	else:
		var idle_target: Vector3 = _get_player_assist_target()
		var assist_speed: float = PLAYER_ASSIST_SPEED
		if ball.position.z >= 0.0:
			assist_speed = PLAYER_RETURN_SPEED
		_move_player_toward(idle_target, assist_speed * delta)

	player.position.x = clampf(player.position.x, -COURT_X_LIMIT, COURT_X_LIMIT)
	player.position.z = clampf(player.position.z, PLAYER_MIN_Z, PLAYER_MAX_Z)

	if not is_doubles:
		var opp_target: Vector3 = _get_opponent_assist_target()
		opponent.position.x = move_toward(opponent.position.x, opp_target.x, OPPONENT_MOVE_SPEED * delta)
		opponent.position.z = move_toward(opponent.position.z, opp_target.z, OPPONENT_MOVE_SPEED * delta)
		opponent.position.x = clampf(opponent.position.x, -COURT_X_LIMIT, COURT_X_LIMIT)
		opponent.position.z = clampf(opponent.position.z, OPPONENT_MIN_Z, OPPONENT_MAX_Z)

func _get_player_move_input() -> Vector2:
	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input.x += 1.0
	if Input.is_key_pressed(KEY_UP):
		input.y += 1.0
	if Input.is_key_pressed(KEY_DOWN):
		input.y -= 1.0
	input += touch_move_dir
	return input

func _move_player_toward(target: Vector3, amount: float) -> void:
	player.position.x = move_toward(player.position.x, target.x, amount)
	player.position.z = move_toward(player.position.z, target.z, amount)

func _get_player_assist_target() -> Vector3:
	if ball.position.z < 0.0:
		var landing: Vector3 = _predict_ball_landing()
		var target_x: float = landing.x if landing.z < -0.05 else ball.position.x
		var target_z: float = landing.z if landing.z < -0.05 else ball.position.z
		return Vector3(
			clampf(target_x, -COURT_X_LIMIT, COURT_X_LIMIT),
			0.0,
			clampf(target_z + 0.12, PLAYER_MIN_Z, PLAYER_MAX_Z)
		)
	return Vector3(
		clampf(ball.position.x * 0.22, -0.45, 0.45),
		0.0,
		PLAYER_BASELINE
	)

func _get_opponent_assist_target() -> Vector3:
	if ball.position.z > 0.0:
		var landing: Vector3 = _predict_ball_landing()
		var target_x: float = landing.x if landing.z > 0.05 else ball.position.x
		var target_z: float = landing.z if landing.z > 0.05 else ball.position.z
		return Vector3(
			clampf(target_x, -COURT_X_LIMIT, COURT_X_LIMIT),
			0.0,
			clampf(target_z - 0.12, OPPONENT_MIN_Z, OPPONENT_MAX_Z)
		)
	return Vector3(
		clampf(ball.position.x * 0.20, -0.45, 0.45),
		0.0,
		OPPONENT_BASELINE
	)

# Ballistic projection ignoring drag — close enough for AI positioning.
# Solves y(t) = pos.y + vel.y*t - 0.5*g*t² = 0 for t > 0.
func _predict_ball_landing() -> Vector3:
	var pos: Vector3 = ball.position
	var vel: Vector3 = ball.linear_velocity
	if vel.length_squared() < 0.01:
		return pos
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var disc: float = vel.y * vel.y + 2.0 * g * maxf(pos.y, 0.0)
	if disc <= 0.0:
		return pos
	var t: float = (vel.y + sqrt(disc)) / g
	if t <= 0.0:
		return pos
	return Vector3(pos.x + vel.x * t, 0.0, pos.z + vel.z * t)

func _update_camera() -> void:
	# Camera sits on the player's side (negative z) looking toward +z, so
	# the human's own (blue) character is in the foreground. dest_z stays
	# negative; we still nudge it slightly with the ball so the framing
	# pulls back when the ball is deep on the opponent's side.
	var follow: float = ball.position.z * 0.06
	var dest_z: float = (-5.4 if is_doubles else -5.0) - follow
	camera_base_pos.z = move_toward(camera_base_pos.z, dest_z, 0.05)
	camera.position = camera_base_pos + game_feel.current_shake_offset
	# Re-aim each frame so the basis stays consistent as we follow the ball.
	camera.look_at(Vector3(0, 0.2, 0.5), Vector3.UP)

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
		if _is_two_bounce_violation():
			hud.show_message("Wait for the bounce!")
			return
		# Player is at -z, opponent at +z. Shots fly in +z direction.
		var direction = Vector3(0, 0.1, 1.0).normalized()
		ball.hit(power_charge, direction, BallRef.ShotType.DRIVE)
		ball.last_hitter_id = 0
		last_player_shot_type = BallRef.ShotType.DRIVE
		EventBus.ball_hit.emit(0, BallRef.ShotType.DRIVE, power_charge)
		match_manager.record_hit()
		_animate_paddle_swing(player)

# === PADDLE SWING ===

func _animate_paddle_swing(character: Node3D) -> void:
	# Rigged characters play a real smash animation; side picks left/right
	# arm based on where the ball is relative to the character.
	if character.has_method("play_swing") and character.has_method("is_animated") and character.is_animated():
		var facing_sign: float = 1.0 if character.global_position.z < 0.0 else -1.0
		var side: float = (ball.position.x - character.global_position.x) * facing_sign
		character.play_swing(side)
		return
	# Placeholder fallback: rotate the box paddle.
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
		hud.show_serve_indicator("Tap SERVE to serve")
		player.position = Vector3(0, 0, PLAYER_BASELINE)
		ball.hold_for_serve(Vector3(0, 0.5, PLAYER_BASELINE + 0.05))
		_set_touch_serve_button_visible(true)
		_set_touch_shot_buttons_visible(false)
	else:
		hud.show_serve_indicator("Opponent serving…")
		_set_touch_serve_button_visible(false)
		_set_touch_shot_buttons_visible(false)
		_reset_for_ai_serve()

# === SERVE FLOW (Doubles) ===

func _on_doubles_serve_ready(server_team: int, server_pos: int, _side: int) -> void:
	is_player_serving = (server_team == 0)
	
	if is_player_serving:
		player_serve_ready = true
		var serve_x = PLAYER_LEFT if server_pos == 0 else PLAYER_RIGHT
		var player_name = "Your" if server_pos == 0 else "Partner's"
		hud.show_serve_indicator(player_name + " serve — Swipe up to serve")
		ball.hold_for_serve(Vector3(serve_x, 0.5, PLAYER_BASELINE + 0.05))
	else:
		hud.show_serve_indicator("Opponent team serving...")
		_reset_for_doubles_ai_serve(server_pos)

func _reset_for_ai_serve() -> void:
	opponent.position = Vector3(0, 0, OPPONENT_BASELINE)
	ball.hold_for_serve(Vector3(0, 0.5, OPPONENT_BASELINE - 0.05))

	await get_tree().create_timer(0.8).timeout
	if not match_manager.match_complete:
		_ai_serve()

func _reset_for_doubles_ai_serve(server_pos: int) -> void:
	var serve_x = PLAYER_RIGHT if server_pos == 0 else PLAYER_LEFT
	ball.hold_for_serve(Vector3(serve_x, 0.5, OPPONENT_BASELINE - 0.05))

	await get_tree().create_timer(0.8).timeout
	if not doubles_manager.match_complete:
		_doubles_ai_serve(server_pos)

func _ai_serve() -> void:
	# Deep-ish target on the player's side, well past their kitchen line.
	var target = Vector3(randf_range(-0.5, 0.5), 0, PLAYER_BASELINE + 0.65)
	ball.serve(ball.position, target, 0.55)
	ball.last_hitter_id = 1
	_animate_paddle_swing(opponent)
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
	if not game_state.can_serve() and not rally_active:
		return

	var dir_name = input_handler.get_swipe_direction_name(velocity)

	if game_state.can_serve() and is_player_serving:
		if is_doubles:
			_handle_doubles_player_serve(dir_name, velocity)
		else:
			_handle_player_serve(dir_name, velocity)
		return

	# Rally: swipes commit a shot (direction picks the type); commit is
	# allowed any time the ball is inbound, even before it crosses the net.
	if rally_active and ball.is_in_play:
		_handle_player_shot(dir_name, velocity)

func _handle_player_serve(swipe_dir: String, velocity: Vector2) -> void:
	if swipe_dir != "up":
		hud.show_serve_indicator("Swipe UP to serve!")
		return
	
	if not match_manager.validate_serve(swipe_dir, ball.position.y):
		hud.show_serve_indicator("Serve must be underhand!")
		return

	# Wii-Sports mobile swipe-serve: ignore velocity/direction details,
	# just commit a default-power serve.
	_launch_player_serve(0.65)

func _handle_doubles_player_serve(swipe_dir: String, velocity: Vector2) -> void:
	if swipe_dir != "up":
		hud.show_serve_indicator("Swipe UP to serve!")
		return

	if not match_manager.validate_serve(swipe_dir, ball.position.y):
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
	hud.show_gesture_guide(true)

func _handle_player_shot(swipe_dir: String, _velocity: Vector2) -> void:
	# Swipe direction picks the shot type; the rest (range check,
	# timing-quality flash, power, target) is the unified swing path,
	# so mouse swipes get the same gating as keyboard / touch buttons.
	var shot_type: int = BallRef.ShotType.DRIVE
	match swipe_dir:
		"up":
			shot_type = BallRef.ShotType.LOB
		"down":
			shot_type = BallRef.ShotType.DINK
		_:
			shot_type = BallRef.ShotType.DRIVE
	_commit_shot(shot_type)

func _on_tap_detected(_position: Vector2) -> void:
	# Tap = commit a DRIVE (same as Space).
	_commit_shot(BallRef.ShotType.DRIVE)

func _on_double_tap(_position: Vector2) -> void:
	# Double tap = commit a LOB.
	_commit_shot(BallRef.ShotType.LOB)

func _on_drag(_from: Vector2, _to: Vector2) -> void:
	# Drags route through _on_swipe_detected → _handle_player_shot, which
	# commits by direction. Nothing extra here.
	pass

# === AI SHOT ===

func _on_ai_shot_selected(shot_type: int, direction: Vector3, force: float) -> void:
	if not rally_active:
		return

	# AI hit ID: 1 in singles, 1 or 3 in doubles (opponent partner).
	var ai_hitter_id: int = 1
	if is_doubles and ball.last_hitter_id == 3:
		ai_hitter_id = 3

	if _is_two_bounce_violation():
		_two_bounce_fault(ai_hitter_id, "Opponent volleyed before two bounces")
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
			# award_point_from_rally takes the LOSER id — opponent loses on their violation.
			match_manager.award_point_from_rally(1, "Opponent kitchen violation")
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
	bounces_since_last_hit += 1
	total_bounces_in_rally += 1

	# First bounce of a point is always the serve landing. Validate it.
	if total_bounces_in_rally == 1:
		if _is_serve_fault(position):
			return  # _serve_fault already ended the rally

	if bounces_since_last_hit >= 2:
		_end_rally_double_bounce()

# Returns true (and ends the rally) if the serve landed illegally.
# Round-1 simplified: only check the serve actually crossed the net.
# Out-of-bounds is caught by the per-frame _check_ball_out_of_bounds.
func _is_serve_fault(pos: Vector3) -> bool:
	var server_id: int = ball.last_hitter_id
	var server_is_player_team: bool = server_id == 0 or server_id == 2
	if server_is_player_team and pos.z < 0:
		_serve_fault(server_id, "Serve in own court")
		return true
	if not server_is_player_team and pos.z > 0:
		_serve_fault(server_id, "Serve in own court")
		return true
	return false

func _serve_fault(server_id: int, reason: String) -> void:
	if not rally_active:
		return
	rally_active = false
	if is_doubles:
		var loser_team: int = 0 if server_id == 0 or server_id == 2 else 1
		doubles_manager.award_point_from_rally(loser_team, reason)
	else:
		# award_point_from_rally takes loser id; the server is the loser.
		match_manager.award_point_from_rally(server_id, reason)

# Returns true if the attempted hit violates the two-bounce rule.
func _is_two_bounce_violation() -> bool:
	if total_bounces_in_rally >= 2:
		return false  # Volleys legal once both required bounces have happened
	if bounces_since_last_hit < 1:
		return true   # Trying to hit before the required bounce
	return false

func _two_bounce_fault(hitter_id: int, reason: String) -> void:
	if not rally_active:
		return
	rally_active = false
	if is_doubles:
		var loser_team: int = 0 if hitter_id == 0 or hitter_id == 2 else 1
		doubles_manager.award_point_from_rally(loser_team, reason)
	else:
		match_manager.award_point_from_rally(hitter_id, reason)

func _on_any_ball_hit_for_rally_tracking(_shooter_id: int, _shot_type: int, _force: float) -> void:
	bounces_since_last_hit = 0

# Hitter wins — opponent couldn't return before the second bounce.
func _end_rally_double_bounce() -> void:
	if not rally_active:
		return
	rally_active = false
	var hitter: int = ball.last_hitter_id
	if is_doubles:
		var loser_team: int = 0 if hitter in [1, 3] else 1
		doubles_manager.award_point_from_rally(loser_team, "Double bounce")
	else:
		var loser_id: int = 1 if hitter == 0 else 0
		match_manager.award_point_from_rally(loser_id, "Double bounce")

# Hitter loses — shot went out.
func _end_rally_out_of_bounds() -> void:
	if not rally_active:
		return
	rally_active = false
	var hitter: int = ball.last_hitter_id
	if is_doubles:
		var loser_team: int = 0 if hitter in [0, 2] else 1
		doubles_manager.award_point_from_rally(loser_team, "Out of bounds")
	else:
		# Defensive fallback if last_hitter_id is unset (-1): give the point
		# to whichever side the ball ended up on.
		var loser_id: int = hitter if hitter >= 0 else (0 if ball.position.z < 0 else 1)
		match_manager.award_point_from_rally(loser_id, "Out of bounds")

func _update_turn_indicator() -> void:
	if not rally_active or not ball.is_in_play:
		return
	# Commit-early model: prompt the moment the ball is ours to play
	# (AI hit it last), clear once a shot is locked or it's not our ball.
	if ball.last_hitter_id != 0 and not player_swung_this_approach:
		if pending_shot == -1:
			hud.show_serve_indicator("Pick your shot!")
		else:
			hud.show_serve_indicator("")
	else:
		hud.show_serve_indicator("")

func _check_ball_stuck(delta: float) -> void:
	# If the ball comes to a halt during an active rally (e.g. rolled to a
	# stop after a soft dink the AI couldn't reach), give it BALL_REST_TIMEOUT
	# seconds and then end the rally — the last hitter wins, because the
	# other side didn't return in time.
	if not rally_active or not ball.is_in_play:
		ball_rest_timer = 0.0
		return
	if ball.linear_velocity.length() < 0.35:
		ball_rest_timer += delta
		if ball_rest_timer >= BALL_REST_TIMEOUT:
			ball_rest_timer = 0.0
			_end_rally_double_bounce()
	else:
		ball_rest_timer = 0.0

func _check_ball_out_of_bounds() -> void:
	if not rally_active or not ball.is_in_play:
		return
	# Real pickleball rule: the FIRST bounce after a hit determines in/out.
	# Once the ball has bounced legally, it can roll/bounce out the back —
	# the rally still ends via double-bounce or stuck-ball, not OOB. Only
	# check OOB while the ball is still in its initial flight.
	if bounces_since_last_hit >= 1:
		return
	var pos: Vector3 = ball.position
	if absf(pos.x) > OUT_X_LIMIT or absf(pos.z) > OUT_Z_LIMIT or pos.y < FLOOR_Y_LIMIT:
		_end_rally_out_of_bounds()

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
	_set_touch_serve_button_visible(false)
	_set_touch_shot_buttons_visible(false)

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
	if scorer_id == 0 or scorer_id == 2:
		hud.show_message("✦  YOU SCORED  ✦\n" + reason, PLAYER_TEAM_COLOR)
	else:
		hud.show_message("✦  AI SCORED  ✦\n" + reason, OPPONENT_TEAM_COLOR)

	await get_tree().create_timer(1.5).timeout

	if not match_manager.match_complete:
		_reset_rally()
		game_state.transition_to(GameStateRef.State.SERVE_WAIT)
		_on_serve_ready(scorer_id, 0)

func _on_side_out(new_server_id: int, reason: String) -> void:
	# Side-out: receiver wins the rally, serve transfers, no point awarded.
	rally_active = false
	hud.show_message("Side out — " + reason)
	await get_tree().create_timer(1.5).timeout
	if not match_manager.match_complete:
		_reset_rally()
		game_state.transition_to(GameStateRef.State.SERVE_WAIT)
		_on_serve_ready(new_server_id, match_manager.current_serve_side)

func _on_match_over(winner_id: int, final_scores: Array) -> void:
	var player_won = winner_id == 0
	var msg = "You win!" if player_won else "Opponent wins!"

	# Victory / defeat poses (held until the next match resets them).
	var winner_char: Node3D = player if player_won else opponent
	var loser_char: Node3D = opponent if player_won else player
	if winner_char and winner_char.has_method("celebrate"):
		winner_char.celebrate()
	if loser_char and loser_char.has_method("play_defeat"):
		loser_char.play_defeat()

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
	bounces_since_last_hit = 0
	total_bounces_in_rally = 0
	ai_ready_to_swing = false
	ai_swing_timer = 0.0
	ai_winding_up = false
	ai_contact_timer = 0.0
	ai_just_swung = false
	pending_shot = -1
	swing_in_progress = false
	swing_contact_timer = 0.0
	player_swung_this_approach = false
	was_serve_space_pressed = false
	was_rally_space_pressed = false
	was_lob_key_pressed = false
	was_dink_key_pressed = false
	touch_move_dir = Vector2.ZERO
	match_manager.reset_rally()
	ai_manager.reset()
	ball.reset()
	# Park away from the net — the net's collision group works now, and a
	# ball resting against it would ding the net SFX every rally reset.
	ball.position = Vector3(0, 0.05, -1.0)

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
	# (start_match already emitted serve_ready, which set the serve prompt.)

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
	# (start_doubles_match already emitted serve_ready.)
