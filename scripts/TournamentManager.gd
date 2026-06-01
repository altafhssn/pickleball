# TournamentManager.gd
# Manages an 8-player single-elimination bracket with CPU opponents
# Uses AIManager with increasing difficulty per round
extends Node

# Bracket round names
const ROUND_NAMES: Dictionary = {
	0: "Quarter-finals",
	1: "Semi-finals",
	2: "Final"
}

# Round to AI difficulty mapping
const ROUND_DIFFICULTY: Dictionary = {
	0: 0,  # AIManager.Difficulty.BEGINNER
	1: 1,  # AIManager.Difficulty.CASUAL
	2: 2   # AIManager.Difficulty.PRO
}

# Prize rewards
const WINNER_COINS: int = 200
const WINNER_GEMS: int = 5
const PARTICIPATION_COINS: int = 50

# Current tournament state
var tournament_active: bool = false
var current_round: int = 0  # 0=quarter, 1=semi, 2=final
var matches_won_in_tournament: int = 0
var opponent_names_pool: Array[String] = []
var player_bracket_position: int = 0  # Which slot in the bracket (0-7)
var has_lost: bool = false
var prizes_claimed: bool = false

# Signal emitted when the player wins a round
signal tournament_round_won(round_name: String)
# Signal emitted when the player wins the entire tournament
signal tournament_won(prize_coins: int, prize_gems: int)
# Signal emitted when the player loses any round
signal tournament_lost(round_name: String)

func _ready() -> void:
	_populate_opponent_names()

func _populate_opponent_names() -> void:
	opponent_names_pool = []
	for i in range(7):
		opponent_names_pool.append("AI Bot #" + str(i + 1))

func start_tournament() -> void:
	tournament_active = true
	current_round = 0
	matches_won_in_tournament = 0
	has_lost = false
	prizes_claimed = false
	_populate_opponent_names()
	# Randomize opponent pool order
	opponent_names_pool.shuffle()
	player_bracket_position = randi() % 8

func get_current_opponent() -> String:
	if not tournament_active or has_lost:
		return ""
	# Pick opponent based on current round
	var opponent_index: int = current_round
	if opponent_index < opponent_names_pool.size():
		return opponent_names_pool[opponent_index]
	return "AI Bot #" + str(current_round + 1)

func get_current_round_name() -> String:
	if not tournament_active:
		return ""
	return ROUND_NAMES.get(current_round, "Unknown Round")

func get_current_difficulty() -> int:
	return ROUND_DIFFICULTY.get(current_round, 0)

func record_win() -> void:
	if not tournament_active or has_lost:
		return
	
	matches_won_in_tournament += 1
	var round_name: String = ROUND_NAMES.get(current_round, "")
	tournament_round_won.emit(round_name)
	
	if current_round >= 2:
		# Won the tournament!
		_end_tournament()
	else:
		# Advance to next round
		current_round += 1

func record_loss() -> void:
	if not tournament_active:
		return
	has_lost = true
	tournament_active = false
	PlayerData.add_coins(PARTICIPATION_COINS)
	var round_name: String = ROUND_NAMES.get(current_round, "")
	tournament_lost.emit(round_name)

func _end_tournament() -> void:
	tournament_active = false
	prizes_claimed = true
	PlayerData.add_coins(WINNER_COINS)
	PlayerData.add_gems(WINNER_GEMS)
	tournament_won.emit(WINNER_COINS, WINNER_GEMS)

func is_tournament_complete() -> bool:
	return not tournament_active and (matches_won_in_tournament > 0 or has_lost)

func get_prize() -> Dictionary:
	if matches_won_in_tournament >= 3:
		return {"coins": WINNER_COINS, "gems": WINNER_GEMS, "participation": false}
	elif matches_won_in_tournament > 0:
		return {"coins": PARTICIPATION_COINS, "gems": 0, "participation": true}
	return {"coins": 0, "gems": 0, "participation": false}

func get_bracket_status() -> Array[Dictionary]:
	# Returns info about each round for UI display
	var status: Array[Dictionary] = []
	for round_idx in range(3):
		var round_name: String = ROUND_NAMES.get(round_idx, "")
		var round_info: Dictionary = {
			"round": round_idx,
			"name": round_name,
			"status": "locked"  # locked, available, won, lost
		}
		if round_idx < current_round:
			round_info["status"] = "won"
		elif round_idx == current_round and not has_lost and tournament_active:
			round_info["status"] = "available"
		elif has_lost and round_idx == current_round:
			round_info["status"] = "lost"
		
		var opponent_name: String = ""
		if round_idx < opponent_names_pool.size():
			opponent_name = opponent_names_pool[round_idx]
		else:
			opponent_name = "AI Bot #" + str(round_idx + 1)
		round_info["opponent"] = opponent_name
		
		# Difficulty label
		match round_idx:
			0:
				round_info["difficulty"] = "Beginner"
			1:
				round_info["difficulty"] = "Casual"
			2:
				round_info["difficulty"] = "Pro"
		
		status.append(round_info)
	return status
