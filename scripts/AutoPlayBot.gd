# AutoPlayBot.gd
# Headless playtest bot. Only active when the game is launched with
# `-- --autoplay` on the command line; otherwise inert.
#
# Plays Quick Match like a player would: serves, commits shots with a
# rotating timing style (instant / medium / late / never), and logs every
# rally event. Prints a summary and quits when the match ends.
extends Node

const BallScript = preload("res://scripts/Ball.gd")

var active: bool = false
var main: Node = null
var started: bool = false
var t: float = 0.0
var serve_wait: float = 0.0
var commit_delay: float = -1.0   # countdown to commit; -1 = not scheduled
var commit_style: int = 0        # rotates per rally: instant/medium/late/skip
var match_done: bool = false

# Stats
var hits_this_rally: int = 0
var rally_lengths: Array = []
var points_log: Array = []
var last_ball_report: float = 0.0

func _ready() -> void:
	active = "--autoplay" in OS.get_cmdline_user_args()
	if not active:
		set_process(false)
		return
	print("[BOT] autoplay active")
	EventBus.ball_hit.connect(_on_ball_hit)
	EventBus.ball_bounced.connect(_on_bounce)

func _process(delta: float) -> void:
	t += delta
	if t > 150.0:
		_finish("TIMEOUT after 150s")
		return
	if main == null:
		main = get_tree().current_scene
		if main == null or not main.has_method("start_quick_match"):
			main = null
			return
	if not started and t > 1.5:
		started = true
		print("[BOT] starting quick match at t=%.1f" % t)
		main._on_menu_start_quick()
		main.match_manager.point_awarded.connect(_on_point)
		main.match_manager.match_over.connect(_on_match_over)
		return
	if not started or match_done:
		return

	# Fine-grained ball telemetry while in play (every 0.1s) to catch
	# floor-tunneling: if y ever goes below 0 the ball fell through.
	var b = main.ball
	if b.is_in_play and t - last_ball_report > 0.1:
		last_ball_report = t
		print("[TRAJ] t=%.2f y=%.3f z=%.3f vy=%.2f vz=%.2f" % [
			t, b.position.y, b.position.z, b.linear_velocity.y, b.linear_velocity.z])

	# Serve when it's ours.
	if main.game_state.can_serve() and main.is_player_serving and main.player_serve_ready:
		serve_wait += delta
		if serve_wait >= 0.6:
			serve_wait = 0.0
			print("[BOT] t=%.1f serving" % t)
			main._launch_player_serve(0.65)
		return

	# Commit when the ball is inbound (AI hit it last).
	var ball = main.ball
	var inbound: bool = main.rally_active and ball.is_in_play and ball.last_hitter_id != 0
	if not inbound:
		commit_delay = -1.0
		return
	if main.pending_shot != -1 or main.player_swung_this_approach:
		return
	if commit_delay < 0.0:
		match commit_style % 4:
			0: commit_delay = 0.05   # instant commit → expect PERFECT
			1: commit_delay = 0.6    # medium → expect GOOD/OK
			2: commit_delay = 1.2    # late → expect OK or miss
			_: commit_delay = 999.0  # never commit → expect lost point
		print("[BOT] t=%.1f ball inbound, committing in %.2fs (style %d)" % [t, commit_delay, commit_style % 4])
	commit_delay -= delta
	if commit_delay <= 0.0:
		commit_delay = -1.0
		var shots = [BallScript.ShotType.DRIVE, BallScript.ShotType.LOB, BallScript.ShotType.DINK]
		var shot: int = shots[randi() % shots.size()]
		print("[BOT] t=%.1f COMMIT shot=%d" % [t, shot])
		main._commit_shot(shot)

func _on_ball_hit(shooter_id: int, shot_type: int, force: float) -> void:
	if not active:
		return
	hits_this_rally += 1
	print("[EVT] t=%.1f hit by=%d type=%d force=%.2f ball_z=%.2f" % [t, shooter_id, shot_type, force, main.ball.position.z if main else 0.0])

func _on_bounce(pos: Vector3, side: int) -> void:
	if not active:
		return
	print("[EVT] t=%.1f bounce at (%.2f, %.2f) side=%d" % [t, pos.x, pos.z, side])

func _on_point(scorer_id: int, reason: String) -> void:
	rally_lengths.append(hits_this_rally)
	var who: String = "PLAYER" if scorer_id == 0 else "AI"
	var entry: String = "%s scored (%s) after %d hits — score %d-%d" % [
		who, reason, hits_this_rally,
		main.match_manager.player_scores[0], main.match_manager.player_scores[1]]
	points_log.append(entry)
	print("[POINT] t=%.1f %s" % [t, entry])
	hits_this_rally = 0
	commit_style += 1
	commit_delay = -1.0

func _on_match_over(winner_id: int, scores: Array) -> void:
	_finish("MATCH OVER — winner=%d, score %s" % [winner_id, str(scores)])

func _finish(why: String) -> void:
	if match_done:
		return
	match_done = true
	print("\n========== AUTOPLAY SUMMARY ==========")
	print("End reason: ", why)
	print("Total sim time: %.1fs" % t)
	print("Points played: ", points_log.size())
	for p in points_log:
		print("  • ", p)
	if rally_lengths.size() > 0:
		var total: int = 0
		for r in rally_lengths:
			total += r
		print("Avg hits per rally: %.1f" % (float(total) / rally_lengths.size()))
	print("======================================\n")
	get_tree().quit()
