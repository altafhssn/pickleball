# AudioManager.gd
# Manages SFX playback for game events
# Autoloaded singleton
extends Node

# Preload audio files
var paddle_hit_sfx: AudioStream
var ball_bounce_sfx: AudioStream
var net_hit_sfx: AudioStream
var score_sfx: AudioStream
var serve_swipe_sfx: AudioStream

# Audio players
var sfx_players: Array[AudioStreamPlayer] = []

func _ready():
	# Load audio files
	paddle_hit_sfx = _load_audio("res://assets/audio/paddle_hit.ogg")
	ball_bounce_sfx = _load_audio("res://assets/audio/ball_bounce.ogg")
	net_hit_sfx = _load_audio("res://assets/audio/net_hit.ogg")
	score_sfx = _load_audio("res://assets/audio/score.ogg")
	serve_swipe_sfx = _load_audio("res://assets/audio/serve_swipe.ogg")
	
	# Create audio player pool
	for i in range(8):
		var player = AudioStreamPlayer.new()
		player.name = "SFXPlayer" + str(i)
		add_child(player)
		sfx_players.append(player)
	
	# Connect game events
	EventBus.ball_hit.connect(_on_ball_hit)
	EventBus.ball_bounced.connect(_on_ball_bounce)
	EventBus.ball_net_hit.connect(_on_net_hit)
	EventBus.point_scored.connect(_on_point_scored)
	EventBus.ball_served.connect(_on_ball_served)

func _load_audio(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _get_free_player() -> AudioStreamPlayer:
	for player in sfx_players:
		if not player.playing:
			return player
	# If all busy, use the first one (will cut off current sound)
	return sfx_players[0]

func play_sfx(stream: AudioStream, volume: float = 0.0) -> void:
	if not stream:
		return
	var player = _get_free_player()
	player.stream = stream
	player.volume_db = volume
	player.play()

func _on_ball_hit(shooter_id: int, _shot_type: int, force: float) -> void:
	var vol = linear_to_db(0.3 + force * 0.5)
	play_sfx(paddle_hit_sfx, vol)

func _on_ball_bounce(_position: Vector3, _side: int) -> void:
	play_sfx(ball_bounce_sfx, -3.0)

func _on_net_hit() -> void:
	play_sfx(net_hit_sfx, -2.0)

func _on_point_scored(_player_id: int, _new_score: int) -> void:
	play_sfx(score_sfx, 0.0)

func _on_ball_served(_from: Vector3, _target: Vector3) -> void:
	play_sfx(serve_swipe_sfx, -5.0)
