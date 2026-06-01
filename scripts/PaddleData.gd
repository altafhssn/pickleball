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
	PaddleDef{id=0, name="Starter Paddle", power=30, control=50, spin=30, reach=40, rarity=Rarity.COMMON, price_coins=0, price_gems=0},
	# Balanced
	PaddleDef{id=1, name="All-Court Classic", power=40, control=50, spin=40, reach=45, rarity=Rarity.COMMON, price_coins=500, price_gems=0},
	# Power-focused
	PaddleDef{id=2, name="Power Smasher", power=75, control=25, spin=30, reach=35, rarity=Rarity.RARE, price_coins=1500, price_gems=0},
	# Control-focused
	PaddleDef{id=3, name="Precision Touch", power=25, control=80, spin=35, reach=40, rarity=Rarity.RARE, price_coins=1500, price_gems=0},
	# Spin-focused
	PaddleDef{id=4, name="Spin Master Pro", power=30, control=35, spin=80, reach=40, rarity=Rarity.RARE, price_coins=2000, price_gems=0},
	# Reach-focused
	PaddleDef{id=5, name="Long Reach Elite", power=35, control=40, spin=30, reach=80, rarity=Rarity.RARE, price_coins=2000, price_gems=0},
	# Epic: well-rounded high stats
	PaddleDef{id=6, name="Tournament Ace", power=55, control=60, spin=55, reach=55, rarity=Rarity.EPIC, price_coins=5000, price_gems=50},
	# Epic: power/control hybrid
	PaddleDef{id=7, name="Thunder Control", power=65, control=65, spin=40, reach=35, rarity=Rarity.EPIC, price_coins=6000, price_gems=60},
	# Legendary: best all-rounder
	PaddleDef{id=8, name="Legendary Phantom", power=80, control=80, spin=70, reach=70, rarity=Rarity.LEGENDARY, price_coins=0, price_gems=500},
	# Legendary: specialist extreme
	PaddleDef{id=9, name="Godhand Smash", power=95, control=15, spin=20, reach=30, rarity=Rarity.LEGENDARY, price_coins=0, price_gems=800},
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
