# PaddleData.gd
# Static paddle definitions and stat lookup
extends RefCounted

# Rarity enum
enum Rarity { COMMON, RARE, EPIC, LEGENDARY }

# Paddle stat structure
struct PaddleDef:
	var id: int
	var name: String
	var power: int       # 0-100
	var control: int     # 0-100
	var spin: int        # 0-100
	var reach: int       # 0-100
	var rarity: Rarity
	var price_coins: int
	var price_gems: int

# Master paddle list — at least 8 paddles with tradeoffs
const PADDLES: Array = [
	# Starter paddle
	PaddleDef.new(0, "Starter Paddle", 30, 50, 30, 40, Rarity.COMMON, 0, 0),
	# Balanced
	PaddleDef.new(1, "All-Court Classic", 40, 50, 40, 45, Rarity.COMMON, 500, 0),
	# Power-focused
	PaddleDef.new(2, "Power Smasher", 75, 25, 30, 35, Rarity.RARE, 1500, 0),
	# Control-focused
	PaddleDef.new(3, "Precision Touch", 25, 80, 35, 40, Rarity.RARE, 1500, 0),
	# Spin-focused
	PaddleDef.new(4, "Spin Master Pro", 30, 35, 80, 40, Rarity.RARE, 2000, 0),
	# Reach-focused
	PaddleDef.new(5, "Long Reach Elite", 35, 40, 30, 80, Rarity.RARE, 2000, 0),
	# Epic: well-rounded high stats
	PaddleDef.new(6, "Tournament Ace", 55, 60, 55, 55, Rarity.EPIC, 5000, 50),
	# Epic: power/control hybrid
	PaddleDef.new(7, "Thunder Control", 65, 65, 40, 35, Rarity.EPIC, 6000, 60),
	# Legendary: best all-rounder
	PaddleDef.new(8, "Legendary Phantom", 80, 80, 70, 70, Rarity.LEGENDARY, 0, 500),
	# Legendary: specialist extreme
	PaddleDef.new(9, "Godhand Smash", 95, 15, 20, 30, Rarity.LEGENDARY, 0, 800),
]


# Returns a Dictionary mapping paddle_id -> paddle stats
static func get_all_paddle_stats() -> Dictionary:
	var result: Dictionary = {}
	for paddle: PaddleDef in PADDLES:
		result[paddle.id] = {
			"id": paddle.id,
			"name": paddle.name,
			"power": paddle.power,
			"control": paddle.control,
			"spin": paddle.spin,
			"reach": paddle.reach,
			"rarity": Rarity.keys()[paddle.rarity].to_lower(),
			"rarity_index": paddle.rarity,
			"price_coins": paddle.price_coins,
			"price_gems": paddle.price_gems,
		}
	return result


# Returns a Dictionary of stats for a specific paddle ID, or null if not found
static func get_paddle_stats(paddle_id: int) -> Dictionary:
	for paddle: PaddleDef in PADDLES:
		if paddle.id == paddle_id:
			return {
				"id": paddle.id,
				"name": paddle.name,
				"power": paddle.power,
				"control": paddle.control,
				"spin": paddle.spin,
				"reach": paddle.reach,
				"rarity": Rarity.keys()[paddle.rarity].to_lower(),
				"rarity_index": paddle.rarity,
				"price_coins": paddle.price_coins,
				"price_gems": paddle.price_gems,
			}
	return {}


# Returns paddle name for display
static func get_paddle_name(paddle_id: int) -> String:
	for paddle: PaddleDef in PADDLES:
		if paddle.id == paddle_id:
			return paddle.name
	return "Unknown"


# Returns total number of paddle definitions
static func get_paddle_count() -> int:
	return PADDLES.size()


# Returns color hex string for a given rarity index
static func get_rarity_color(rarity_index: int) -> String:
	match rarity_index:
		Rarity.COMMON:
			return "#aaaaaa"
		Rarity.RARE:
			return "#4488ff"
		Rarity.EPIC:
			return "#aa44ff"
		Rarity.LEGENDARY:
			return "#ffaa00"
		_:
			return "#ffffff"
