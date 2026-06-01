# ChallengeUI.gd
# Controls the Challenges UI scene — list of daily challenges with progress bars
extends CanvasLayer

signal challenges_closed

# Node references
@onready var title_label: Label = $ChallengePanel/TitleLabel
@onready var challenge_list: VBoxContainer = $ChallengePanel/ScrollContainer/ChallengeList
@onready var back_button: Button = $ChallengePanel/BackButton
@onready var reset_timer_label: Label = $ChallengePanel/ResetTimerLabel

var challenge_manager: Node = null
var _pending_manager: Node = null

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	if _pending_manager != null:
		_do_setup(_pending_manager)
		_pending_manager = null

func setup(manager: Node) -> void:
	if not is_inside_tree():
		_pending_manager = manager
		return
	_do_setup(manager)

func _do_setup(manager: Node) -> void:
	challenge_manager = manager
	if challenge_manager == null:
		return
	
	if challenge_manager.has_signal("challenge_progress_updated"):
		challenge_manager.challenge_progress_updated.connect(_on_progress_updated)
	if challenge_manager.has_signal("challenge_completed"):
		challenge_manager.challenge_completed.connect(_on_challenge_completed)
	
	_refresh_challenges()

func _refresh_challenges() -> void:
	if challenge_manager == null:
		return
	
	# Clear existing entries
	for child in challenge_list.get_children():
		child.queue_free()
	
	var challenges: Array[Dictionary] = challenge_manager.get_daily_challenges()
	
	if challenges.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No challenges available today!"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.theme_override_font_sizes/font_size = 18
		challenge_list.add_child(empty_label)
		return
	
	for chall_data in challenges:
		var entry = _create_challenge_entry(chall_data)
		challenge_list.add_child(entry)
	
	_update_reset_timer()

func _create_challenge_entry(data: Dictionary) -> Node:
	var container = VBoxContainer.new()
	container.custom_minimum_size = Vector2(0, 100)
	container.theme_override_constants/separation = 4
	
	# Name line
	var name_label = Label.new()
	name_label.text = data.get("name", "Challenge")
	name_label.theme_override_font_sizes/font_size = 18
	container.add_child(name_label)
	
	# Description line
	var desc_label = Label.new()
	desc_label.text = data.get("description", "")
	desc_label.theme_override_font_sizes/font_size = 14
	desc_label.modulate = Color(0.7, 0.7, 0.7)
	container.add_child(desc_label)
	
	# Progress bar container
	var progress_hbox = HBoxContainer.new()
	progress_hbox.custom_minimum_size = Vector2(0, 30)
	
	var current: int = data.get("current", 0)
	var target: int = data.get("target", 1)
	var claimed: bool = data.get("claimed", false)
	
	# Progress bar (using TextureProgressBar would need texture, use plain color approach)
	var progress_bar = ColorRect.new()
	progress_bar.custom_minimum_size = Vector2(400, 24)
	progress_bar.color = Color(0.15, 0.15, 0.2)
	progress_bar.size_flags_horizontal = SIZE_EXPAND_FILL
	
	# Fill bar
	var fill_bar = ColorRect.new()
	var progress_ratio: float = float(min(current, target)) / float(target) if target > 0 else 0.0
	fill_bar.custom_minimum_size = Vector2(400 * progress_ratio, 20)
	fill_bar.color = Color(0.2, 0.8, 0.3) if not claimed else Color(0.5, 0.5, 0.5)
	fill_bar.position = Vector2(2, 2)
	fill_bar.size_flags_horizontal = SIZE_SHRINK_BEGIN
	progress_bar.add_child(fill_bar)
	
	# Progress text overlay
	var progress_text = Label.new()
	progress_text.text = str(min(current, target)) + " / " + str(target)
	progress_text.theme_override_font_sizes/font_size = 14
	progress_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	progress_text.custom_minimum_size = Vector2(400, 24)
	progress_bar.add_child(progress_text)
	
	progress_hbox.add_child(progress_bar)
	
	# Claim button or checkmark
	if claimed:
		var claimed_label = Label.new()
		claimed_label.text = "✅ Claimed"
		claimed_label.theme_override_font_sizes/font_size = 14
		claimed_label.modulate = Color(0.5, 0.8, 0.5)
		progress_hbox.add_child(claimed_label)
	elif current >= target:
		var claim_btn = Button.new()
		claim_btn.text = "Claim " + str(data.get("reward_coins", 0)) + "🪙"
		claim_btn.theme_override_font_sizes/font_size = 14
		var cid = data.get("id", -1)
		claim_btn.pressed.connect(_on_claim_pressed.bind(cid, claim_btn))
		progress_hbox.add_child(claim_btn)
	else:
		var pending_label = Label.new()
		pending_label.text = "In progress..."
		pending_label.theme_override_font_sizes/font_size = 14
		pending_label.modulate = Color(0.7, 0.7, 0.3)
		progress_hbox.add_child(pending_label)
	
	container.add_child(progress_hbox)
	
	# Separator
	var sep = ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(0.3, 0.3, 0.35)
	container.add_child(sep)
	
	return container

func _on_claim_pressed(challenge_id: int, button: Button) -> void:
	if challenge_manager == null:
		return
	
	var success: bool = challenge_manager.claim_reward(challenge_id)
	if success:
		button.text = "✅ Claimed!"
		button.disabled = true
		_refresh_challenges()

func _on_progress_updated(challenge_id: int, current: int, target: int) -> void:
	_refresh_challenges()

func _on_challenge_completed(challenge_id: int, reward_coins: int, reward_gems: int) -> void:
	_refresh_challenges()

func _update_reset_timer() -> void:
	# Calculate time until next daily reset (midnight)
	var date_dict = Time.get_date_dict_from_system()
	var next_midnight = Time.get_unix_time_from_datetime_dict({
		"year": date_dict.year,
		"month": date_dict.month,
		"day": date_dict.day + 1,
		"hour": 0,
		"minute": 0,
		"second": 0
	})
	var now = Time.get_unix_time_from_system()
	var seconds_left = int(next_midnight - now)
	
	var hours = seconds_left / 3600
	var minutes = (seconds_left % 3600) / 60
	
	reset_timer_label.text = "Resets in " + str(hours) + "h " + str(minutes) + "m"

func _on_back_pressed() -> void:
	challenges_closed.emit()
	queue_free()
