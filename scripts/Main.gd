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
# AI auto-swing — fires after a brief reaction window once the ball is in
# range of the AI character.
var ai_ready_to_swing: bool = false
var ai_swing_timer: float = 0.0
# Flag set when AI just swung; cleared when the ball crosses back to the
# player's side. Prevents the AI from re-hitting its own outgoing ball.
var ai_just_swung: bool = false
const AI_REACTION_TIME: float = 0.35
const AI_HIT_RANGE: float = 2.50
# How close the ball needs to be to the player character for a Space press
# to count as a connected swing. Generous on purpose.
const PLAYER_HIT_RANGE: float = 2.1

# Camera base (Main owns this; GameFeel adds a shake offset on top each frame).
var camera_base_pos: Vector3 = Vector3.ZERO

# Landing marker — a flat ring on the court showing where the ball will bounce.
var landing_marker: MeshInstance3D = null
# Swing-zone ring around the player character: colour-coded by how perfect
# a swing would be right now.
var swing_zone_ring: MeshInstance3D = null
# Power-meter semicircle in front of the player — fills up segment-by-segment
# as the ball gets closer to perfect contact range.
var power_segments: Array[MeshInstance3D] = []
const POWER_SEGMENT_COUNT: int = 7
const POWER_METER_RADIUS: float = 0.35
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
const OUT_X_LIMIT: float = 1.55
const OUT_Z_LIMIT: float = 2.30
const FLOOR_Y_LIMIT: float = -0.3

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
	camera.position = Vector3(0, 2.8, -4.2)
	camera.look_at(Vector3(0, 0.3, 0), Vector3.UP)
	camera.fov = 65

	# Initialize game feel and capture the (new) camera position as our base.
	game_feel.setup(camera, hud)
	camera_base_pos = camera.position

	# Team coloring so the player can tell themselves apart from the AI.
	_apply_team_colors()

	# Spawn the landing marker (hidden until first serve).
	_spawn_landing_marker()
	_spawn_swing_zone_ring()
	_spawn_power_meter()

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
	# Wii-Sports rally swing: one tap of Space hits the ball when it's on
	# the player's side. Whether the swing connects depends only on whether
	# the ball is in PLAYER_HIT_RANGE of the character.
	var space_now: bool = Input.is_key_pressed(KEY_SPACE)
	if rally_active and ball.is_in_play and ball.position.z < 0 and not game_state.can_serve():
		if space_now and not was_rally_space_pressed:
			_player_swing()
	was_rally_space_pressed = space_now

# Wii-Sports player swing: forgiving — if the ball is anywhere within
# PLAYER_HIT_RANGE of the character, the swing connects and the ball flies
# back toward the opponent's court. Timing quality (distance at impact)
# controls power: closer = PERFECT, further = OK.
func _player_swing() -> void:
	_player_swing_with_shot(BallRef.ShotType.DRIVE)

# Single entry point — used by keyboard Space and by the LOB/DRIVE/DINK
# touch buttons. Computes the timing quality, shows feedback, applies a
# power proportional to that quality.
func _player_swing_with_shot(shot_type: int) -> void:
	if not (rally_active and ball.is_in_play):
		return
	# Ball must be solidly on the player's side, not still passing over the
	# net. The 0.1 margin treats anything within 10 cm of the net as "not
	# yet on your side" — prevents the 'I swung but the ball was on the
	# other court' feeling.
	if ball.position.z > -0.1:
		return
	if ball.linear_velocity.z > 0.5:
		return  # ball flying away, can't be hit
	var dist: float = Vector2(player.position.x - ball.position.x, player.position.z - ball.position.z).length()
	if dist > PLAYER_HIT_RANGE:
		hud.show_message("Whiff!", Color(1, 0.4, 0.4))
		return
	# Tier feedback only — quality affects target precision, not arc.
	var quality_scale: float
	if dist < PERFECT_DIST:
		hud.show_message("✦ PERFECT! ✦", Color(0.2, 1.0, 0.4))
		quality_scale = 0.10  # tight aim
	elif dist < GOOD_DIST:
		hud.show_message("GOOD!", Color(1.0, 0.95, 0.2))
		quality_scale = 0.25
	else:
		hud.show_message("OK", Color(1.0, 0.6, 0.2))
		quality_scale = 0.45  # sprayed aim
	# Shot type determines trajectory (flight time) and target depth.
	# LOB high & deep; DINK low & short; DRIVE low & mid.
	var target_x: float = clampf(-ball.position.x * 0.7 + randf_range(-quality_scale, quality_scale), -1.2, 1.2)
	var target_z: float
	var flight_time: float
	match shot_type:
		BallRef.ShotType.LOB:
			target_z = OPPONENT_BASELINE - randf_range(0.15, 0.4)
			flight_time = 1.10
		BallRef.ShotType.DINK:
			target_z = randf_range(0.35, 0.85)
			flight_time = 0.90
		_:
			target_z = OPPONENT_BASELINE - randf_range(0.5, 0.95)
			flight_time = 0.70
	var target := Vector3(target_x, 0, target_z)
	ball.launch_at_target(ball.position, target, flight_time)
	ball.last_hitter_id = 0
	last_player_shot_type = shot_type
	# Convert the timing tier back to a 0-1 "power" for downstream listeners
	# (audio, vfx) that still expect that signal shape.
	var emit_power: float = 1.0 - clampf(quality_scale / 0.45, 0.0, 1.0) * 0.5
	EventBus.ball_hit.emit(0, shot_type, emit_power)
	_announce_shot(shot_type)
	match_manager.record_hit()
	_animate_paddle_swing(player)

# Wii-Sports AI auto-swing: once the ball is on the AI's side and within
# AI_HIT_RANGE of the AI character, fire a swing after a short reaction
# window. No decision tree, no shot types — just send the ball back.
func _process_ai_swing(delta: float) -> void:
	# When the ball is back on the player's side, reset everything.
	if ball.position.z < 0:
		ai_ready_to_swing = false
		ai_swing_timer = 0.0
		ai_just_swung = false
		return
	if not (rally_active and ball.is_in_play):
		ai_ready_to_swing = false
		ai_swing_timer = 0.0
		return
	# Don't re-hit a ball we just sent away.
	if ai_just_swung:
		return
	if total_bounces_in_rally < 1:
		return  # wait for the serve to bounce first
	if ai_ready_to_swing:
		ai_swing_timer -= delta
		if ai_swing_timer <= 0.0:
			ai_ready_to_swing = false
			# Re-check distance at swing time — if the ball moved out of
			# range during the reaction window, AI whiffs (no hit, last
			# hitter unchanged, so the eventual fault goes to the right
			# side).
			var dist_now: float = Vector2(opponent.position.x - ball.position.x, opponent.position.z - ball.position.z).length()
			if dist_now <= AI_HIT_RANGE:
				ai_just_swung = true
				_ai_swing()
		return
	var dist: float = Vector2(opponent.position.x - ball.position.x, opponent.position.z - ball.position.z).length()
	if dist <= AI_HIT_RANGE:
		ai_ready_to_swing = true
		ai_swing_timer = AI_REACTION_TIME

func _ai_swing() -> void:
	if not rally_active or not ball.is_in_play:
		return
	var target_x: float = clampf(-ball.position.x * 0.5 + randf_range(-0.45, 0.45), -1.2, 1.2)
	var target_z: float = PLAYER_BASELINE + randf_range(0.4, 1.0)
	var target := Vector3(target_x, 0, target_z)
	# AI uses a flat DRIVE-style trajectory most of the time.
	ball.launch_at_target(ball.position, target, 0.85)
	ball.last_hitter_id = 1
	EventBus.ball_hit.emit(1, BallRef.ShotType.DRIVE, 0.75)
	match_manager.record_hit()
	_animate_paddle_swing(opponent)

func _launch_player_serve(power: float) -> void:
	if not player_serve_ready:
		return
	player_serve_ready = false
	game_state.transition_to(GameStateRef.State.SERVE_ACTIVE)

	# Wii-Sports serve: fixed target in the middle of the opponent's
	# mid-court with a small random nudge.
	var target := Vector3(randf_range(-0.5, 0.5), 0, 1.1)
	ball.serve(ball.position, target, power)
	ball.last_hitter_id = 0

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
	# Touch buttons share the keyboard swing's quality-based pipeline.
	_player_swing_with_shot(shot_type)

func _on_touch_move(direction: Vector2) -> void:
	touch_move_dir = direction

func _spawn_power_meter() -> void:
	# Build POWER_SEGMENT_COUNT small flat boxes that we'll arrange in a
	# half-circle in front of the player every frame.
	for _i in POWER_SEGMENT_COUNT:
		var seg: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(0.07, 0.005, 0.13)
		seg.mesh = box
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.2, 0.25, 0.35)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.2, 0.25)
		mat.emission_energy_multiplier = 0.4
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		seg.material_override = mat
		seg.visible = false
		add_child(seg)
		power_segments.append(seg)

func _update_power_meter_segments() -> void:
	if power_segments.is_empty():
		return
	# Only visible while the ball is approaching the player on their side.
	var show: bool = rally_active and ball.is_in_play \
		and ball.position.z < 0 \
		and ball.linear_velocity.z <= 0.5
	if not show:
		for seg in power_segments:
			seg.visible = false
		return

	var dist: float = Vector2(player.position.x - ball.position.x, player.position.z - ball.position.z).length()
	# 0 when out of hit range, 1 when at perfect distance.
	var power_pct: float = 1.0 - clampf((dist - PERFECT_DIST) / maxf(PLAYER_HIT_RANGE - PERFECT_DIST, 0.01), 0.0, 1.0)
	var lit_count: int = int(round(power_pct * POWER_SEGMENT_COUNT))

	var color_lit: Color
	if power_pct > 0.85:
		color_lit = Color(0.15, 1.0, 0.35)        # green — perfect
	elif power_pct > 0.55:
		color_lit = Color(1.0, 0.95, 0.2)         # yellow — good
	elif power_pct > 0.2:
		color_lit = Color(1.0, 0.55, 0.15)        # orange — ok
	else:
		color_lit = Color(1.0, 0.25, 0.25)        # red — far

	# Arrange segments in a half-circle in FRONT of the player (toward the
	# net, which is +z for our player at -z).
	for i in POWER_SEGMENT_COUNT:
		var seg: MeshInstance3D = power_segments[i]
		seg.visible = true
		var fraction: float = float(i) / float(POWER_SEGMENT_COUNT - 1)
		var angle: float = lerpf(-PI * 0.45, PI * 0.45, fraction)
		seg.global_position = Vector3(
			player.position.x + sin(angle) * POWER_METER_RADIUS,
			0.02,
			player.position.z + 0.18 + cos(angle) * 0.05
		)
		seg.rotation.y = -angle
		var mat: StandardMaterial3D = seg.material_override as StandardMaterial3D
		if i < lit_count:
			mat.albedo_color = color_lit
			mat.emission = color_lit
			mat.emission_energy_multiplier = 1.2
		else:
			mat.albedo_color = Color(0.18, 0.18, 0.22, 0.5)
			mat.emission = Color(0.18, 0.18, 0.22)
			mat.emission_energy_multiplier = 0.3

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
	# Only show when the ball is approaching the player on their side.
	if not (rally_active and ball.is_in_play) \
		or ball.position.z >= 0 \
		or ball.linear_velocity.z > 0.5:
		swing_zone_ring.visible = false
		return
	swing_zone_ring.visible = true
	swing_zone_ring.global_position = Vector3(player.position.x, 0.015, player.position.z)

	# Two-bounce wait: ring is grey/dim, "don't hit yet" cue.
	var awaiting_bounce: bool = total_bounces_in_rally < 2 and bounces_since_last_hit < 1
	var color: Color
	if awaiting_bounce:
		color = Color(0.45, 0.45, 0.5, 0.55)   # grey: not yet hittable
	else:
		var dist: float = Vector2(player.position.x - ball.position.x, player.position.z - ball.position.z).length()
		if dist < PERFECT_DIST:
			color = Color(0.15, 1.0, 0.35, 1.0)     # green
		elif dist < GOOD_DIST:
			color = Color(1.0, 0.95, 0.2, 0.95)     # yellow
		elif dist < PLAYER_HIT_RANGE:
			color = Color(1.0, 0.55, 0.15, 0.9)     # orange
		else:
			color = Color(1.0, 0.25, 0.25, 0.7)     # red
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
	var body: MeshInstance3D = character.get_node_or_null("Body") as MeshInstance3D
	if body == null:
		return
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.5
	body.material_override = mat

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
	_update_power_meter_segments()
	_process_serve_input(delta)
	_process_rally_input()
	_process_ai_swing(delta)
	_check_ball_stuck(delta)

	# Make characters look toward the ball each frame
	_update_characters_look_at_ball()

func _update_player_auto_move(delta: float) -> void:
	# Don't move anyone while waiting on a serve — the serve setup placed
	# them in the correct service court and we shouldn't pull them back to
	# center until the ball is in play.
	if not ball.is_in_play:
		return

	var player_target_z = PLAYER_BASELINE
	var opp_target_z = OPPONENT_BASELINE
	var player_target_x = 0.0
	var opp_target_x = 0.0

	if ball.is_in_play:
		# Wii-Sports auto-positioning: whoever's side the ball is on runs to
		# meet it at its predicted landing. The other side drifts back to
		# their baseline with a slight lateral lean while they wait.
		var landing: Vector3 = _predict_ball_landing()
		if is_doubles:
			# Doubles still uses the old simple zone coverage.
			if ball.position.z < 0 and ball.position.x < 0:
				player_target_z = PLAYER_BASELINE
				player_target_x = clampf(ball.position.x, -0.5, 0.0)
			elif ball.position.z > 0 and ball.position.x < 0:
				opp_target_z = OPPONENT_BASELINE
				opp_target_x = clampf(ball.position.x, -0.5, 0.0)
		else:
			if ball.position.z < 0:
				# Ball is coming to the player — auto-run there.
				var plx: float = landing.x if landing.z < -0.05 else ball.position.x
				var plz: float = landing.z if landing.z < -0.05 else ball.position.z
				player_target_x = clampf(plx, -1.4, 1.4)
				player_target_z = clampf(plz + 0.15, -2.1, -0.85)
				opp_target_x = clampf(ball.position.x * 0.3, -0.6, 0.6)
				opp_target_z = OPPONENT_BASELINE
			else:
				# Ball heading to the AI — AI runs there, player drifts back.
				var olx: float = landing.x if landing.z > 0.05 else ball.position.x
				var olz: float = landing.z if landing.z > 0.05 else ball.position.z
				opp_target_x = clampf(olx, -1.4, 1.4)
				opp_target_z = clampf(olz - 0.15, 0.85, 2.1)
				player_target_x = clampf(ball.position.x * 0.3, -0.6, 0.6)
				player_target_z = PLAYER_BASELINE

	# Move rate per second. Sport-pacing — characters jog to the ball
	# without snapping. About a quarter court per second.
	var move_rate: float = delta * 2.5
	player.position.x = move_toward(player.position.x, player_target_x, move_rate)
	player.position.z = move_toward(player.position.z, player_target_z, move_rate)

	if not is_doubles:
		opponent.position.x = move_toward(opponent.position.x, opp_target_x, move_rate)
		opponent.position.z = move_toward(opponent.position.z, opp_target_z, move_rate)

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
	var follow: float = ball.position.z * 0.08
	var dest_z: float = (-4.6 if is_doubles else -4.2) - follow
	camera_base_pos.z = move_toward(camera_base_pos.z, dest_z, 0.05)
	camera.position = camera_base_pos + game_feel.current_shake_offset
	# Re-aim each frame so the basis stays consistent as we follow the ball.
	camera.look_at(Vector3(0, 0.3, 0), Vector3.UP)

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
	# Center-ish target on the player's side, past their kitchen line.
	var target = Vector3(randf_range(-0.5, 0.5), 0, PLAYER_BASELINE + 0.45)
	ball.serve(ball.position, target, 0.55)
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
	_player_swing_with_shot(shot_type)

func _on_tap_detected(_position: Vector2) -> void:
	# If charging, release power shot
	if is_charging:
		release_power_shot()
		return
	
	# Tap = volley if ball on player side and in air
	if rally_active and ball.position.z < 0 and ball.position.y > 0.1 and ball.is_in_play:
		if _is_two_bounce_violation():
			hud.show_message("Wait for the bounce!")
			return
		var power = 0.7
		var direction = Vector3(0, -0.1, 1.0).normalized()

		if match_manager.check_kitchen_violation(player.position, true):
			hud.show_message("No volleying from the kitchen!")
			return
		
		ball.hit(power, direction, BallRef.ShotType.VOLLEY)
		ball.last_hitter_id = 0
		last_player_shot_type = BallRef.ShotType.VOLLEY
		EventBus.ball_hit.emit(0, BallRef.ShotType.VOLLEY, power)
		_announce_shot(BallRef.ShotType.VOLLEY)
		match_manager.record_hit()

func _on_double_tap(_position: Vector2) -> void:
	# Double tap starts power charge
	start_power_charge()

func _on_drag(from: Vector2, to: Vector2) -> void:
	if rally_active and ball.position.z < 0 and ball.is_in_play:
		var drag_vector = to - from
		var power = clampf(drag_vector.length() / 500.0, 0.3, 0.9)
		var target_x = clampf((to.x - 540) / 540.0, -0.5, 0.5)
		var direction = Vector3(target_x, 0.3, 0.9).normalized()
		ball.hit(power, direction, BallRef.ShotType.DRIVE)
		ball.last_hitter_id = 0
		EventBus.ball_hit.emit(0, BallRef.ShotType.DRIVE, power)
		match_manager.record_hit()

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
	if ball.position.z < 0:
		# Two-bounce phase: the ball has crossed to player's side after
		# the AI's serve but hasn't bounced yet. Tell the user to wait.
		if total_bounces_in_rally < 2 and bounces_since_last_hit < 1:
			hud.show_serve_indicator("Wait for the bounce…")
		else:
			hud.show_serve_indicator("SPACE to swing!")
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
	ai_just_swung = false
	was_serve_space_pressed = false
	was_rally_space_pressed = false
	match_manager.reset_rally()
	ai_manager.reset()
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
