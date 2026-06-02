# TouchControls.gd
# On-screen mobile controls overlay — virtual D-pad on the left for movement,
# shot type buttons on the right for swing selection, and a SERVE button that
# appears only while the player is about to serve.
extends CanvasLayer

signal serve_pressed
signal lob_pressed
signal drive_pressed
signal dink_pressed
# Movement direction, normalized in screen-space; (-1, 0) = left, (0, -1) = up (toward net).
signal move_input(direction: Vector2)

@onready var btn_serve: Button = $ServeButton
@onready var btn_lob: Button = $LobButton
@onready var btn_drive: Button = $DriveButton
@onready var btn_dink: Button = $DinkButton
@onready var btn_up: Button = $DPad/Up
@onready var btn_down: Button = $DPad/Down
@onready var btn_left: Button = $DPad/Left
@onready var btn_right: Button = $DPad/Right

func _ready() -> void:
	btn_serve.pressed.connect(func(): serve_pressed.emit())
	btn_lob.pressed.connect(func(): lob_pressed.emit())
	btn_drive.pressed.connect(func(): drive_pressed.emit())
	btn_dink.pressed.connect(func(): dink_pressed.emit())
	show_shot_buttons(false)

func _process(_delta: float) -> void:
	var dir := Vector2.ZERO
	if btn_up.button_pressed:
		dir.y -= 1.0
	if btn_down.button_pressed:
		dir.y += 1.0
	if btn_left.button_pressed:
		dir.x -= 1.0
	if btn_right.button_pressed:
		dir.x += 1.0
	move_input.emit(dir)

# Toggle between SERVE mode and rally-shot mode.
func show_serve_button(visible_flag: bool) -> void:
	btn_serve.visible = visible_flag

func show_shot_buttons(visible_flag: bool) -> void:
	btn_lob.visible = visible_flag
	btn_drive.visible = visible_flag
	btn_dink.visible = visible_flag
