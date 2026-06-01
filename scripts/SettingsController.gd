# SettingsController.gd
# Settings screen — volume controls, reset progress, controls guide
extends CanvasLayer

signal settings_closed

const SETTINGS_PATH: String = "user://settings.cfg"
const SFX_BUS: String = "SFX"
const MUSIC_BUS: String = "Music"
const MASTER_BUS: String = "Master"

@onready var master_slider: HSlider = $MasterSlider
@onready var master_value_label: Label = $MasterValueLabel
@onready var sfx_slider: HSlider = $SFXSlider
@onready var sfx_value_label: Label = $SFXValueLabel
@onready var music_slider: HSlider = $MusicSlider
@onready var music_value_label: Label = $MusicValueLabel
@onready var reset_button: Button = $ResetButton
@onready var back_button: Button = $BackButton
@onready var controls_label: Label = $ControlsLabel
@onready var confirm_panel: Panel = $ConfirmPanel
@onready var confirm_yes: Button = $ConfirmPanel/YesButton
@onready var confirm_no: Button = $ConfirmPanel/NoButton

func _ready() -> void:
	load_settings()
	_setup_ui()

func _setup_ui() -> void:
	# Connect slider signals
	master_slider.value_changed.connect(_on_master_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	music_slider.value_changed.connect(_on_music_changed)

	# Connect buttons
	back_button.pressed.connect(_on_back)
	reset_button.pressed.connect(_on_reset_pressed)
	confirm_yes.pressed.connect(_on_confirm_reset)
	confirm_no.pressed.connect(_on_cancel_reset)

	# Hide confirmation panel by default
	confirm_panel.visible = false

	# Set controls guide text
	controls_label.text = _get_controls_text()

func _get_controls_text() -> String:
	return """Controls Guide:
━━━━━━━━━━━━━━━━━━
⬆  Swipe Up       → Lob Shot
⬇  Swipe Down     → Dink Shot
⬅  Swipe Left     → Cross Court (Left)
➡  Swipe Right    → Cross Court (Right)
⚡  Tap (in air)   → Volley
🔥  Double Tap     → Power Charge
↔️  Drag           → Precision Shot

Serve: Swipe Up from ball position

Two-Bounce Rule:
Serve & return must bounce
before volleying."""

# === SLIDER HANDLERS ===

func _on_master_changed(value: float) -> void:
	var vol = _slider_to_db(value)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MASTER_BUS), vol)
	master_value_label.text = str(int(value))
	_save_setting("audio", "master_volume", int(value))

func _on_sfx_changed(value: float) -> void:
	var vol = _slider_to_db(value)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SFX_BUS), vol)
	sfx_value_label.text = str(int(value))
	_save_setting("audio", "sfx_volume", int(value))

func _on_music_changed(value: float) -> void:
	var vol = _slider_to_db(value)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MUSIC_BUS), vol)
	music_value_label.text = str(int(value))
	_save_setting("audio", "music_volume", int(value))

# === RESET PROGRESS ===

func _on_reset_pressed() -> void:
	confirm_panel.visible = true

func _on_confirm_reset() -> void:
	confirm_panel.visible = false
	PlayerData.reset()
	# Update any displayed UI that depends on player data
	pass

func _on_cancel_reset() -> void:
	confirm_panel.visible = false

# === NAVIGATION ===

func _on_back() -> void:
	settings_closed.emit()

# === PERSISTENCE ===

func load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_PATH)
	if err != OK:
		# Defaults
		master_slider.value = 80
		sfx_slider.value = 100
		music_slider.value = 70
		_apply_defaults()
		return

	var master_val: int = config.get_value("audio", "master_volume", 80)
	var sfx_val: int = config.get_value("audio", "sfx_volume", 100)
	var music_val: int = config.get_value("audio", "music_volume", 70)

	master_slider.value = master_val
	sfx_slider.value = sfx_val
	music_slider.value = music_val

	_apply_from_sliders()

func _apply_defaults() -> void:
	_on_master_changed(master_slider.value)
	_on_sfx_changed(sfx_slider.value)
	_on_music_changed(music_slider.value)

func _apply_from_sliders() -> void:
	_on_master_changed(master_slider.value)
	_on_sfx_changed(sfx_slider.value)
	_on_music_changed(music_slider.value)

func _save_setting(section: String, key: String, value: Variant) -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_PATH)
	config.set_value(section, key, value)
	config.save(SETTINGS_PATH)

func _slider_to_db(value: float) -> float:
	# 0..100 → -60..0 dB (0 = silent, 100 = full)
	if value <= 0:
		return -60.0
	return linear_to_db(value / 100.0)
