# EventBus.gd
# Global signal bus for cross-system communication
# Autoloaded via project.godot
extends Node

# Game State Signals
signal game_state_changed(from_state: String, to_state: String)
signal match_started(match_type: int)  # 0=quick, 1=ranked, 2=doubles, 3=practice
signal match_ended(winner_id: int, score: Dictionary)
signal point_scored(player_id: int, new_score: int)

# Input Signals
signal swipe_detected(direction: Vector2, velocity: Vector2)
signal tap_detected(position: Vector2)
signal drag_detected(from: Vector2, to: Vector2)
signal double_tap_detected(position: Vector2)
signal power_shot_charged(charge_level: float)

# Ball Signals
signal ball_served(from_position: Vector3, target: Vector3)
signal ball_hit(shooter_id: int, shot_type: int, force: float)
signal ball_bounced(position: Vector3, side: int)  # side: 0=player, 1=opponent
signal ball_out_of_bounds
signal ball_net_hit
signal ball_landed_in_kitchen

# Match Signals
signal rally_began
signal rally_ended(winner_id: int, reason: String)
signal two_bounce_rule_ready
signal kitchen_violation(player_id: int)
signal fault_called(player_id: int, reason: String)

# Player Signals
signal player_moved(player_id: int, position: Vector3)
signal player_ready_changed(player_id: int, ready: bool)
signal player_disconnected(player_id: int)
signal player_reconnected(player_id: int)

# UI Signals
signal menu_navigated(from_screen: String, to_screen: String)
signal settings_changed(setting: String, value: Variant)
signal matchmaking_started(queue_type: String)
signal matchmaking_cancelled
signal matchmaking_found(opponent_name: String, mmr: int)

# System Signals
signal game_paused
signal game_resumed
signal frame_update(delta: float)
signal physics_update(delta: float)
