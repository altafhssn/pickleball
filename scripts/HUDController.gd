# HUDController.gd
# Controls the HUD CanvasLayer — score display, serve indicator, gesture guide
extends CanvasLayer

@onready var score_label: Label = $ScoreLabel
@onready var serve_label: Label = $ServeLabel
@onready var message_label: Label = $MessageLabel
@onready var power_bar: ProgressBar = $PowerIndicator
@onready var gesture_guide: Label = $GestureGuide

var message_timer: float = 0.0

func _ready():
	score_label.text = "0  –  0"
	serve_label.text = ""
	message_label.text = ""
	power_bar.visible = false
	power_bar.value = 0.0
	power_bar.max_value = 1.0
	# Layout/typography is owned by HUD.tscn — don't override at runtime.

func _process(delta: float) -> void:
	if message_timer > 0:
		message_timer -= delta
		if message_timer <= 0:
			message_label.text = ""

func update_score(player_score: int, opponent_score: int) -> void:
	score_label.text = "%d  –  %d" % [player_score, opponent_score]

func show_serve_indicator(text: String) -> void:
	serve_label.text = text

func show_gesture_guide(visible_flag: bool) -> void:
	if visible_flag:
		gesture_guide.text = "Serve: arrows aim · hold Space (release to launch)\nRally: W Lob · S Dink · A/D Cross · V Volley · P Power"
	else:
		gesture_guide.text = ""

func show_message(text: String) -> void:
	message_label.text = text
	message_timer = 2.0

func show_rewards(rewards: Dictionary) -> void:
	var lines = []
	if rewards.has("xp"):
		lines.append("+" + str(rewards.xp) + " XP")
	if rewards.has("coins"):
		lines.append("+" + str(rewards.coins) + " 🪙")
	if rewards.has("gems"):
		lines.append("+" + str(rewards.gems) + " 💎")
	if lines.size() > 0:
		message_label.text = "Rewards:\n" + "\n".join(lines)
		message_timer = 4.0

func show_game_over(winner_text: String, rewards: Dictionary = {}) -> void:
	message_label.text = winner_text

func set_power_charge(value: float) -> void:
	if power_bar:
		power_bar.value = clamp(value, 0.0, 1.0)

func show_power_meter(visible_flag: bool) -> void:
	if power_bar:
		power_bar.visible = visible_flag
