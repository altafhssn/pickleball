# GameState.gd
# State machine for match lifecycle: MENU → SERVE → PLAY → SCORE → GAME_OVER
extends Node

enum State {
	MENU,
	MATCHMAKING,
	SERVE_WAIT,       # Waiting for server to serve
	SERVE_ACTIVE,     # Serve gesture in progress
	PLAY,             # Rally in progress
	POINT_SCORED,     # Brief pause showing point
	GAME_OVER,        # Match ended
	PAUSED,
	REPLAY
}

var current_state: State = State.MENU
var previous_state: State = State.MENU

# State timing
var point_scored_timer: float = 0.0
const POINT_SCORED_DELAY: float = 2.0  # Show point for 2 seconds

func _ready():
	EventBus.game_paused.connect(_on_game_paused)
	EventBus.game_resumed.connect(_on_game_resumed)

func transition_to(new_state: State) -> void:
	if new_state == current_state:
		return
	
	var old_state: String = State.keys()[current_state]
	var new_state_name: String = State.keys()[new_state]
	
	previous_state = current_state
	current_state = new_state
	
	_on_exit_state(previous_state)
	_on_enter_state(new_state)
	
	EventBus.game_state_changed.emit(old_state, new_state_name)

func _on_exit_state(state: State) -> void:
	match state:
		State.POINT_SCORED:
			point_scored_timer = 0.0

func _on_enter_state(state: State) -> void:
	match state:
		State.SERVE_WAIT:
			# Reset ball position
			pass
		State.POINT_SCORED:
			point_scored_timer = 0.0

func _process(delta: float) -> void:
	match current_state:
		State.POINT_SCORED:
			point_scored_timer += delta
			if point_scored_timer >= POINT_SCORED_DELAY:
				# Automatically transition to next serve
				# Check if game is over
				transition_to(State.SERVE_WAIT)

func _on_game_paused() -> void:
	if current_state != State.PAUSED and current_state != State.MENU:
		previous_state = current_state
		current_state = State.PAUSED

func _on_game_resumed() -> void:
	if current_state == State.PAUSED:
		current_state = previous_state

func is_playing() -> bool:
	return current_state in [State.SERVE_WAIT, State.SERVE_ACTIVE, State.PLAY]

func can_serve() -> bool:
	return current_state == State.SERVE_WAIT

func is_rally_active() -> bool:
	return current_state == State.PLAY

func reset() -> void:
	current_state = State.MENU
	previous_state = State.MENU
	point_scored_timer = 0.0
