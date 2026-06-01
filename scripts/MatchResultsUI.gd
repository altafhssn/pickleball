# MatchResultsUI.gd
# Full-screen match results with animated stats and rewards
extends CanvasLayer

signal play_again
signal go_to_menu

# Node references
@onready var score_label: Label = $ScoreLabel
@onready var winner_label: Label = $WinnerLabel
@onready var rallies_value: Label = $StatsGrid/RalliesValue
@onready var longest_value: Label = $StatsGrid/LongestValue
@onready var aces_value: Label = $StatsGrid/AcesValue
@onready var drives_value: Label = $StatsGrid/DrivesValue
@onready var dinks_value: Label = $StatsGrid/DinksValue
@onready var lobs_value: Label = $StatsGrid/LobsValue
@onready var volleys_value: Label = $StatsGrid/VolleysValue
@onready var xp_value: Label = $RewardsPanel/XPValue
@onready var coins_value: Label = $RewardsPanel/CoinsValue
@onready var gems_value: Label = $RewardsPanel/GemsValue
@onready var level_label: Label = $LevelLabel
@onready var xp_bar: ProgressBar = $XPProgressBar
@onready var xp_progress_label: Label = $XPProgressLabel
@onready var play_again_button: Button = $PlayAgainButton
@onready var menu_button: Button = $MenuButton

# Stats to display
var final_scores: Array = [0, 0]
var winner_id: int = 0
var match_stats: Dictionary = {}
var rewards: Dictionary = {}

# Animation state
var animating: bool = false

func _ready() -> void:
	play_again_button.pressed.connect(_on_play_again)
	menu_button.pressed.connect(_on_menu)

func setup(scores: Array, winner: int, stats: Dictionary = {}) -> void:
	final_scores = scores
	winner_id = winner
	match_stats = stats
	
	# Display score and winner instantly
	_update_static_display()
	
	# Grant rewards and get reward values
	rewards = _grant_rewards()
	
	# Start animated display
	_animate_display()

func _update_static_display() -> void:
	# Scores
	score_label.text = str(final_scores[0]) + " - " + str(final_scores[1])
	
	# Winner text
	if winner_id == 0:
		winner_label.text = "You Win!"
		winner_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1))
	else:
		winner_label.text = "Opponent Wins"
		winner_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1))
	
	# Level and XP bar
	level_label.text = "Level " + str(PlayerData.player_level)
	var progress: float = PlayerData.get_level_progress()
	xp_bar.value = progress
	xp_bar.max_value = 1.0
	var current_xp: int = PlayerData.get_current_level_xp() + PlayerData.get_xp_for_level(PlayerData.player_level)
	var next_xp: int = PlayerData.get_xp_for_level(PlayerData.player_level + 1)
	xp_progress_label.text = str(current_xp) + " / " + str(next_xp) + " XP"

func _grant_rewards() -> Dictionary:
	# Calculate performance score from match result
	var perf_score: float = 1.0 if winner_id == 0 else 0.3
	return PlayerData.grant_match_rewards(perf_score)

func _animate_display() -> void:
	animating = true
	
	# Get stat values from provided data or defaults
	var rallies_total: int = match_stats.get("rallies_played", PlayerData.matches_played)
	var longest_rally: int = match_stats.get("longest_rally", 0)
	var aces: int = match_stats.get("aces", 0)
	
	var drives: int = match_stats.get("drives", 0)
	var dinks: int = match_stats.get("dinks", 0)
	var lobs: int = match_stats.get("lobs", 0)
	var volleys: int = match_stats.get("volleys", 0)
	
	var xp_gained: int = rewards.get("xp", 0)
	var coins_gained: int = rewards.get("coins", 0)
	var gems_gained: int = rewards.get("gems", 0)
	
	# Animate stats counting up
	_animate_number(rallies_value, rallies_total, 0.8)
	await get_tree().create_timer(0.15).timeout
	_animate_number(longest_value, longest_rally, 0.8)
	await get_tree().create_timer(0.15).timeout
	_animate_number(aces_value, aces, 0.8)
	await get_tree().create_timer(0.15).timeout
	_animate_number(drives_value, drives, 0.8)
	await get_tree().create_timer(0.1).timeout
	_animate_number(dinks_value, dinks, 0.8)
	await get_tree().create_timer(0.1).timeout
	_animate_number(lobs_value, lobs, 0.8)
	await get_tree().create_timer(0.1).timeout
	_animate_number(volleys_value, volleys, 0.8)
	
	# Animate rewards with a delay
	await get_tree().create_timer(0.3).timeout
	_animate_number(xp_value, xp_gained, 1.0, "+")
	await get_tree().create_timer(0.2).timeout
	_animate_number(coins_value, coins_gained, 1.0, "+")
	await get_tree().create_timer(0.2).timeout
	_animate_number(gems_value, gems_gained, 1.0, "+")
	
	# Update XP bar after rewards are applied
	await get_tree().create_timer(0.3).timeout
	_update_xp_bar_animated()
	
	animating = false

func _animate_number(label: Label, target: int, duration: float = 0.8, prefix: String = "") -> void:
	if target <= 0:
		label.text = prefix + "0"
		return
	
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_method(func(v): label.text = prefix + str(int(v)), 0, target, duration)

func _update_xp_bar_animated() -> void:
	var old_progress: float = xp_bar.value
	var new_progress: float = PlayerData.get_level_progress()
	
	# Update label with current values
	var current_xp: int = PlayerData.get_current_level_xp() + PlayerData.get_xp_for_level(PlayerData.player_level)
	var next_xp: int = PlayerData.get_xp_for_level(PlayerData.player_level + 1)
	xp_progress_label.text = str(current_xp) + " / " + str(next_xp) + " XP"
	
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_method(func(v): xp_bar.value = v, old_progress, new_progress, 0.8)
	
	# Update level label (in case of level up)
	level_label.text = "Level " + str(PlayerData.player_level)

func _on_play_again() -> void:
	if animating:
		return
	play_again.emit()

func _on_menu() -> void:
	if animating:
		return
	go_to_menu.emit()
