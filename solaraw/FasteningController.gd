
extends Node3D

signal fastening_completed

# ==========================================
# CAMERA SETTINGS
# ==========================================

@export var camera_path: NodePath
@export var focus_marker_path: NodePath
@export var transition_duration: float = 1.2

@onready var camera: Camera3D = get_node(camera_path)
@onready var focus_marker: Marker3D = get_node(focus_marker_path)

# ==========================================
# SCREWDRIVER REFERENCES
# ==========================================

@onready var screwdriver: Node3D = $"../Screwdriver"
@onready var screwdriver_tip: Marker3D = $"../Screwdriver/ToolTip"
@onready var screwdriver_start: Marker3D = $"../Screwdriver/ScrewdriverStart"

# ==========================================
# CHARGE CONTROLLER REFERENCES
# ==========================================

@onready var charge_controller: RigidBody3D = $"../ChargeController_Physics"
@onready var screw_container: Node3D = $"../ChargeController_Physics/ChargeController"

# ==========================================
# ANIMATION SETTINGS
# ==========================================

@export var screwdriver_move_duration: float = 0.6
@export var screw_rotation_amount: float = TAU * 3.0
@export var screw_tighten_duration: float = 1.5

# ==========================================
# VARIABLES
# ==========================================

var transition_tween: Tween

var original_camera_transform: Transform3D
var original_screwdriver_transform: Transform3D

var fastening_active: bool = false
var is_fastening_sequence: bool = false

var screws: Array[Node3D] = []
var current_screw_index: int = 0


# ==========================================
# READY
# ==========================================

func _ready() -> void:

	original_camera_transform = camera.global_transform

	_get_charge_controller_screws()


# ==========================================
# ENTER FASTENING CAMERA MODE
# ==========================================

func enter_fastening_mode() -> void:

	if fastening_active:
		return

	fastening_active = true

	original_camera_transform = camera.global_transform

	if transition_tween and transition_tween.is_running():
		transition_tween.kill()

	transition_tween = create_tween()
	transition_tween.set_trans(Tween.TRANS_SINE)
	transition_tween.set_ease(Tween.EASE_IN_OUT)

	transition_tween.tween_property(
		camera,
		"global_transform",
		focus_marker.global_transform,
		transition_duration
	)

	await transition_tween.finished


# ==========================================
# EXIT FASTENING CAMERA MODE
# ==========================================

func exit_fastening_mode() -> void:

	if not fastening_active:
		return

	if transition_tween and transition_tween.is_running():
		transition_tween.kill()

	transition_tween = create_tween()
	transition_tween.set_trans(Tween.TRANS_SINE)
	transition_tween.set_ease(Tween.EASE_IN_OUT)

	transition_tween.tween_property(
		camera,
		"global_transform",
		original_camera_transform,
		transition_duration
	)

	await transition_tween.finished

	fastening_active = false


# ==========================================
# FIND THE FOUR SCREWS
# ==========================================

func _get_charge_controller_screws() -> void:

	screws.clear()

	if not is_instance_valid(screw_container):
		push_error("CHARGE CONTROLLER SCREW CONTAINER NOT FOUND")
		return

	for child in screw_container.get_children():

		if child.name.begins_with("Screw_"):
			screws.append(child)

	screws.sort_custom(
		func(a: Node3D, b: Node3D) -> bool:
			return a.name < b.name
	)

	print("Found screws: ", screws.size())

	for screw in screws:
		print(" - ", screw.name)


# ==========================================
# MOVE SCREWDRIVER TO A SCREW
# ==========================================

func _move_screwdriver_to(target: Marker3D) -> void:

	var tip_offset := (
		screwdriver_tip.global_position
		- screwdriver.global_position
	)

	var target_position := target.global_position - tip_offset

	var tween := create_tween()

	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(
		screwdriver,
		"global_position",
		target_position,
		screwdriver_move_duration
	)

	await tween.finished


# ==========================================
# TIGHTEN SCREW
# ==========================================

func _tighten_screw(screw: Node3D) -> void:

	var start_rotation: Vector3 = screw.rotation

	var target_rotation: Vector3 = start_rotation + Vector3(
		screw_rotation_amount,
		0.0,
		0.0
	)

	var tween := create_tween()

	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(
		screw,
		"rotation",
		target_rotation,
		screw_tighten_duration
	)

	await tween.finished


# ==========================================
# RETURN SCREWDRIVER TO PLAYER REST POSITION
# ==========================================

func _return_screwdriver_to_start() -> void:

	var tween := create_tween()

	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(
		screwdriver,
		"global_transform",
		original_screwdriver_transform,
		screwdriver_move_duration
	)

	await tween.finished


# ==========================================
# FOCUS CAMERA ON CURRENT SCREW
# ==========================================

func _focus_on_screw(screw: Node3D) -> void:

	var contact_point := (
		screw.get_node_or_null("ScrewContactPoint") as Marker3D
	)

	if contact_point == null:
		push_error("MISSING SCREW CONTACT POINT: " + screw.name)
		return

	var camera_offset := Vector3(0.0, 0.25, 0.65)

	focus_marker.global_position = (
		contact_point.global_position + camera_offset
	)

	focus_marker.look_at(
		contact_point.global_position,
		Vector3.UP
	)

	if transition_tween and transition_tween.is_running():
		transition_tween.kill()

	transition_tween = create_tween()

	transition_tween.set_trans(Tween.TRANS_SINE)
	transition_tween.set_ease(Tween.EASE_IN_OUT)

	transition_tween.tween_property(
		camera,
		"global_transform",
		focus_marker.global_transform,
		transition_duration
	)

	await transition_tween.finished


# ==========================================
# MAIN FASTENING SEQUENCE
# ==========================================

func start_fastening_sequence() -> void:

	if is_fastening_sequence:
		return

	if screws.size() != 4:
		_get_charge_controller_screws()

	if screws.size() != 4:
		push_error("FASTENING REQUIRES EXACTLY 4 SCREWS")
		return

	is_fastening_sequence = true
	current_screw_index = 0

	# SAVE ORIGINAL PLAYER-SIDE RESTING POSITION
	original_screwdriver_transform = screwdriver.global_transform

	# ENTER CLOSE-UP CAMERA MODE
	await enter_fastening_mode()

	# PROCESS ALL FOUR SCREWS
	for screw in screws:

		var contact_point := (
			screw.get_node_or_null("ScrewContactPoint") as Marker3D
		)

		if contact_point == null:

			push_error("MISSING SCREW CONTACT POINT: " + screw.name)

			is_fastening_sequence = false

			await exit_fastening_mode()

			return

		# FOCUS ON CURRENT SCREW
		await _focus_on_screw(screw)

		# MOVE SCREWDRIVER TOWARD SCREW
		await _move_screwdriver_to(contact_point)

		# TIGHTEN CURRENT SCREW
		await _tighten_screw(screw)

		await get_tree().create_timer(0.3).timeout

		# RETURN TO ORIGINAL RESTING POSITION
		await _return_screwdriver_to_start()

		current_screw_index += 1

	# RETURN CAMERA TO PLAYER VIEW
	await exit_fastening_mode()

	is_fastening_sequence = false

	print("ALL FOUR SCREWS HAVE BEEN TIGHTENED!")

	# NOTIFY SIMULATION WORKSPACE
	fastening_completed.emit()
