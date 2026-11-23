extends Control

# Connect our buttons using their node paths
@onready var btn_start: Button = $MenuButtons/BtnStart
@onready var btn_guide: Button = $MenuButtons/BtnGuide
@onready var btn_results: Button = $MenuButtons/BtnResults
@onready var btn_settings: Button = $MenuButtons/BtnSettings

func _ready() -> void:
	# Safely connect each button press to its function
	btn_start.pressed.connect(_on_btn_start_pressed)
	btn_guide.pressed.connect(_on_btn_guide_pressed)
	btn_results.pressed.connect(_on_btn_results_pressed)
	btn_settings.pressed.connect(_on_btn_settings_pressed)

func _on_btn_start_pressed() -> void:
	get_tree().change_scene_to_file("res://ModeSelection.tscn")

func _on_btn_guide_pressed() -> void:
	print("Component & Safety Guide clicked!")

func _on_btn_results_pressed() -> void:
	print("Simulation Results clicked!")

func _on_btn_settings_pressed() -> void:
	print("Settings clicked!")
