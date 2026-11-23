
extends Control

@onready var btn_back: Button = $BtnBack
@onready var guided_card: Button = $CardsContainer/GuideCard
@onready var free_card: Button = $CardsContainer/FreeCard


func _ready() -> void:
	btn_back.pressed.connect(_on_btn_back_pressed)
	guided_card.pressed.connect(_on_guided_card_pressed)
	free_card.pressed.connect(_on_free_card_pressed)


func _on_btn_back_pressed() -> void:
	get_tree().change_scene_to_file("res://main_menu.tscn")


func _on_guided_card_pressed() -> void:
	GameManager.selected_mode = GameManager.SimMode.GUIDED
	print("DEBUG: Guided Mode Selected")

	get_tree().change_scene_to_file("res://SimulationWorkspace.tscn")


func _on_free_card_pressed() -> void:
	GameManager.selected_mode = GameManager.SimMode.FREE
	print("DEBUG: Free Mode Selected")

	get_tree().change_scene_to_file("res://SimulationWorkspace.tscn")
