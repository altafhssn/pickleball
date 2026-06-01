# MainMenu.gd
# Title screen with play, practice, shop, tournament, and challenges buttons
extends CanvasLayer

signal start_quick_match
signal start_practice
signal start_doubles
signal open_shop
signal start_tournament
signal open_challenges

func _ready():
	$PlayButton.pressed.connect(_on_play)
	$PracticeButton.pressed.connect(_on_practice)
	$DoublesButton.pressed.connect(_on_doubles)
	$ShopButton.pressed.connect(_on_shop)
	$TournamentButton.pressed.connect(_on_tournament)
	$ChallengesButton.pressed.connect(_on_challenges)

func _on_play():
	start_quick_match.emit()

func _on_practice():
	start_practice.emit()

func _on_doubles():
	start_doubles.emit()

func _on_shop():
	open_shop.emit()

func _on_tournament():
	start_tournament.emit()

func _on_challenges():
	open_challenges.emit()
