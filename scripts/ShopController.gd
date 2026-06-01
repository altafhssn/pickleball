# ShopController.gd
# Controls the Shop UI — paddle grid, buying, equipping
extends CanvasLayer

signal shop_closed

# References
@onready var coin_label: Label = $ShopPanel/CoinLabel
@onready var gem_label: Label = $ShopPanel/GemLabel
@onready var paddle_grid: GridContainer = $ShopPanel/ScrollContainer/PaddleGrid
@onready var buy_button: Button = $ShopPanel/BuyButton
@onready var equip_button: Button = $ShopPanel/EquipButton
@onready var back_button: Button = $ShopPanel/BackButton
@onready var paddle_preview_name: Label = $ShopPanel/PaddlePreviewName
@onready var paddle_preview_stats: VBoxContainer = $ShopPanel/PaddlePreviewStats

# The paddle card scene (instantiated for each paddle in the grid)
var paddle_card_scene: PackedScene = preload("res://scenes/Menus/PaddleCard.tscn")

# Currently selected paddle ID in the shop
var selected_paddle_id: int = -1

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	buy_button.pressed.connect(_on_buy_pressed)
	equip_button.pressed.connect(_on_equip_pressed)
	
	_refresh_shop()

func _refresh_shop() -> void:
	_update_balances()
	_populate_grid()
	_clear_preview()

func _update_balances() -> void:
	coin_label.text = "🪙 " + str(PlayerData.coins)
	gem_label.text = "💎 " + str(PlayerData.gems)

func _populate_grid() -> void:
	# Clear existing cards
	for child in paddle_grid.get_children():
		child.queue_free()
	
	# Get all paddle definitions
	var all_paddles: Dictionary = PaddleData.get_all_paddle_stats()
	var paddle_ids: Array = all_paddles.keys()
	paddle_ids.sort()
	
	for pid: int in paddle_ids:
		var stats: Dictionary = all_paddles[pid]
		var card = paddle_card_scene.instantiate()
		paddle_grid.add_child(card)
		
		var owned: bool = PlayerData.is_paddle_unlocked(pid)
		var equipped: bool = (PlayerData.selected_paddle == pid)
		
		card.setup(pid, stats, owned, equipped)
		card.paddle_selected.connect(_on_paddle_card_selected.bind(pid))

func _on_paddle_card_selected(paddle_id: int) -> void:
	selected_paddle_id = paddle_id
	_update_preview(paddle_id)
	
	var owned: bool = PlayerData.is_paddle_unlocked(paddle_id)
	var equipped: bool = (PlayerData.selected_paddle == paddle_id)
	
	buy_button.visible = not owned
	equip_button.visible = owned
	equip_button.disabled = equipped
	
	if owned:
		if equipped:
			equip_button.text = "✅ Equipped"
		else:
			equip_button.text = "⚡ Equip"
	else:
		var stats: Dictionary = PaddleData.get_paddle_stats(paddle_id)
		if stats.get("price_coins", 0) > 0:
			buy_button.text = "🪙 Buy: " + str(stats["price_coins"])
		elif stats.get("price_gems", 0) > 0:
			buy_button.text = "💎 Buy: " + str(stats["price_gems"])
		else:
			buy_button.text = "Buy"

func _update_preview(paddle_id: int) -> void:
	var stats: Dictionary = PaddleData.get_paddle_stats(paddle_id)
	if stats.is_empty():
		_clear_preview()
		return
	
	paddle_preview_name.text = stats["name"]
	
	# Update stat bars
	var stat_labels: Array = paddle_preview_stats.get_children()
	for i in range(stat_labels.size()):
		var label: Label = stat_labels[i]
		match label.name:
			"PowerLabel":
				label.text = "Power:      " + _stat_bar(stats["power"])
			"ControlLabel":
				label.text = "Control:   " + _stat_bar(stats["control"])
			"SpinLabel":
				label.text = "Spin:        " + _stat_bar(stats["spin"])
			"ReachLabel":
				label.text = "Reach:      " + _stat_bar(stats["reach"])

func _stat_bar(value: int) -> String:
	var filled: int = int(value / 10.0)
	var empty: int = 10 - filled
	return "█".repeat(filled) + "░".repeat(empty) + " " + str(value)

func _clear_preview() -> void:
	paddle_preview_name.text = "Select a paddle"
	buy_button.visible = false
	equip_button.visible = false
	selected_paddle_id = -1
	
	for label in paddle_preview_stats.get_children():
		label.text = "---"

func _on_buy_pressed() -> void:
	if selected_paddle_id < 0:
		return
	if PlayerData.is_paddle_unlocked(selected_paddle_id):
		return
	
	var stats: Dictionary = PaddleData.get_paddle_stats(selected_paddle_id)
	var coin_price: int = stats.get("price_coins", 0)
	var gem_price: int = stats.get("price_gems", 0)
	
	var bought: bool = false
	
	if coin_price > 0:
		bought = PlayerData.spend_coins(coin_price)
	elif gem_price > 0:
		bought = PlayerData.spend_gems(gem_price)
	else:
		# Free paddle (starter)
		bought = true
	
	if bought:
		PlayerData.unlock_paddle(selected_paddle_id)
		PlayerData.select_paddle(selected_paddle_id)
		_refresh_shop()
		_on_paddle_card_selected(selected_paddle_id)
	else:
		# Not enough currency — show feedback
		_show_not_enough_coins()

func _on_equip_pressed() -> void:
	if selected_paddle_id < 0:
		return
	if not PlayerData.is_paddle_unlocked(selected_paddle_id):
		return
	if PlayerData.selected_paddle == selected_paddle_id:
		return
	
	PlayerData.select_paddle(selected_paddle_id)
	_refresh_shop()
	_on_paddle_card_selected(selected_paddle_id)

func _on_back_pressed() -> void:
	shop_closed.emit()
	queue_free()

func _show_not_enough_coins() -> void:
	# Simple feedback — flash the coin label red or show a message
	coin_label.modulate = Color.RED
	await get_tree().create_timer(0.5).timeout
	coin_label.modulate = Color.WHITE
