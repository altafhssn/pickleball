# HUDController.gd
# Controls the HUD CanvasLayer — score display, serve indicator, gesture guide
extends CanvasLayer

@onready var score_label: RichTextLabel = $ScoreLabel
@onready var serve_label: Label = $ServeLabel
@onready var message_label: Label = $MessageLabel
@onready var power_bar: ProgressBar = $PowerIndicator
@onready var gesture_guide: Label = $GestureGuide

var message_timer: float = 0.0
# Gesture guide fades out after a few seconds so it doesn't clutter play.
var guide_timer: float = 0.0

func _ready():
	_set_score_bbcode(0, 0)
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
			message_label.modulate = Color(1, 1, 1, 1)
	if guide_timer > 0:
		guide_timer -= delta
		if guide_timer <= 0:
			gesture_guide.text = ""

const PLAYER_COLOR := Color(0.27, 0.53, 1.0)   # Blue — matches the player character
const OPPONENT_COLOR := Color(1.0, 0.5, 0.2)   # Orange — matches the AI character

func update_score(player_score: int, opponent_score: int) -> void:
	_set_score_bbcode(player_score, opponent_score)

func _set_score_bbcode(player_score: int, opponent_score: int) -> void:
	score_label.text = "[center][color=#4488ff]YOU %d[/color]  –  [color=#ff8033]AI %d[/color][/center]" % [player_score, opponent_score]

func show_serve_indicator(text: String) -> void:
	serve_label.text = text

func show_gesture_guide(visible_flag: bool) -> void:
	if visible_flag:
		gesture_guide.text = "Pick your shot EARLY while the ball comes to you — earlier = better!\nSPACE/tap = Drive · W/double-tap = Lob · S = Dink"
		guide_timer = 10.0
	else:
		gesture_guide.text = ""
		guide_timer = 0.0

func show_message(text: String, color: Color = Color(1, 1, 1, 1)) -> void:
	message_label.text = text
	message_label.modulate = color
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
