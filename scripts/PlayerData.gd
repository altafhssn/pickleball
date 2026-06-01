# PlayerData.gd
# Singleton autoload for player progression — saves/loads to user://player_data.cfg
extends Node

# === LEVEL XP TABLE ===
# Level 1 = 0, then each level's total XP threshold
const XP_TABLE: Dictionary = {
	1: 0,
	2: 100,
	3: 250,
	4: 500,
	5: 1000,
	6: 1800,
	7: 2800,
	8: 4000,
	9: 5500,
	10: 7500,
	11: 10000,
	12: 12500,
	13: 15000,
	14: 17500,
	15: 20000,
	16: 22500,
	17: 25000,
	18: 27500,
	19: 30000,
	20: 32500,
}
const XP_PER_LEVEL_AFTER_TABLE: int = 2500

# === LEVEL UNLOCKS ===
const LEVEL_UNLOCKS: Dictionary = {
	1: ["quick", "practice"],
	3: ["ranked"],
	5: ["shop"],
	7: ["doubles"],
	10: ["events", "tournaments"],
	12: ["erne_shot"],
	15: ["atp_shot"],
}

# === MATCH REWARDS ===
const MIN_XP_PER_MATCH: int = 15
const MAX_XP_PER_MATCH: int = 50
const MIN_COINS_PER_MATCH: int = 10
const MAX_COINS_PER_MATCH: int = 30

# === SAVE PATH ===
const SAVE_PATH: String = "user://player_data.cfg"

# === PERSISTED FIELDS ===
var player_level: int = 1
var xp: int = 0
var coins: int = 0
var gems: int = 0
var rank_tier: int = 0          # 0=unranked, 1=Bronze, 2=Silver, ...
var rank_mmr: int = 1000
var unlocked_paddles: Array = []  # Array of paddle int IDs
var unlocked_cosmetics: Array = []  # Array of cosmetic int IDs
var selected_paddle: int = 0
var matches_played: int = 0
var matches_won: int = 0
var total_xp_earned: int = 0

func _ready() -> void:
	load_data()

# === XP MANAGEMENT ===

func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	total_xp_earned += amount
	_check_level_up()
	save()

func _check_level_up() -> void:
	# xp is cumulative lifetime XP; level up while the next threshold is crossed.
	# Matches the cumulative model used by get_current_level_xp / get_level_progress.
	while player_level < 50 and xp >= get_xp_for_level(player_level + 1):
		player_level += 1
		EventBus.menu_navigated.emit("level_up", str(player_level))

func get_xp_for_level(level: int) -> int:
	if level <= 1:
		return 0
	if XP_TABLE.has(level):
		return XP_TABLE[level]
	# For levels beyond the table, each level costs more (cumulative)
	var base_level: int = XP_TABLE.keys()[-1]
	var base_xp: int = XP_TABLE[base_level]
	var extra_levels: int = level - base_level
	return base_xp + (extra_levels * XP_PER_LEVEL_AFTER_TABLE)

func get_current_level_xp() -> int:
	# XP progress within current level
	var current_threshold: int = get_xp_for_level(player_level)
	var next_threshold: int = get_xp_for_level(player_level + 1)
	return xp - current_threshold

func get_xp_to_next_level() -> int:
	var current_threshold: int = get_xp_for_level(player_level)
	var next_threshold: int = get_xp_for_level(player_level + 1)
	return next_threshold - current_threshold

func get_level_progress() -> float:
	# Returns 0.0 - 1.0 progress within the current level
	var current_threshold: int = get_xp_for_level(player_level)
	var next_threshold: int = get_xp_for_level(player_level + 1)
	var range_size: int = next_threshold - current_threshold
	if range_size <= 0:
		return 1.0
	return float(xp - current_threshold) / float(range_size)

# === COINS ===

func add_coins(amount: int) -> void:
	if amount <= 0:
		return
	coins += amount
	save()

func spend_coins(amount: int) -> bool:
	if amount <= 0:
		return false
	if coins < amount:
		return false
	coins -= amount
	save()
	return true

# === GEMS ===

func add_gems(amount: int) -> void:
	if amount <= 0:
		return
	gems += amount
	save()

func spend_gems(amount: int) -> bool:
	if amount <= 0:
		return false
	if gems < amount:
		return false
	gems -= amount
	save()
	return true

# === PADDLE MANAGEMENT ===

func unlock_paddle(id: int) -> void:
	if id in unlocked_paddles:
		return
	unlocked_paddles.append(id)
	save()

func is_paddle_unlocked(id: int) -> bool:
	return id in unlocked_paddles

func select_paddle(id: int) -> void:
	if id in unlocked_paddles:
		selected_paddle = id
		save()

func get_selected_paddle_id() -> int:
	return selected_paddle

# === COSMETICS ===

func unlock_cosmetic(id: int) -> void:
	if id in unlocked_cosmetics:
		return
	unlocked_cosmetics.append(id)
	save()

func is_cosmetic_unlocked(id: int) -> bool:
	return id in unlocked_cosmetics

# === LEVEL / RANK ===

func set_level(level: int) -> void:
	player_level = clamp(level, 1, 50)
	xp = get_xp_for_level(player_level)
	save()

# === MATCH REWARDS ===

func grant_match_rewards(perf_score: float) -> Dictionary:
	# perf_score: 0.0 (lost badly) to 1.0 (perfect)
	var perf: float = clampf(perf_score, 0.0, 1.0)
	
	var xp_reward: int = floori(MIN_XP_PER_MATCH + (MAX_XP_PER_MATCH - MIN_XP_PER_MATCH) * perf)
	var coin_reward: int = floori(MIN_COINS_PER_MATCH + (MAX_COINS_PER_MATCH - MIN_COINS_PER_MATCH) * perf)
	
	add_xp(xp_reward)
	add_coins(coin_reward)
	
	matches_played += 1
	save()
	
	return {"xp": xp_reward, "coins": coin_reward}

func grant_match_win() -> void:
	matches_won += 1
	save()

# === UNLOCKS CHECK ===

func is_mode_unlocked(mode: String) -> bool:
	var required_level: int = _get_unlock_level(mode)
	if required_level <= 0:
		return true  # Always unlocked
	return player_level >= required_level

func _get_unlock_level(mode: String) -> int:
	for level: int in LEVEL_UNLOCKS.keys():
		var unlocks: Array = LEVEL_UNLOCKS[level]
		if mode in unlocks:
			return level
	return -1

# === PERSISTENCE ===

func save() -> void:
	var config = ConfigFile.new()
	
	config.set_value("player", "player_level", player_level)
	config.set_value("player", "xp", xp)
	config.set_value("player", "coins", coins)
	config.set_value("player", "gems", gems)
	config.set_value("player", "rank_tier", rank_tier)
	config.set_value("player", "rank_mmr", rank_mmr)
	config.set_value("player", "unlocked_paddles", unlocked_paddles)
	config.set_value("player", "unlocked_cosmetics", unlocked_cosmetics)
	config.set_value("player", "selected_paddle", selected_paddle)
	config.set_value("player", "matches_played", matches_played)
	config.set_value("player", "matches_won", matches_won)
	config.set_value("player", "total_xp_earned", total_xp_earned)
	
	config.save(SAVE_PATH)

func load_data() -> void:
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)
	if err != OK:
		# No save file yet — use defaults
		reset()
		return
	
	player_level = config.get_value("player", "player_level", 1)
	xp = config.get_value("player", "xp", 0)
	coins = config.get_value("player", "coins", 0)
	gems = config.get_value("player", "gems", 0)
	rank_tier = config.get_value("player", "rank_tier", 0)
	rank_mmr = config.get_value("player", "rank_mmr", 1000)
	unlocked_paddles = config.get_value("player", "unlocked_paddles", [])
	unlocked_cosmetics = config.get_value("player", "unlocked_cosmetics", [])
	selected_paddle = config.get_value("player", "selected_paddle", 0)
	matches_played = config.get_value("player", "matches_played", 0)
	matches_won = config.get_value("player", "matches_won", 0)
	total_xp_earned = config.get_value("player", "total_xp_earned", 0)

func reset() -> void:
	player_level = 1
	xp = 0
	coins = 0
	gems = 0
	rank_tier = 0
	rank_mmr = 1000
	unlocked_paddles = []
	unlocked_cosmetics = []
	selected_paddle = 0
	matches_played = 0
	matches_won = 0
	total_xp_earned = 0
	save()
