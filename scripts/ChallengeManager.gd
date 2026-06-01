# ChallengeManager.gd
# Manages daily challenges — loading, tracking progress, claiming rewards
# Saves state to user://challenges.cfg
extends Node

const SAVE_PATH: String = "user://challenges.cfg"
const ChallengeData = preload("res://scripts/ChallengeData.gd")

# Current challenge tracking state
var daily_date_key: String = ""
var challenge_ids: Array[int] = []
var challenge_progress: Dictionary = {}  # challenge_id -> current_count (int)
var challenge_claimed: Dictionary = {}   # challenge_id -> bool
var last_completed_date: String = ""

# Signals
signal challenge_progress_updated(challenge_id: int, current: int, target: int)
signal challenge_completed(challenge_id: int, reward_coins: int, reward_gems: int)

func _ready() -> void:
	load_data()
	_check_daily_reset()
	_connect_event_bus()

func _connect_event_bus() -> void:
	# Rally length is reported externally via report_rally_length() from Main.gd —
	# no per-hit listener needed here.
	EventBus.match_ended.connect(_on_match_ended)
	EventBus.point_scored.connect(_on_point_scored)

func _on_match_ended(winner_id: int, _score: Dictionary) -> void:
	# Track matches_played
	for cid in challenge_ids:
		var chall = ChallengeData.get_challenge(cid)
		if chall == null:
			continue
		if challenge_claimed.get(cid, false):
			continue
		
		match chall.type:
			"matches_played":
				var current: int = challenge_progress.get(cid, 0)
				challenge_progress[cid] = current + 1
				_check_progress(cid)

func _on_point_scored(player_id: int, _new_score: int) -> void:
	if player_id != 0:
		return
	
	for cid in challenge_ids:
		var chall = ChallengeData.get_challenge(cid)
		if chall == null:
			continue
		if challenge_claimed.get(cid, false):
			continue
		
		match chall.type:
			"total_points":
				var current: int = challenge_progress.get(cid, 0)
				challenge_progress[cid] = current + 1
				_check_progress(cid)
			_:
				pass

# Called externally when a rally ends with a specific shot type that won the point
func report_rally_won(shot_type: String) -> void:
	for cid in challenge_ids:
		var chall = ChallengeData.get_challenge(cid)
		if chall == null:
			continue
		if challenge_claimed.get(cid, false):
			continue
		
		var matched: bool = false
		match chall.type:
			"dink_wins":
				matched = (shot_type == "dink")
			"lob_wins":
				matched = (shot_type == "lob")
			"volley_wins":
				matched = (shot_type == "volley")
			"drive_wins":
				matched = (shot_type == "drive")
			_:
				pass
		
		if matched:
			var current: int = challenge_progress.get(cid, 0)
			challenge_progress[cid] = current + 1
			_check_progress(cid)

# Called externally when a long rally happens
func report_rally_length(length: int) -> void:
	for cid in challenge_ids:
		var chall = ChallengeData.get_challenge(cid)
		if chall == null:
			continue
		if challenge_claimed.get(cid, false):
			continue
		
		match chall.type:
			"rally_length":
				if length >= chall.target:
					var current: int = challenge_progress.get(cid, 0)
					if current < chall.target:
						challenge_progress[cid] = chall.target
						_check_progress(cid)
			_:
				pass

# Called externally when player scores aces
func report_ace() -> void:
	for cid in challenge_ids:
		var chall = ChallengeData.get_challenge(cid)
		if chall == null:
			continue
		if challenge_claimed.get(cid, false):
			continue
		
		match chall.type:
			"aces":
				var current: int = challenge_progress.get(cid, 0)
				challenge_progress[cid] = current + 1
				_check_progress(cid)
			_:
				pass

func _check_progress(challenge_id: int) -> void:
	var chall = ChallengeData.get_challenge(challenge_id)
	if chall == null:
		return
	
	var current: int = challenge_progress.get(challenge_id, 0)
	var reached_target: bool = current >= chall.target
	
	challenge_progress_updated.emit(challenge_id, min(current, chall.target), chall.target)
	
	if reached_target and not challenge_claimed.get(challenge_id, false):
		challenge_completed.emit(challenge_id, chall.reward_coins, chall.reward_gems)

func get_daily_challenges() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cid in challenge_ids:
		var chall = ChallengeData.get_challenge(cid)
		if chall == null:
			continue
		result.append({
			"id": chall.id,
			"name": chall.name,
			"description": chall.description,
			"type": chall.type,
			"target": chall.target,
			"current": challenge_progress.get(cid, 0),
			"claimed": challenge_claimed.get(cid, false),
			"reward_coins": chall.reward_coins,
			"reward_gems": chall.reward_gems
		})
	return result

func get_progress(challenge_id: int) -> Dictionary:
	var chall = ChallengeData.get_challenge(challenge_id)
	if chall == null:
		return {"current": 0, "target": 0}
	return {
		"current": challenge_progress.get(challenge_id, 0),
		"target": chall.target
	}

func claim_reward(challenge_id: int) -> bool:
	if challenge_claimed.get(challenge_id, false):
		return false
	
	var chall = ChallengeData.get_challenge(challenge_id)
	if chall == null:
		return false
	
	var current: int = challenge_progress.get(challenge_id, 0)
	if current < chall.target:
		return false
	
	challenge_claimed[challenge_id] = true
	PlayerData.add_coins(chall.reward_coins)
	PlayerData.add_gems(chall.reward_gems)
	save()
	return true

func is_claimed(challenge_id: int) -> bool:
	return challenge_claimed.get(challenge_id, false)

func is_completed(challenge_id: int) -> bool:
	var chall = ChallengeData.get_challenge(challenge_id)
	if chall == null:
		return false
	var current: int = challenge_progress.get(challenge_id, 0)
	return current >= chall.target

func _check_daily_reset() -> void:
	var today_key: String = _get_date_key()
	if daily_date_key != today_key:
		reset_daily()

func _get_date_key() -> String:
	var date_dict = Time.get_date_dict_from_system()
	return str(date_dict.year) + "-" + str(date_dict.month) + "-" + str(date_dict.day)

func reset_daily() -> void:
	daily_date_key = _get_date_key()
	challenge_ids = ChallengeData.get_daily_challenge_ids(daily_date_key)
	challenge_progress.clear()
	challenge_claimed.clear()
	for cid in challenge_ids:
		challenge_progress[cid] = 0
		challenge_claimed[cid] = false
	save()

func save() -> void:
	var config = ConfigFile.new()
	
	config.set_value("daily", "date_key", daily_date_key)
	config.set_value("daily", "challenge_ids", challenge_ids)
	
	# Save progress as individual values
	for cid in challenge_ids:
		config.set_value("progress", str(cid), challenge_progress.get(cid, 0))
		config.set_value("claimed", str(cid), challenge_claimed.get(cid, false))
	
	config.save(SAVE_PATH)

func load_data() -> void:
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)
	if err != OK:
		reset_daily()
		return
	
	daily_date_key = config.get_value("daily", "date_key", "")
	challenge_ids = config.get_value("daily", "challenge_ids", [])
	
	# Load progress
	for cid in challenge_ids:
		challenge_progress[cid] = config.get_value("progress", str(cid), 0)
		challenge_claimed[cid] = config.get_value("claimed", str(cid), false)
	
	# If challenge_ids is empty (first load), reset
	if challenge_ids.is_empty():
		reset_daily()
