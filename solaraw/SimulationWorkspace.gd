
extends Node3D

# ==========================================
# PLAYER AND CAMERA
# ==========================================

@onready var player: CharacterBody3D = $Player
@onready var camera_pivot: Node3D = $Player/CameraPivot
@onready var camera: Camera3D = $Player/CameraPivot/WorkspaceCamera
@onready var fastening_controller: Node = get_node_or_null("FasteningController")

@onready var move_joystick = $HUD/MobileControls/MoveJoystick
@onready var look_joystick = $HUD/MobileControls/LookJoystick

# ==========================================
# COMPONENTS
# ==========================================

@onready var solar_panel: Node3D = find_child("SolarPanel_1", true, false)
@onready var charge_controller: Node3D = find_child("ChargeController", true, false)
@onready var inverter: Node3D = find_child("Inverter", true, false)
@onready var battery_bank: Node3D = find_child("BatteryBank", true, false)

@onready var wiring_harness: Node3D = $WiringHarness

# ==========================================
# SNAP ZONES
# ==========================================

@onready var panel_snap_zone: Area3D = $PanelSnapZone
@onready var controller_snap_zone: Area3D = $ControllerSnapZone
@onready var inverter_snap_zone: Area3D = $InverterSnapZone
@onready var battery_snap_zone: Area3D = $BatterySnapZone

# ==========================================
# COMMISSIONING AREA
# ==========================================

@onready var step_4_click_area: Area3D = get_node_or_null("Step4ClickArea")

# ==========================================
# HUD
# ==========================================

@onready var instruction_panel: PanelContainer = $HUD/InstructionPanel
@onready var step_title_label: Label = $HUD/InstructionPanel/VBox/StepTitleLabel
@onready var instruction_label: Label = $HUD/InstructionPanel/VBox/InstructionLabel
@onready var safety_alert_label: Label = $HUD/InstructionPanel/VBox/SafetyAlertLabel

@onready var win_screen: Control = $HUD/WinScreen
@onready var restart_button: Button = $HUD/WinScreen/CenterContainer/PanelContainer/VBoxContainer/RestartButton
@onready var accuracy_label: Label = $HUD/WinScreen/CenterContainer/PanelContainer/VBoxContainer/AccuracyLabel
@onready var time_label: Label = $HUD/WinScreen/CenterContainer/PanelContainer/VBoxContainer/TimeLabel
@onready var feedback_label: RichTextLabel = $HUD/WinScreen/CenterContainer/PanelContainer/VBoxContainer/FeedbackTextLabel

@onready var crosshair: Label = $HUD/MobileControls/Crosshair
@onready var grab_button: Button = $HUD/MobileControls/GrabButton
@onready var fasten_button: Button = $HUD/MobileControls/FastenButton

# ==========================================
# PAUSE SYSTEM
# ==========================================

@onready var pause_button: Button = $HUD/PauseButton
@onready var pause_menu: Control = $HUD/PauseMenu
@onready var resume_button: Button = $HUD/PauseMenu/CenterContainer/VBoxContainer/ResumeButton
@onready var pause_restart_button: Button = $HUD/PauseMenu/CenterContainer/VBoxContainer/RestartButton
@onready var main_menu_button: Button = $HUD/PauseMenu/CenterContainer/VBoxContainer/MainMenuButton

@export_file("*.tscn") var main_menu_scene_path: String = "res://main_menu.tscn"

var is_game_paused: bool = false

# ==========================================
# COMPONENT DRAGGING
# ==========================================

var current_step: int = 1

var active_drag_node: Node3D = null
var active_drag_body: RigidBody3D = null
var active_touch_index: int = -1

var drag_offset: Vector3 = Vector3.ZERO
var active_drag_mesh_offset: Vector3 = Vector3.ZERO

var is_orbiting_camera: bool = false
var orbit_sensitivity: float = 0.005

var component_areas: Dictionary = {}
var grab_button_held: bool = false

# ==========================================
# DRAG REACH AND COLLISION
# ==========================================

const MIN_DRAG_REACH: float = 0.75
const MAX_DRAG_REACH: float = 3.5
const DRAG_COLLISION_MARGIN: float = 0.05
const MAX_SLIDE_ITERATIONS: int = 4

var drag_distance: float = 2.0

# ==========================================
# SNAP ANIMATION
# ==========================================

var snap_animation_duration: float = 0.35
var snapping_nodes: Array[Node3D] = []

# ==========================================
# PLAYER MOVEMENT
# ==========================================

var move_speed: float = 3.0
var look_sensitivity: float = 2.0
var camera_pitch: float = deg_to_rad(-20.0)

var gravity: float = float(
	ProjectSettings.get_setting("physics/3d/default_gravity")
)

# ==========================================
# WIRE CONNECTION SYSTEM
# ==========================================

var wire_connection_animating: bool = false

var active_wire_connector: Node3D = null
var active_wire_marker: Marker3D = null

var active_wire_index: int = -1
var active_wire_is_start: bool = false

var wire_task_index: int = 0

var wire_connection_duration: float = 0.45

# ==========================================
# 3D COMMISSIONING BUTTON CROSSHAIR DETECTION
# ==========================================

func _is_commissioning_area_under_crosshair(screen_position: Vector2) -> bool:
	if not is_instance_valid(step_4_click_area):
		printerr("COMMISSIONING AREA NOT FOUND")
		return false

	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_direction * 100.0
	)
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return false

	var collider = result.get("collider")
	if not is_instance_valid(collider):
		return false

	return collider == step_4_click_area or step_4_click_area.is_ancestor_of(collider)


# ==========================================
# TERMINAL CAMERA CLOSE-UP
# ==========================================

var terminal_camera_mode: bool = false
var terminal_camera_animating: bool = false
var terminal_camera_original_transform: Transform3D
var terminal_camera_tween: Tween = null

@export_range(0.25, 1.5, 0.05) var terminal_camera_distance: float = 0.55
@export_range(0.2, 1.5, 0.05) var terminal_camera_transition_time: float = 0.65

var wire_nodes: Array = []
var wire_start_connectors: Array = []
var wire_end_connectors: Array = []

var wire_start_markers: Array = []
var wire_end_markers: Array = []

var wire_start_targets: Array = []
var wire_end_targets: Array = []

var wire_start_connected: Array[bool] = []
var wire_end_connected: Array[bool] = []

var wire_area_indices: Dictionary = {}
var wire_terminal_areas: Dictionary = {}

@export var wire_start_target_paths: Array[NodePath] = [
	NodePath("SolarPanel_Physics/SolarPanel_1/Panel_Positive_Terminal"),
	NodePath("SolarPanel_Physics/SolarPanel_1/Panel_Negative_Terminal"),
	NodePath("ChargeController_Physics/ChargeController/Controller_Battery_Positive"),
	NodePath("ChargeController_Physics/ChargeController/Controller_Battery_Negative"),
	NodePath("BatteryBank/Battery_Positive_Terminal"),
	NodePath("BatteryBank/Battery_Negative_Terminal")
]

# ==========================================
# WIRE NAMES
# ==========================================

var wire_names: Array[String] = [
	"Wire_1_Panel_Positive",
	"Wire_2_Panel_Negative",
	"Wire_3_Controller_Battery_Positive",
	"Wire_4_Controller_Battery_Negative",
	"Wire_5_Battery_Inverter_Positive",
	"Wire_6_Battery_Inverter_Negative"
]

# ==========================================
# END WIRE TARGET PATHS
# ==========================================

var wire_target_paths: Array[String] = [
	"ChargeController_Physics/ChargeController/Controller_PV_Positive",
	"ChargeController_Physics/ChargeController/Controller_PV_Negative",
	"BatteryBank/Battery_Positive_Terminal",
	"BatteryBank/Battery_Negative_Terminal",
	"Inverter/Inverter_Positive_Terminal",
	"Inverter/Inverter_Negative_Terminal"
]

# ==========================================
# INSTALLATION STATUS
# ==========================================

var controller_fastened: bool = false
var panel_snapped: bool = false
var controller_snapped: bool = false
var inverter_snapped: bool = false
var battery_snapped: bool = false

var wiring_connected: bool = false

# ==========================================
# PERFORMANCE
# ==========================================

var simulation_timer: float = 0.0
var safety_violations_count: int = 0
var simulation_active: bool = true

# ==========================================
# MODE CHECK
# ==========================================

func is_free_mode() -> bool:
	return GameManager.selected_mode == GameManager.SimMode.FREE


func is_guided_mode() -> bool:
	return GameManager.selected_mode == GameManager.SimMode.GUIDED


func _is_fastening_active() -> bool:
	if not is_instance_valid(fastening_controller):
		return false

	return bool(fastening_controller.get("fastening_active"))


# ==========================================
# PHYSICS BODY HELPER
# ==========================================

func _get_component_body(node: Node3D) -> RigidBody3D:
	if node == null:
		return null

	if node is RigidBody3D:
		return node as RigidBody3D

	var parent = node.get_parent()

	if parent is RigidBody3D:
		return parent as RigidBody3D

	return null


# ==========================================
# FIND WIRE TERMINAL
# ==========================================

func _find_wire_target(target_path: String) -> Node3D:
	if target_path.is_empty():
		return null

	var target := get_node_or_null(NodePath(target_path)) as Node3D

	if is_instance_valid(target):
		return target

	var target_name := target_path.get_file()

	if target_name.is_empty():
		return null

	target = find_child(target_name, true, false) as Node3D

	if is_instance_valid(target):
		print("WIRE TARGET FOUND BY NAME: ", target_name)
		return target

	printerr("WIRE TARGET NOT FOUND BY PATH OR NAME: ", target_path)
	return null


# ==========================================
# REGISTER TERMINAL DETECTION AREA
# ==========================================

func _register_wire_terminal_area(target: Node3D) -> void:
	if not is_instance_valid(target):
		return

	var terminal_area := target.find_child(
		"TerminalArea",
		true,
		false
	) as Area3D

	if terminal_area == null:
		terminal_area = Area3D.new()
		terminal_area.name = "TerminalArea"
		target.add_child(terminal_area)

		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"

		var sphere := SphereShape3D.new()
		sphere.radius = 0.15

		collision.shape = sphere
		terminal_area.add_child(collision)

		print("CREATED TERMINAL AREA: ", target.name)

	terminal_area.collision_layer = 2
	terminal_area.collision_mask = 0
	terminal_area.monitoring = true
	terminal_area.monitorable = true
	terminal_area.input_ray_pickable = true

	# Larger invisible hitbox makes small terminal sockets easier to tap on Android.
	var terminal_collision := terminal_area.get_node_or_null(
		"CollisionShape3D"
	) as CollisionShape3D
	if terminal_collision and terminal_collision.shape is SphereShape3D:
		terminal_collision.shape.radius = 0.25

	wire_terminal_areas[terminal_area] = target

	print("TERMINAL DETECTION READY: ", target.name)


# ==========================================
# READY
# ==========================================

func _ready() -> void:
	print("====================================")
	print("SOLARAW SIMULATION STARTED")
	print("CURRENT MODE: ", GameManager.selected_mode)
	print("====================================")

	wiring_harness.visible = false

	camera.current = true
	camera_pitch = deg_to_rad(-20.0)
	camera.rotation.x = camera_pitch

	win_screen.visible = false
	instruction_panel.visible = is_guided_mode()

	if crosshair:
		crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if grab_button:
		grab_button.toggle_mode = false
		grab_button.text = "GRAB"

		if not grab_button.pressed.is_connected(_on_grab_button_pressed):
			grab_button.pressed.connect(_on_grab_button_pressed)
	else:
		printerr("GRAB BUTTON NOT FOUND")

	if fasten_button:
		fasten_button.text = "FASTEN"

		if not fasten_button.pressed.is_connected(_on_fasten_button_pressed):
			fasten_button.pressed.connect(_on_fasten_button_pressed)
	else:
		printerr("FASTEN BUTTON NOT FOUND")

	if is_instance_valid(fastening_controller):
		if fastening_controller.has_signal("fastening_completed"):
			var callback := Callable(self, "_on_fastening_completed")

			if not fastening_controller.is_connected("fastening_completed", callback):
				fastening_controller.connect("fastening_completed", callback)
		else:
			printerr("FASTENING COMPLETED SIGNAL NOT FOUND")
	else:
		printerr("FASTENING CONTROLLER NOT FOUND")

	if restart_button:
		if not restart_button.pressed.is_connected(_on_restart_pressed):
			restart_button.pressed.connect(_on_restart_pressed)

	if pause_menu:
		pause_menu.visible = false
		pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	else:
		printerr("PAUSE MENU NOT FOUND")

	if pause_button:
		pause_button.process_mode = Node.PROCESS_MODE_ALWAYS

		if not pause_button.pressed.is_connected(_on_pause_button_pressed):
			pause_button.pressed.connect(_on_pause_button_pressed)
	else:
		printerr("PAUSE BUTTON NOT FOUND")

	if resume_button:
		resume_button.process_mode = Node.PROCESS_MODE_ALWAYS

		if not resume_button.pressed.is_connected(_on_resume_button_pressed):
			resume_button.pressed.connect(_on_resume_button_pressed)
	else:
		printerr("RESUME BUTTON NOT FOUND")

	if pause_restart_button:
		pause_restart_button.process_mode = Node.PROCESS_MODE_ALWAYS

		if not pause_restart_button.pressed.is_connected(_on_restart_pressed):
			pause_restart_button.pressed.connect(_on_restart_pressed)
	else:
		printerr("PAUSE RESTART BUTTON NOT FOUND")

	if main_menu_button:
		main_menu_button.process_mode = Node.PROCESS_MODE_ALWAYS

		if not main_menu_button.pressed.is_connected(_on_main_menu_button_pressed):
			main_menu_button.pressed.connect(_on_main_menu_button_pressed)
	else:
		printerr("MAIN MENU BUTTON NOT FOUND")

	if step_4_click_area:
		step_4_click_area.input_ray_pickable = true
		step_4_click_area.monitoring = true
		step_4_click_area.monitorable = true
		if not step_4_click_area.input_event.is_connected(_on_step_4_clicked):
			step_4_click_area.input_event.connect(_on_step_4_clicked)
	else:
		printerr("Step4ClickArea NOT FOUND - check the exact node path")

	_connect_component(solar_panel)
	_connect_component(charge_controller)
	_connect_component(inverter)
	_connect_component(battery_bank)

	_setup_wires()

	_update_hud_for_step()
	_update_grab_button_label()


# ==========================================
# PROCESS
# ==========================================

func _process(delta: float) -> void:
	if is_game_paused:
		return

	if simulation_active:
		simulation_timer += delta

	if active_drag_node != null and active_touch_index == -2:
		if grab_button_held:
			var screen_center: Vector2 = (
				get_viewport().get_visible_rect().size / 2.0
			)
			_move_node_to_pointer(screen_center)


# ==========================================
# PHYSICS PROCESS
# ==========================================

func _physics_process(delta: float) -> void:
	if is_game_paused:
		return

	apply_mobile_controls(delta)


# ==========================================
# CONNECT COMPONENT INPUT
# ==========================================

func _connect_component(target_node: Node3D) -> void:
	if target_node == null:
		printerr("COMPONENT NOT FOUND")
		return

	var area: Area3D = null
	var search_node: Node = target_node

	while search_node != null:
		area = search_node.find_child("Area3D", true, false) as Area3D

		if area != null:
			break

		search_node = search_node.get_parent()

	if area == null:
		printerr("AREA3D NOT FOUND FOR: ", target_node.name)
		return

	area.input_ray_pickable = true
	component_areas[area] = target_node

	var body = _get_component_body(target_node)

	if body != null:
		component_areas[body] = target_node

	var callback = _on_component_input.bind(target_node)

	if not area.input_event.is_connected(callback):
		area.input_event.connect(callback)

	print("COMPONENT INPUT READY: ", target_node.name)


# ==========================================
# CINEMATIC FASTENING
# ==========================================

func _on_fasten_button_pressed() -> void:
	if is_game_paused or _is_fastening_active():
		return

	if not controller_snapped:
		print("SNAP THE CHARGE CONTROLLER INTO POSITION FIRST")
		return

	if controller_fastened:
		print("CHARGE CONTROLLER IS ALREADY FASTENED")
		return

	if not is_instance_valid(fastening_controller):
		printerr("FASTENING CONTROLLER NOT FOUND")
		return

	if fastening_controller.has_method("start_fastening_sequence"):
		fasten_button.disabled = true
		fastening_controller.start_fastening_sequence()
	else:
		printerr("START FASTENING SEQUENCE FUNCTION NOT FOUND")


func _on_fastening_completed() -> void:
	controller_fastened = true

	if fasten_button:
		fasten_button.text = "FASTENED"
		fasten_button.disabled = true

	print("CHARGE CONTROLLER: ALL FOUR SCREWS FASTENED")

	_check_step_2_complete()
	_check_wiring_unlock()


# ==========================================
# SETUP WIRES
# ==========================================

func _setup_wires() -> void:
	wire_nodes.clear()
	wire_start_connectors.clear()
	wire_end_connectors.clear()
	wire_start_markers.clear()
	wire_end_markers.clear()
	wire_start_targets.clear()
	wire_end_targets.clear()
	wire_start_connected.clear()
	wire_end_connected.clear()
	wire_area_indices.clear()
	wire_terminal_areas.clear()

	for i in range(wire_names.size()):
		wire_nodes.append(null)
		wire_start_connectors.append(null)
		wire_end_connectors.append(null)
		wire_start_markers.append(null)
		wire_end_markers.append(null)
		wire_start_targets.append(null)
		wire_end_targets.append(null)
		wire_start_connected.append(false)
		wire_end_connected.append(false)

		var wire_node: Node3D = wiring_harness.get_node_or_null(
			wire_names[i]
		) as Node3D

		if wire_node == null:
			printerr("WIRE NOT FOUND: ", wire_names[i])
			continue

		var start_marker: Marker3D = wire_node.get_node_or_null(
			"StartMarker"
		) as Marker3D

		var end_marker: Marker3D = wire_node.get_node_or_null(
			"EndMarker"
		) as Marker3D

		if start_marker == null or end_marker == null:
			printerr("WIRE MARKERS MISSING: ", wire_names[i])
			continue

		var start_connector: Node3D = start_marker.get_node_or_null(
			"StartConnector"
		) as Node3D

		var end_connector: Node3D = end_marker.get_node_or_null(
			"EndConnector"
		) as Node3D

		if start_connector == null or end_connector == null:
			printerr("WIRE CONNECTORS MISSING: ", wire_names[i])
			continue

		var start_area: Area3D = start_connector.get_node_or_null(
			"ConnectorArea"
		) as Area3D

		var end_area: Area3D = end_connector.get_node_or_null(
			"ConnectorArea"
		) as Area3D

		if start_area == null or end_area == null:
			printerr("CONNECTOR AREA MISSING: ", wire_names[i])
			continue

		var start_collision := start_area.get_node_or_null(
			"CollisionShape3D"
		) as CollisionShape3D

		var end_collision := end_area.get_node_or_null(
			"CollisionShape3D"
		) as CollisionShape3D

		if start_collision == null or end_collision == null:
			printerr("CONNECTOR COLLISION SHAPE MISSING: ", wire_names[i])
			continue

		var start_target: Node3D = null

		if i < wire_start_target_paths.size():
			if not wire_start_target_paths[i].is_empty():
				start_target = _find_wire_target(
					String(wire_start_target_paths[i])
				)

		var end_target: Node3D = _find_wire_target(
			wire_target_paths[i]
		)

		if start_target == null:
			printerr(
				"START TARGET NOT ASSIGNED FOR: ",
				wire_names[i],
				" | Configure wire_start_target_paths in Inspector"
			)

		if end_target == null:
			printerr("END TARGET STILL MISSING FOR: ", wire_names[i])

		_register_wire_terminal_area(start_target)
		_register_wire_terminal_area(end_target)

		_configure_wire_area(start_area, start_collision)
		_configure_wire_area(end_area, end_collision)

		wire_nodes[i] = wire_node
		wire_start_connectors[i] = start_connector
		wire_end_connectors[i] = end_connector
		wire_start_markers[i] = start_marker
		wire_end_markers[i] = end_marker
		wire_start_targets[i] = start_target
		wire_end_targets[i] = end_target

		wire_area_indices[start_area] = {
			"index": i,
			"is_start": true
		}

		wire_area_indices[end_area] = {
			"index": i,
			"is_start": false
		}

		print("WIRE READY: ", wire_names[i])

	print("TOTAL WIRES: ", wire_nodes.size())
	print("REGISTERED CONNECTOR AREAS: ", wire_area_indices.size())
	print("REGISTERED TERMINAL AREAS: ", wire_terminal_areas.size())


# ==========================================
# CONFIGURE WIRE CONNECTOR AREA
# ==========================================

func _configure_wire_area(
	area: Area3D,
	collision_shape: CollisionShape3D
) -> void:
	area.monitoring = true
	area.monitorable = true
	area.input_ray_pickable = true
	area.collision_layer = 1
	area.collision_mask = 0

	var hitbox := SphereShape3D.new()
	hitbox.radius = 0.22

	collision_shape.shape = hitbox
	collision_shape.position = Vector3.ZERO
	collision_shape.disabled = false


# ==========================================
# CROSSHAIR COMPONENT DETECTION
# ==========================================

func _get_crosshair_component() -> Dictionary:
	var screen_center: Vector2 = (
		get_viewport().get_visible_rect().size / 2.0
	)

	var ray_origin = camera.project_ray_origin(screen_center)
	var ray_direction = camera.project_ray_normal(screen_center)

	var query = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_direction * 100.0
	)

	query.collide_with_areas = true
	query.collide_with_bodies = true

	var result = get_world_3d().direct_space_state.intersect_ray(query)

	if result.is_empty():
		return {}

	var collider = result.get("collider")

	if not is_instance_valid(collider):
		return {}

	if not component_areas.has(collider):
		return {}

	return {
		"node": component_areas[collider],
		"position": result["position"],
		"normal": result["normal"],
		"shape": result["shape"]
	}


# ==========================================
# TERMINAL CAMERA CLOSE-UP
# ==========================================

func _focus_camera_on_terminal(target_node: Node3D) -> void:
	if not is_instance_valid(target_node) or terminal_camera_animating:
		return

	if not terminal_camera_mode:
		terminal_camera_original_transform = camera.global_transform

	terminal_camera_mode = true
	terminal_camera_animating = true

	var view_direction: Vector3 = (
		camera.global_position - target_node.global_position
	).normalized()

	if view_direction.length_squared() < 0.001:
		view_direction = target_node.global_basis.z.normalized()

	var close_position: Vector3 = (
		target_node.global_position
		+ view_direction * terminal_camera_distance
	)

	var close_transform := Transform3D(Basis.IDENTITY, close_position)
	close_transform = close_transform.looking_at(
		target_node.global_position,
		Vector3.UP
	)

	if terminal_camera_tween and terminal_camera_tween.is_running():
		terminal_camera_tween.kill()

	terminal_camera_tween = create_tween()
	terminal_camera_tween.set_trans(Tween.TRANS_SINE)
	terminal_camera_tween.set_ease(Tween.EASE_IN_OUT)
	terminal_camera_tween.tween_property(
		camera,
		"global_transform",
		close_transform,
		terminal_camera_transition_time
	)
	await terminal_camera_tween.finished
	terminal_camera_animating = false
	print("TERMINAL CAMERA CLOSE-UP READY: ", target_node.name)


func _return_camera_from_terminal_focus() -> void:
	if not terminal_camera_mode:
		return

	terminal_camera_animating = true

	if terminal_camera_tween and terminal_camera_tween.is_running():
		terminal_camera_tween.kill()

	terminal_camera_tween = create_tween()
	terminal_camera_tween.set_trans(Tween.TRANS_SINE)
	terminal_camera_tween.set_ease(Tween.EASE_IN_OUT)
	terminal_camera_tween.tween_property(
		camera,
		"global_transform",
		terminal_camera_original_transform,
		terminal_camera_transition_time
	)
	await terminal_camera_tween.finished

	terminal_camera_mode = false
	terminal_camera_animating = false
	print("CAMERA RETURNED TO WORKSPACE")


# ==========================================
# DIRECT TERMINAL TAP DETECTION
# ==========================================

func _get_terminal_target_at_screen_position(
	screen_position: Vector2
) -> Node3D:
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)

	var query := PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_direction * 100.0
	)

	query.collision_mask = 2
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var result := get_world_3d().direct_space_state.intersect_ray(query)

	if result.is_empty():
		return null

	var collider = result.get("collider")

	if not is_instance_valid(collider):
		return null

	if not wire_terminal_areas.has(collider):
		return null

	return wire_terminal_areas[collider]


# ==========================================
# CHECK IF TAP IS ON HUD
# ==========================================

func _is_touch_over_hud(screen_position: Vector2) -> bool:
	var controls: Array = [
		grab_button,
		fasten_button,
		pause_button,
		move_joystick,
		look_joystick,
		instruction_panel,
		pause_menu,
		win_screen
	]

	for control in controls:
		if control is Control:
			if control.visible and control.get_global_rect().has_point(screen_position):
				return true

	return false


# ==========================================
# MOBILE GRAB BUTTON
# ==========================================

func _on_grab_button_pressed() -> void:
	if is_game_paused or wire_connection_animating:
		return

	var screen_center: Vector2 = (
		get_viewport().get_visible_rect().size / 2.0
	)

	# A selected connector waits for a direct terminal tap.
	if is_instance_valid(active_wire_connector):
		if is_guided_mode():
			safety_alert_label.text = "Tap the correct terminal on the screen."

		print("TAP THE CORRECT TERMINAL")
		return

	# Component drop behavior.
	if active_drag_node != null and active_touch_index == -2:
		print("MOBILE COMPONENT DROP")
		_finish_component_drag()
		return

	if active_drag_node != null:
		return

	# FINAL COMMISSIONING: aim at the existing 3D Area3D and press GRAB.
	if current_step == 5:
		if _is_commissioning_area_under_crosshair(screen_center):
			print("3D COMMISSIONING BUTTON DETECTED")
			_complete_final_commissioning()
		else:
			print("AIM THE CROSSHAIR AT THE 3D COMMISSIONING BUTTON")
			if is_guided_mode() and safety_alert_label:
				safety_alert_label.text = "Aim at the commissioning button and press GRAB."
		return

	# Select a wire connector.
	if current_step == 4 and not wiring_connected:
		if _try_select_wire_connector(screen_center):
			print("WIRE CONNECTOR SELECTED")
		else:
			print("NO AVAILABLE WIRE CONNECTOR UNDER CROSSHAIR")
		return

	if current_step >= 6:
		return

	var detected: Dictionary = _get_crosshair_component()

	if detected.is_empty():
		print("CROSSHAIR: No selectable component detected")
		return

	var target_node: Node3D = detected["node"]

	var grab_event := InputEventMouseButton.new()
	grab_event.button_index = MOUSE_BUTTON_LEFT
	grab_event.pressed = true
	grab_event.position = screen_center


	_on_component_input(
		camera,
		grab_event,
		detected["position"],
		detected["normal"],
		detected["shape"],
		target_node)

	if active_drag_node != null:
		active_touch_index = -2
		grab_button_held = true
		_update_grab_button_label()
		print("MOBILE COMPONENT GRAB STARTED: ", target_node.name)


# ==========================================
# UPDATE GRAB BUTTON LABEL
# ==========================================

func _update_grab_button_label() -> void:
	if grab_button == null:
		return

	if wire_connection_animating:
		grab_button.text = "CONNECTING..."
	elif is_instance_valid(active_wire_connector):
		grab_button.text = "TAP TERMINAL"
	elif active_drag_node != null and active_touch_index == -2:
		grab_button.text = "DROP"
	else:
		grab_button.text = "GRAB"


# ==========================================
# COMPONENT INPUT
# ==========================================

func _on_component_input(
	_camera: Node,
	event: InputEvent,
	_pos: Vector3,
	_normal: Vector3,
	_shape_idx: int,
	target_node: Node3D
) -> void:
	if is_game_paused:
		return

	var pressed := false
	var touch_index := -1
	var screen_position := Vector2.ZERO

	if event is InputEventScreenTouch:
		if event.pressed:
			pressed = true
			touch_index = event.index
			screen_position = event.position
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			pressed = true
			screen_position = event.position

	if not pressed:
		return

	if active_drag_node != null or is_instance_valid(active_wire_connector):
		return

	if current_step >= 5:
		return

	if _is_component_snapped(target_node):
		return

	if snapping_nodes.has(target_node):
		return

	if is_guided_mode():
		if current_step == 1 and target_node != solar_panel:
			safety_violations_count += 1
			safety_alert_label.text = "Mount the Solar Panel first!"
			return

		if current_step == 2:
			if target_node != charge_controller and target_node != inverter:
				safety_violations_count += 1
				safety_alert_label.text = "Mount the Charge Controller and Inverter next!"
				return

		if current_step == 3 and target_node != battery_bank:
			safety_violations_count += 1
			safety_alert_label.text = "Place the Battery Bank before wiring!"
			return

	active_drag_node = target_node
	active_touch_index = touch_index
	active_drag_body = _get_component_body(target_node)

	if active_drag_body != null:
		active_drag_mesh_offset = (
			target_node.global_position
			- active_drag_body.global_position
		)

		active_drag_body.linear_velocity = Vector3.ZERO
		active_drag_body.angular_velocity = Vector3.ZERO
		active_drag_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		active_drag_body.freeze = true
	else:
		active_drag_mesh_offset = Vector3.ZERO

	var ray_origin = camera.project_ray_origin(screen_position)
	var ray_direction = camera.project_ray_normal(screen_position)
	var component_position = target_node.global_position

	drag_distance = (component_position - ray_origin).dot(ray_direction)
	drag_distance = clamp(drag_distance, MIN_DRAG_REACH, MAX_DRAG_REACH)

	var initial_target_position = ray_origin + ray_direction * drag_distance
	drag_offset = component_position - initial_target_position

	print("DRAG STARTED: ", target_node.name)
	print("DRAG DISTANCE: ", drag_distance)


# ==========================================
# INPUT HANDLING
# ==========================================

func _input(event: InputEvent) -> void:
	if is_game_paused or _is_fastening_active():
		return

	# Direct Android terminal tap.
	if event is InputEventScreenTouch and event.pressed:
		if terminal_camera_animating:
			return
		if is_instance_valid(active_wire_connector):
			if current_step == 4 and not wire_connection_animating:
				if _is_touch_over_hud(event.position):
					return

				var tapped_terminal := _get_terminal_target_at_screen_position(
					event.position
				)

				if is_instance_valid(tapped_terminal):
					get_viewport().set_input_as_handled()
					_connect_selected_wire(tapped_terminal)
				else:
					print("NO TERMINAL DETECTED AT TAP POSITION")

					if is_guided_mode():
						safety_alert_label.text = "Tap directly on a terminal socket."

				return

	# Component dragging.
	if event is InputEventScreenDrag:
		if active_drag_node != null and active_touch_index >= 0:
			if event.index == active_touch_index:
				_move_node_to_pointer(event.position)
				return

	if event is InputEventScreenTouch:
		if not event.pressed:
			if active_drag_node != null and active_touch_index >= 0:
				if event.index == active_touch_index:
					_finish_component_drag()
					return

	# Existing camera orbit handling.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			is_orbiting_camera = event.pressed

	if event is InputEventMouseMotion:
		if is_orbiting_camera:
			camera_pivot.rotate_y(-event.relative.x * orbit_sensitivity)


# ==========================================
# MOVE COMPONENT WITH REACH AND COLLISION
# ==========================================

func _move_node_to_pointer(screen_position: Vector2) -> void:
	if active_drag_node == null:
		return

	var ray_origin = camera.project_ray_origin(screen_position)
	var ray_direction = camera.project_ray_normal(screen_position)

	var desired_position = (
		ray_origin
		+ ray_direction * drag_distance
		+ drag_offset
	)

	var camera_to_object = desired_position - ray_origin
	var current_reach = camera_to_object.length()

	if current_reach > 0.001:
		var clamped_reach = clamp(
			current_reach,
			MIN_DRAG_REACH,
			MAX_DRAG_REACH
		)

		desired_position = (
			ray_origin
			+ camera_to_object.normalized() * clamped_reach
		)

	if active_drag_body != null:
		var desired_body_position = (
			desired_position - active_drag_mesh_offset
		)

		_move_component_with_collision(
			active_drag_body,
			desired_body_position
		)
	else:
		active_drag_node.global_position = desired_position


# ==========================================
# COLLISION-AWARE COMPONENT MOVEMENT
# ==========================================

func _move_component_with_collision(
	body: RigidBody3D,
	desired_body_position: Vector3
) -> void:
	if not is_instance_valid(body):
		return

	var remaining_motion = desired_body_position - body.global_position

	if remaining_motion.length_squared() < 0.000001:
		return

	for i in range(MAX_SLIDE_ITERATIONS):
		if remaining_motion.length_squared() < 0.000001:
			break

		var collision := KinematicCollision3D.new()

		var collided = body.test_move(
			body.global_transform,
			remaining_motion,
			collision,
			DRAG_COLLISION_MARGIN
		)

		if not collided:
			body.global_position += remaining_motion
			break

		var travel = collision.get_travel()
		body.global_position += travel

		var collision_normal = collision.get_normal()
		var leftover_motion = collision.get_remainder()

		remaining_motion = leftover_motion.slide(collision_normal)

		if remaining_motion.length_squared() < 0.0001:
			break


# ==========================================
# FINISH COMPONENT DRAG / DROP
# ==========================================

func _finish_component_drag() -> void:
	if active_drag_node == null:
		return

	var released_node = active_drag_node
	var released_body = active_drag_body

	_check_snap(released_node)

	if released_body != null:
		if not _is_component_snapped(released_node):
			released_body.freeze = false
			released_body.sleeping = false
			released_body.linear_velocity = Vector3.ZERO
			released_body.angular_velocity = Vector3.ZERO

	print("DRAG RELEASED: ", released_node.name)

	active_drag_node = null
	active_drag_body = null
	active_touch_index = -1
	active_drag_mesh_offset = Vector3.ZERO

	drag_distance = 2.0
	drag_offset = Vector3.ZERO
	grab_button_held = false

	_update_grab_button_label()


# ==========================================
# CHECK COMPONENT SNAP STATUS
# ==========================================

func _is_component_snapped(node: Node3D) -> bool:
	if node == solar_panel:
		return panel_snapped
	if node == charge_controller:
		return controller_snapped
	if node == inverter:
		return inverter_snapped
	if node == battery_bank:
		return battery_snapped

	return false


# ==========================================
# SNAP ANIMATION
# ==========================================

func _play_snap_animation(
	node: Node3D,
	snap_zone: Node3D
) -> void:
	if node == null or snap_zone == null:
		return

	var body = _get_component_body(node)
	var animated_node: Node3D = node

	var target_position: Vector3
	var target_rotation: Vector3

	if body != null:
		animated_node = body
		var mesh_offset = node.global_position - body.global_position
		target_position = snap_zone.global_position - mesh_offset
		target_rotation = snap_zone.global_rotation
	else:
		target_position = snap_zone.global_position
		target_rotation = snap_zone.global_rotation

	snapping_nodes.append(node)

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)

	var lifted_position = target_position + Vector3.UP * 0.12

	tween.tween_property(
		animated_node,
		"global_position",
		lifted_position,
		snap_animation_duration * 0.4
	)

	tween.parallel().tween_property(
		animated_node,
		"global_rotation",
		target_rotation,
		snap_animation_duration * 0.4
	)

	tween.tween_property(
		animated_node,
		"global_position",
		target_position,
		snap_animation_duration * 0.6
	)

	tween.finished.connect(
		_on_snap_animation_finished.bind(node, body)
	)


func _on_snap_animation_finished(
	node: Node3D,
	body: RigidBody3D
) -> void:
	if is_instance_valid(body):
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.freeze = true

	if is_instance_valid(node):
		snapping_nodes.erase(node)
		print("COMPONENT INSTALLED: ", node.name)
	else:
		print("COMPONENT INSTALLED")


# ==========================================
# CHECK SNAP
# ==========================================

func _check_snap(node: Node3D) -> void:
	if node == solar_panel:
		var distance = node.global_position.distance_to(
			panel_snap_zone.global_position
		)

		if distance < 0.8:
			panel_snapped = true
			_play_snap_animation(node, panel_snap_zone)

			if is_guided_mode():
				current_step = 2

			_update_hud_for_step()

	elif node == charge_controller:
		var distance = node.global_position.distance_to(
			controller_snap_zone.global_position
		)

		if distance < 0.8:
			controller_snapped = true
			_play_snap_animation(node, controller_snap_zone)
			_check_step_2_complete()

	elif node == inverter:
		var distance = node.global_position.distance_to(
			inverter_snap_zone.global_position
		)

		if distance < 0.8:
			inverter_snapped = true
			_play_snap_animation(node, inverter_snap_zone)
			_check_step_2_complete()

	elif node == battery_bank:
		var distance = node.global_position.distance_to(
			battery_snap_zone.global_position
		)

		if distance < 0.8:
			battery_snapped = true
			_play_snap_animation(node, battery_snap_zone)

			if is_guided_mode():
				current_step = 4

			_update_hud_for_step()

	_check_wiring_unlock()


# ==========================================
# CHECK STEP 2
# ==========================================

func _check_step_2_complete() -> void:
	if controller_snapped and controller_fastened and inverter_snapped:
		if is_guided_mode() and current_step == 2:
			current_step = 3

			print(
				"STEP 2 COMPLETE: CHARGE CONTROLLER FASTENED AND INVERTER INSTALLED"
			)

			_update_hud_for_step()


# ==========================================
# CHECK ALL COMPONENTS
# ==========================================

func _all_components_snapped() -> bool:
	return (
		panel_snapped
		and controller_snapped
		and controller_fastened
		and inverter_snapped
		and battery_snapped
	)


# ==========================================
# CHECK WIRING UNLOCK
# ==========================================

func _check_wiring_unlock() -> void:
	if not _all_components_snapped():
		return

	if current_step >= 5:
		return

	current_step = 4
	wiring_harness.visible = true

	print("ALL COMPONENTS INSTALLED")
	print("STEP 4 UNLOCKED")

	_update_hud_for_step()


# ==========================================
# UPDATE HUD
# ==========================================

func _update_hud_for_step() -> void:
	if current_step >= 6:
		simulation_active = false
		instruction_panel.visible = false
		win_screen.visible = true

		if pause_button:
			pause_button.visible = false

		_populate_performance_dashboard()
		return

	if is_free_mode():
		instruction_panel.visible = false
		return

	instruction_panel.visible = true

	match current_step:
		1:
			step_title_label.text = "Step 1 of 5: Solar Panel Mounting"
			instruction_label.text = "Aim at the PV Module and tap GRAB to pick it up. Tap DROP to position it on the aluminum mounting rails."
			safety_alert_label.text = "Handle the module by its aluminum frame. Never step on the glass."

		2:
			step_title_label.text = "Step 2 of 5: Charge Controller & Inverter Setup"
			instruction_label.text = "Aim at each component and tap GRAB to pick it up. Tap DROP to position it on the electrical mounting board."
			safety_alert_label.text = "Maintain proper clearance around inverter vents."

		3:
			step_title_label.text = "Step 3 of 5: Battery Bank Placement"
			instruction_label.text = "Aim at the Battery Bank and tap GRAB to pick it up. Tap DROP to position it below the electrical board."
			safety_alert_label.text = "Use proper lifting posture and insulated tools."

		4:
			step_title_label.text = "Step 4 of 5: Electrical Wiring"
			instruction_label.text = "Aim at a loose wire connector and tap GRAB. Then tap its assigned terminal directly on the screen. Connect both ends of every wire."
			safety_alert_label.text = "Follow the approved wiring sequence and verify polarity."

		5:
			step_title_label.text = "Step 5 of 5: Final Commissioning"
			instruction_label.text = "Review your wiring connections and tap the commissioning control to finish."
			safety_alert_label.text = "Verify all connections before proceeding."


# ==========================================
# SELECT WIRE CONNECTOR
# ==========================================

func _try_select_wire_connector(screen_position: Vector2) -> bool:
	if is_game_paused or wire_connection_animating:
		return false

	if current_step != 4 or wiring_connected:
		return false

	if is_instance_valid(active_wire_connector):
		return false

	if active_drag_node != null:
		return false

	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)

	var space_state = get_world_3d().direct_space_state

	var detection_sphere := SphereShape3D.new()
	detection_sphere.radius = 0.18

	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = detection_sphere
	shape_query.collision_mask = 1
	shape_query.collide_with_areas = true
	shape_query.collide_with_bodies = false

	for distance_step in range(5, 201, 5):
		var ray_distance: float = float(distance_step) / 10.0

		shape_query.transform = Transform3D(
			Basis.IDENTITY,
			ray_origin + ray_direction * ray_distance
		)

		var results = space_state.intersect_shape(shape_query, 32)

		for result in results:
			var collider = result.get("collider")

			if not is_instance_valid(collider):
				continue

			if not wire_area_indices.has(collider):
				continue

			var data: Dictionary = wire_area_indices[collider]

			var detected_index: int = data["index"]
			var is_start: bool = data["is_start"]

			if detected_index < 0 or detected_index >= wire_nodes.size():
				continue

			if is_guided_mode() and detected_index != wire_task_index:
				continue

			var connector: Node3D
			var marker: Marker3D
			var target_node: Node3D

			if is_start:
				if wire_start_connected[detected_index]:
					continue

				connector = wire_start_connectors[detected_index]
				marker = wire_start_markers[detected_index]
				target_node = wire_start_targets[detected_index]
			else:
				if wire_end_connected[detected_index]:
					continue

				connector = wire_end_connectors[detected_index]
				marker = wire_end_markers[detected_index]
				target_node = wire_end_targets[detected_index]

			if not is_instance_valid(target_node):
				printerr("WIRE DESTINATION NOT ASSIGNED: ", wire_names[detected_index])
				continue

			if not is_instance_valid(connector) or not is_instance_valid(marker):
				continue

			active_wire_index = detected_index
			active_wire_is_start = is_start
			active_wire_connector = connector
			active_wire_marker = marker

			_update_grab_button_label()

			print(
				"WIRE SELECTED: ",
				wire_names[detected_index],
				" | ",
				"START" if is_start else "END"
			)

			print("TAP TERMINAL: ", target_node.name)
			_focus_camera_on_terminal(target_node)

			return true

	print("WIRE MISS: NO AVAILABLE CONNECTOR FOUND")
	return false


# ==========================================
# CONNECT SELECTED WIRE
# ==========================================

func _connect_selected_wire(detected_target: Node3D) -> void:
	if is_game_paused or wire_connection_animating:
		return

	if not is_instance_valid(active_wire_connector):
		return

	if not is_instance_valid(active_wire_marker):
		_clear_wire_selection()
		return

	if not is_instance_valid(detected_target):
		return

	var index: int = active_wire_index
	var is_start: bool = active_wire_is_start

	if index < 0 or index >= wire_nodes.size():
		_clear_wire_selection()
		return

	var target_node: Node3D

	if is_start:
		target_node = wire_start_targets[index]
	else:
		target_node = wire_end_targets[index]

	if not is_instance_valid(target_node):
		printerr("WIRE TARGET NOT FOUND: ", wire_names[index])
		return

	if detected_target != target_node:
		safety_violations_count += 1

		print("INCORRECT TERMINAL!")
		print("EXPECTED: ", target_node.name)
		print("DETECTED: ", detected_target.name)

		if is_guided_mode():
			safety_alert_label.text = "Incorrect terminal! Check the wiring sequence and polarity."

		return

	print("CORRECT TERMINAL DETECTED: ", target_node.name)

	await _play_wire_connection_animation(
		index,
		is_start,
		target_node
	)

	await _return_camera_from_terminal_focus()


# ==========================================
# CINEMATIC WIRE CONNECTION ANIMATION
# ==========================================

func _play_wire_connection_animation(
	index: int,
	is_start: bool,
	target_node: Node3D
) -> void:
	if wire_connection_animating:
		return

	if not is_instance_valid(active_wire_marker):
		return

	wire_connection_animating = true

	if grab_button:
		grab_button.disabled = true

	_update_grab_button_label()

	var marker_to_animate: Marker3D = active_wire_marker

	var target_position: Vector3 = target_node.global_position

	print("CINEMATIC WIRE CONNECTION STARTED: ", wire_names[index])

	var approach_position: Vector3 = (
		marker_to_animate.global_position
		.lerp(target_position, 0.35)
		+ Vector3.UP * 0.06
	)

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(
		marker_to_animate,
		"global_position",
		approach_position,
		wire_connection_duration * 0.35
	)

	tween.tween_property(
		marker_to_animate,
		"global_position",
		target_position,
		wire_connection_duration * 0.65
	)

	await tween.finished

	if not is_instance_valid(marker_to_animate):
		wire_connection_animating = false

		if grab_button:
			grab_button.disabled = false

		_clear_wire_selection()
		return

	marker_to_animate.global_position = target_position

	if is_start:
		wire_start_connected[index] = true
		print("WIRE START CONNECTED: ", wire_names[index])
	else:
		wire_end_connected[index] = true
		print("WIRE END CONNECTED: ", wire_names[index])

	wire_connection_animating = false

	if grab_button:
		grab_button.disabled = false

	_clear_wire_selection()

	var both_ends_connected: bool = (
		wire_start_connected[index]
		and wire_end_connected[index]
	)

	if both_ends_connected:
		print("COMPLETE WIRE: ", wire_names[index])

		if is_guided_mode():
			wire_task_index += 1

			if wire_task_index < wire_nodes.size():
				print("NEXT WIRE: ", wire_names[wire_task_index])
			else:
				print("ALL GUIDED WIRE TASKS COMPLETED")
	else:
		print("CONNECT THE OTHER END OF: ", wire_names[index])

	if _all_wires_connected():
		complete_wiring()


# ==========================================
# CLEAR WIRE SELECTION
# ==========================================

func _clear_wire_selection() -> void:
	active_wire_connector = null
	active_wire_marker = null

	active_wire_index = -1
	active_wire_is_start = false

	grab_button_held = false

	_update_grab_button_label()


# ==========================================
# CHECK ALL WIRES
# ==========================================

func _all_wires_connected() -> bool:
	for i in range(wire_nodes.size()):
		if not wire_start_connected[i]:
			return false

		if not wire_end_connected[i]:
			return false

	return true


# ==========================================
# COMPLETE WIRING
# ==========================================

func complete_wiring() -> void:
	if not _all_components_snapped():
		return

	if current_step != 4 or wiring_connected:
		return

	if not _all_wires_connected():
		printerr("WIRING INCOMPLETE")
		return

	wiring_connected = true
	current_step = 5

	_clear_wire_selection()

	print("ALL SIX WIRES CONNECTED")
	print("STEP 5 UNLOCKED")

	_update_hud_for_step()


# ==========================================
# FINAL COMMISSIONING
# ==========================================

func _on_step_4_clicked(
	_camera: Node,
	event: InputEvent,
	_pos: Vector3,
	_normal: Vector3,
	_shape_idx: int
) -> void:
	if event is InputEventScreenTouch:
		if not event.pressed:
			return
	elif event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
			return
	else:
		return

	_complete_final_commissioning()


func _complete_final_commissioning() -> void:
	if is_game_paused or current_step != 5 or not wiring_connected:
		return

	if not _all_components_snapped() or not _all_wires_connected():
		printerr("COMMISSIONING BLOCKED: INSTALLATION OR WIRING INCOMPLETE")
		return

	current_step = 6
	print("FINAL COMMISSIONING COMPLETED")
	_update_hud_for_step()


# ==========================================
# PERFORMANCE DASHBOARD
# ==========================================

func _populate_performance_dashboard() -> void:
	var accuracy = clamp(
		100.0 - (safety_violations_count * 15.0),
		0.0,
		100.0
	)

	if accuracy_label:
		accuracy_label.text = "Procedural Accuracy: " + str(
			int(accuracy)
		) + "%"

	if time_label:
		time_label.text = "Completion Time: " + String.num(
			simulation_timer,
			1
		) + " seconds"

	if feedback_label:
		feedback_label.text = "[b]SOLARAW Simulation Report:[/b]\n- All required components installed.\n- Required wiring connections completed.\n- Final commissioning stage completed."


# ==========================================
# PAUSE BUTTON
# ==========================================

func _on_pause_button_pressed() -> void:
	if not simulation_active:
		return

	if is_game_paused:
		_on_resume_button_pressed()
		return

	is_game_paused = true

	if is_instance_valid(active_wire_connector):
		_clear_wire_selection()

	if active_drag_node != null:
		_finish_component_drag()

	grab_button_held = false
	_update_grab_button_label()

	if pause_menu:
		pause_menu.visible = true

	get_tree().paused = true

	print("SOLARAW PAUSED")


# ==========================================
# RESUME BUTTON
# ==========================================

func _on_resume_button_pressed() -> void:
	is_game_paused = false
	get_tree().paused = false

	if pause_menu:
		pause_menu.visible = false

	_update_hud_for_step()
	print("SOLARAW RESUMED")


# ==========================================
# MAIN MENU BUTTON
# ==========================================

func _on_main_menu_button_pressed() -> void:
	get_tree().paused = false
	is_game_paused = false

	if main_menu_scene_path.is_empty():
		printerr("MAIN MENU SCENE PATH NOT ASSIGNED")
		return

	if not ResourceLoader.exists(main_menu_scene_path):
		printerr("MAIN MENU SCENE NOT FOUND: ", main_menu_scene_path)
		return

	get_tree().change_scene_to_file(main_menu_scene_path)


# ==========================================
# RESTART
# ==========================================

func _on_restart_pressed() -> void:
	get_tree().paused = false
	is_game_paused = false

	get_tree().reload_current_scene()


# ==========================================
# MOBILE PLAYER MOVEMENT
# ==========================================

func apply_mobile_controls(delta: float) -> void:
	if is_game_paused or _is_fastening_active() or terminal_camera_mode:
		return

	var move_input: Vector2 = move_joystick.output

	var forward: Vector3 = -camera_pivot.global_basis.z
	var right: Vector3 = camera_pivot.global_basis.x

	forward.y = 0.0
	right.y = 0.0

	forward = forward.normalized()
	right = right.normalized()

	var move_direction: Vector3 = (
		right * move_input.x
		+ forward * -move_input.y
	)

	if move_direction.length() > 1.0:
		move_direction = move_direction.normalized()

	player.velocity.x = move_direction.x * move_speed
	player.velocity.z = move_direction.z * move_speed

	if not player.is_on_floor():
		player.velocity.y -= gravity * delta
	else:
		if player.velocity.y < 0.0:
			player.velocity.y = 0.0

	player.move_and_slide()

	var look_input: Vector2 = look_joystick.output

	camera_pivot.rotate_y(
		-look_input.x * look_sensitivity * delta
	)

	camera_pitch -= look_input.y * look_sensitivity * delta

	camera_pitch = clamp(
		camera_pitch,
		deg_to_rad(-60.0),
		deg_to_rad(60.0)
	)

	camera.rotation.x = camera_pitch
