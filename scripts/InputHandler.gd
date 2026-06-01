# InputHandler.gd
# Touch input → shot type mapping
# Detects swipe gestures, taps, drags, and power shots
extends Node

# Gesture parameters — tuneable
@export var swipe_threshold: float = 30.0  # Minimum swipe distance in pixels
@export var tap_threshold: float = 15.0     # Max movement to count as tap
@export var tap_duration: float = 0.15      # Max seconds for tap
@export var double_tap_window: float = 0.3  # Max between taps for double-tap
@export var drag_hold_time: float = 0.3     # Hold time before drag mode

# Input state
enum InputState { IDLE, TOUCH_DOWN, SWIPE, DRAG, RELEASE }
var touch_state: InputState = InputState.IDLE
var touch_start_pos: Vector2 = Vector2.ZERO
var touch_start_time: float = 0.0
var touch_current_pos: Vector2 = Vector2.ZERO
var last_touch_time: float = 0.0
var last_touch_pos: Vector2 = Vector2.ZERO
var tap_count: int = 0
var drag_started: bool = false

# Swipe buffer for detecting direction
var swipe_buffer: Array[Vector2] = []
const SWIPE_BUFFER_SIZE: int = 5

# Current detected gesture (emitted each frame while active)
var current_gesture: String = ""
var gesture_strength: float = 1.0

func _ready():
	EventBus.frame_update.connect(_on_frame_update)

func _on_frame_update(_delta: float) -> void:
	pass  # Touch processing is in _input()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch_event(event)
	elif event is InputEventScreenDrag:
		_handle_drag_event(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)

# Desktop keyboard fallback so the game is playable without a touchscreen.
# Synthesizes the same swipe_detected / tap_detected events the touch path emits.
func _handle_key(event: InputEventKey) -> void:
	var center: Vector2 = Vector2(540, 960)
	match event.keycode:
		KEY_SPACE, KEY_UP, KEY_W:
			EventBus.swipe_detected.emit(Vector2(0, -200), 200.0)  # serve / lob
		KEY_DOWN, KEY_S:
			EventBus.swipe_detected.emit(Vector2(0, 200), 200.0)   # dink
		KEY_LEFT, KEY_A:
			EventBus.swipe_detected.emit(Vector2(-200, 0), 200.0)  # cross-court left
		KEY_RIGHT, KEY_D:
			EventBus.swipe_detected.emit(Vector2(200, 0), 200.0)   # cross-court right
		KEY_V:
			EventBus.tap_detected.emit(center)                     # volley
		KEY_P:
			EventBus.double_tap_detected.emit(center)              # power charge

func _handle_touch_event(event: InputEventScreenTouch) -> void:
	if event.pressed:
		# Touch down
		touch_state = InputState.TOUCH_DOWN
		touch_start_pos = event.position
		touch_current_pos = event.position
		touch_start_time = Time.get_ticks_msec() / 1000.0
		swipe_buffer.clear()
		drag_started = false
	else:
		# Touch released
		_release_detected(event.position)

func _handle_drag_event(event: InputEventScreenDrag) -> void:
	touch_current_pos = event.position
	swipe_buffer.append(event.relative)
	if swipe_buffer.size() > SWIPE_BUFFER_SIZE:
		swipe_buffer.pop_front()
	
	var elapsed: float = (Time.get_ticks_msec() / 1000.0) - touch_start_time
	var total_distance: float = touch_start_pos.distance_to(touch_current_pos)
	
	if total_distance > swipe_threshold and touch_state == InputState.TOUCH_DOWN:
		# Transition from touch-down to swipe
		touch_state = InputState.SWIPE
		_detect_swipe()
	elif elapsed > drag_hold_time and touch_state != InputState.SWIPE:
		# Held long enough to be a drag
		touch_state = InputState.DRAG
		if not drag_started:
			drag_started = true
			EventBus.drag_detected.emit(touch_start_pos, touch_current_pos)

func _release_detected(position: Vector2) -> void:
	var elapsed: float = (Time.get_ticks_msec() / 1000.0) - touch_start_time
	var total_distance: float = touch_start_pos.distance_to(position)
	var swipe_vector: Vector2 = position - touch_start_pos

	# Any release with sufficient cumulative motion should fire as a swipe,
	# regardless of whether the state machine landed in SWIPE or DRAG.
	# This keeps mouse-driven testing usable while preserving fast-flick swipes.
	if total_distance >= swipe_threshold:
		EventBus.swipe_detected.emit(swipe_vector, total_distance)
		# A held + dragged motion still gets a drag_detected so precision shots work.
		if touch_state == InputState.DRAG:
			EventBus.drag_detected.emit(touch_start_pos, position)
	else:
		match touch_state:
			InputState.TOUCH_DOWN:
				if elapsed < tap_duration:
					_handle_tap()
				else:
					EventBus.tap_detected.emit(position)
			InputState.SWIPE, InputState.DRAG:
				# Sub-threshold release — treat as tap.
				EventBus.tap_detected.emit(position)

	touch_state = InputState.IDLE

func _handle_tap() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	
	# Check double-tap
	if now - last_touch_time < double_tap_window:
		tap_count += 1
		if tap_count >= 2:
			EventBus.double_tap_detected.emit(touch_start_pos)
			tap_count = 0
	else:
		tap_count = 1
	
	last_touch_time = now
	last_touch_pos = touch_start_pos
	
	# Single tap = volley if ball is on player's side
	if tap_count == 1:
		EventBus.tap_detected.emit(touch_start_pos)

func _detect_swipe() -> void:
	# Calculate average velocity from buffer
	if swipe_buffer.size() < 2:
		return
	
	var total_velocity: Vector2 = Vector2.ZERO
	for v in swipe_buffer:
		total_velocity += v
	
	var avg_velocity: Vector2 = total_velocity / swipe_buffer.size()
	var distance: float = touch_start_pos.distance_to(touch_current_pos)
	gesture_strength = minf(distance / 200.0, 1.0)
	
	EventBus.swipe_detected.emit(avg_velocity, distance)

func _emit_swipe_result() -> void:
	var swipe_vector: Vector2 = touch_current_pos - touch_start_pos
	EventBus.swipe_detected.emit(swipe_vector, swipe_vector.length())

func get_swipe_direction_name(velocity: Vector2) -> String:
	if velocity.length() < swipe_threshold:
		return "tap"
	
	var angle: float = velocity.angle()
	# Convert to degrees and classify
	var deg: float = rad_to_deg(angle)
	
	if deg > -45 and deg <= 45:
		return "right"
	elif deg > 45 and deg <= 135:
		return "down"
	elif deg > -135 and deg <= -45:
		return "up"
	else:
		return "left"

func reset() -> void:
	touch_state = InputState.IDLE
	swipe_buffer.clear()
	tap_count = 0
	drag_started = false
