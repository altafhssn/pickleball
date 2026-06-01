# ChallengeData.gd
# Defines daily challenge structures and provides static challenge data
extends RefCounted

# Challenge definition structure
class Challenge:
	var id: int
	var name: String
	var description: String
	var type: String       # 'dink_wins', 'lob_wins', 'aces', 'rally_length', 'matches_played', 'volley_wins'
	var target: int        # Count to achieve
	var reward_coins: int
	var reward_gems: int
	
	func _init(p_id: int, p_name: String, p_desc: String, p_type: String, p_target: int, p_reward_coins: int, p_reward_gems: int):
		id = p_id
		name = p_name
		description = p_desc
		type = p_type
		target = p_target
		reward_coins = p_reward_coins
		reward_gems = p_reward_gems

# All available challenges
static func get_all_challenges() -> Array:
	return [
		Challenge.new(1, "Dink Master", "Win 5 rallies with a dink shot", "dink_wins", 5, 50, 1),
		Challenge.new(2, "Lob Expert", "Win 3 rallies with a lob shot", "lob_wins", 3, 50, 1),
		Challenge.new(3, "Ace Service", "Hit 2 unreturnable serves (aces)", "aces", 2, 75, 2),
		Challenge.new(4, "Endurance Rally", "Survive a rally of 10+ hits", "rally_length", 10, 40, 1),
		Challenge.new(5, "Match Player", "Play 3 matches", "matches_played", 3, 60, 1),
		Challenge.new(6, "Volley King", "Win 5 rallies with volley shots", "volley_wins", 5, 50, 1),
		Challenge.new(7, "Point Collector", "Score 15 total points across matches", "total_points", 15, 75, 2),
		Challenge.new(8, "Perfect Rally", "Win a rally with a drive shot", "drive_wins", 3, 40, 1),
	]

# Get challenge by ID
static func get_challenge(id: int) -> Challenge:
	for c in get_all_challenges():
		if c.id == id:
			return c
	return null

# Returns 3 random challenges for the day (seeded by date for consistent daily rotation)
static func get_daily_challenge_ids(date_key: String) -> Array[int]:
	var all_challs: Array = get_all_challenges()
	var seed_val: int = abs(hash(date_key))
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val
	
	# Pick 3 unique challenges using seeded RNG
	var picked: Array[int] = []
	var all_copy: Array = all_challs.duplicate()
	
	# Manual shuffle using seeded RNG
	for i in range(all_copy.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var temp = all_copy[i]
		all_copy[i] = all_copy[j]
		all_copy[j] = temp
	
	for i in range(min(3, all_copy.size())):
		picked.append(all_copy[i].id)
	
	return picked
