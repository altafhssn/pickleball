# TournamentUI.gd
# Controls the Tournament UI scene — bracket visualization, round display, play button
extends CanvasLayer

signal tournament_closed
signal play_tournament_round(opponent_name: String, difficulty: int)

# Node references
@onready var title_label: Label = $TournamentPanel/TitleLabel
@onready var round_label: Label = $TournamentPanel/RoundLabel
@onready var opponent_label: Label = $TournamentPanel/OpponentLabel
@onready var difficulty_label: Label = $TournamentPanel/DifficultyLabel
@onready var play_button: Button = $TournamentPanel/PlayButton
@onready var back_button: Button = $TournamentPanel/BackButton
@onready var status_label: Label = $TournamentPanel/StatusLabel
@onready var bracket_container: VBoxContainer = $TournamentPanel/BracketContainer
@onready var prize_label: Label = $TournamentPanel/PrizeLabel

var tournament_manager: Node = null
var _pending_manager: Node = null

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	play_button.pressed.connect(_on_play_pressed)
	if _pending_manager != null:
		_do_setup(_pending_manager)
		_pending_manager = null

func setup(manager: Node) -> void:
	if not is_inside_tree():
		_pending_manager = manager
		return
	_do_setup(manager)

func _do_setup(manager: Node) -> void:
	tournament_manager = manager
	if tournament_manager == null:
		return
	
	# Connect to tournament signals
	if tournament_manager.has_signal("tournament_round_won"):
		tournament_manager.tournament_round_won.connect(_on_round_won)
	if tournament_manager.has_signal("tournament_won"):
		tournament_manager.tournament_won.connect(_on_tournament_won)
	if tournament_manager.has_signal("tournament_lost"):
		tournament_manager.tournament_lost.connect(_on_tournament_lost)
	
	_refresh_ui()

func _refresh_ui() -> void:
	if tournament_manager == null:
		return
	
	_update_bracket()
	
	if not tournament_manager.tournament_active and tournament_manager.matches_won_in_tournament == 0 and not tournament_manager.has_lost:
		# Not started yet — show start prompt
		title_label.text = "🏆 Tournament"
		round_label.text = "8-Player Single Elimination"
		opponent_label.text = "Ready to compete?"
		difficulty_label.text = ""
		play_button.text = "▶ Start Tournament"
		play_button.disabled = false
		status_label.text = "Win 3 rounds to become champion!"
		prize_label.text = "🥇 Prize: 200 🪙 + 5 💎"
		return
	
	if tournament_manager.has_lost:
		# Tournament lost
		title_label.text = "🏆 Tournament"
		round_label.text = "Eliminated!"
		opponent_label.text = "Better luck next time!"
		difficulty_label.text = ""
		play_button.text = "▶ New Tournament"
		play_button.disabled = false
		status_label.text = "You earned 50 🪙 participation reward"
		prize_label.text = "Participation: 50 🪙"
		return
	
	if tournament_manager.matches_won_in_tournament >= 3:
		# Won tournament
		title_label.text = "🏆 Tournament Champion!"
		round_label.text = "You won it all!"
		opponent_label.text = "CHAMPION!"
		difficulty_label.text = ""
		play_button.text = "▶ New Tournament"
		play_button.disabled = false
		status_label.text = "Congratulations! You are the champion!"
		prize_label.text = "🏆 Prize: 200 🪙 + 5 💎"
		return
	
	# Active tournament
	var round_name: String = tournament_manager.get_current_round_name()
	var opponent_name: String = tournament_manager.get_current_opponent()
	
	title_label.text = "🏆 Tournament"
	round_label.text = round_name
	
	if opponent_name != "":
		opponent_label.text = "vs " + opponent_name
	else:
		opponent_label.text = "vs Unknown"
	
	match tournament_manager.current_round:
		0:
			difficulty_label.text = "Difficulty: Beginner"
		1:
			difficulty_label.text = "Difficulty: Casual"
		2:
			difficulty_label.text = "Difficulty: Pro"
	
	play_button.text = "▶ Play Round"
	play_button.disabled = false
	
	# Show round prize
	match tournament_manager.current_round:
		0:
			status_label.text = "Win this round to advance to Semi-finals!"
			prize_label.text = "Next: Semi-finals"
		1:
			status_label.text = "Win this round to advance to the Final!"
			prize_label.text = "Next: Championship Final"
		2:
			status_label.text = "Win this match to become the champion!"
			prize_label.text = "🏆 Grand Prize: 200 🪙 + 5 💎"

func _update_bracket() -> void:
	# Clear existing bracket labels
	for child in bracket_container.get_children():
		child.queue_free()
	
	var bracket_info: Array[Dictionary] = []
	if tournament_manager != null and tournament_manager.has_method("get_bracket_status"):
		bracket_info = tournament_manager.get_bracket_status()
	
	if bracket_info.is_empty():
		# Default bracket display
		var bracket_data = [
			{"round": 0, "name": "Quarter-finals", "status": "locked", "opponent": "---"},
			{"round": 1, "name": "Semi-finals", "status": "locked", "opponent": "---"},
			{"round": 2, "name": "Final", "status": "locked", "opponent": "---"}
		]
		
		# If tournament is active or completed, fill in real data
		if tournament_manager != null:
			if tournament_manager.tournament_active or tournament_manager.matches_won_in_tournament > 0 or tournament_manager.has_lost:
				for i in range(3):
					var names_pool = tournament_manager.opponent_names_pool
					if i < names_pool.size():
						bracket_data[i]["opponent"] = names_pool[i]
					if i < tournament_manager.current_round:
						bracket_data[i]["status"] = "won"
					elif i == tournament_manager.current_round:
						if tournament_manager.has_lost:
							bracket_data[i]["status"] = "lost"
						elif tournament_manager.tournament_active:
							bracket_data[i]["status"] = "available"
		
		bracket_info = bracket_data
	
	for round_info in bracket_info:
		var round_entry = Label.new()
		var status_icon: String = ""
		match round_info.get("status", ""):
			"won":
				status_icon = "✅ "
			"lost":
				status_icon = "❌ "
			"available":
				status_icon = "▶ "
			_:
				status_icon = "🔒 "
		
		var diff_text: String = ""
		if round_info.has("difficulty"):
			diff_text = " (" + round_info["difficulty"] + ")"
		
		round_entry.text = status_icon + round_info.get("name", "") + ": vs " + round_info.get("opponent", "???") + diff_text
		round_entry.theme_override_font_sizes/font_size = 16
		round_entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bracket_container.add_child(round_entry)

func _on_play_pressed() -> void:
	if tournament_manager == null:
		return
	
	if not tournament_manager.tournament_active and tournament_manager.matches_won_in_tournament == 0 and not tournament_manager.has_lost:
		# Start new tournament
		tournament_manager.start_tournament()
		_refresh_ui()
		# Auto-play the first round
		var opponent_name: String = tournament_manager.get_current_opponent()
		var difficulty: int = tournament_manager.get_current_difficulty()
		play_tournament_round.emit(opponent_name, difficulty)
	elif tournament_manager.matches_won_in_tournament >= 3 or tournament_manager.has_lost:
		# Start a new tournament
		tournament_manager.start_tournament()
		_refresh_ui()
		var opponent_name: String = tournament_manager.get_current_opponent()
		var difficulty: int = tournament_manager.get_current_difficulty()
		play_tournament_round.emit(opponent_name, difficulty)
	else:
		# Play current round
		var opponent_name: String = tournament_manager.get_current_opponent()
		var difficulty: int = tournament_manager.get_current_difficulty()
		play_tournament_round.emit(opponent_name, difficulty)

func _on_round_won(round_name: String) -> void:
	_refresh_ui()

func _on_tournament_won(prize_coins: int, prize_gems: int) -> void:
	_refresh_ui()

func _on_tournament_lost(round_name: String) -> void:
	_refresh_ui()

func _on_back_pressed() -> void:
	tournament_closed.emit()
	queue_free()
