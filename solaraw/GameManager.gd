extends Node

enum SimMode { GUIDED, FREE }
var selected_mode: int = SimMode.GUIDED
var selected_scenario: String = "Off-Grid PV System Installation"

# Results passed from 3D Workspace to Evaluation Dashboard
var last_score: int = 100
var last_time_seconds: float = 0.0
var completed_steps: Array[String] = []
var error_logs: Array[String] = []

func reset_session() -> void:
	last_score = 100
	last_time_seconds = 0.0
	completed_steps.clear()
	error_logs.clear()
