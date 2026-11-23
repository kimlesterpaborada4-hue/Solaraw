
extends MeshInstance3D

@onready var start_marker: Marker3D = $StartMarker
@onready var end_marker: Marker3D = $EndMarker

# CABLE APPEARANCE
@export var cable_radius: float = 0.025
@export_range(4, 100) var segments: int = 40
@export_range(4, 16) var radial_segments: int = 8

# ROPE PHYSICS
@export var cable_slack_ratio: float = 1.12
@export var extra_cable_length: float = 3.0
@export var gravity_strength: float = 5.0
@export_range(0.0, 1.0) var damping: float = 0.94
@export_range(1, 20) var constraint_iterations: int = 12
@export_range(0.1, 1.0) var constraint_stiffness: float = 1.0

# ENVIRONMENT COLLISION
@export_group("Environment Collision")
@export var enable_environment_collision: bool = false
@export_flags_3d_physics var environment_collision_mask: int = 1
@export var collision_radius_multiplier: float = 1.2
@export_range(1, 5) var collision_iterations: int = 2

# ROPE DATA
var rope_points: PackedVector3Array = PackedVector3Array()
var previous_points: PackedVector3Array = PackedVector3Array()

var rest_segment_length: float = 0.0
var max_endpoint_distance: float = 5.0
var rope_initialized: bool = false
var gravity_vector: Vector3 = Vector3.DOWN
var rope_collision_shape: SphereShape3D


func _ready() -> void:
	rope_collision_shape = SphereShape3D.new()
	rope_collision_shape.radius = cable_radius * collision_radius_multiplier
	_initialize_rope()


func _physics_process(delta: float) -> void:
	if not rope_initialized:
		return

	_simulate_rope(delta)
	_update_cable_mesh()


# INITIALIZE ROPE

func _initialize_rope() -> void:
	rope_points.clear()
	previous_points.clear()

	if not is_instance_valid(start_marker):
		return

	if not is_instance_valid(end_marker):
		return

	var start_position: Vector3 = to_local(start_marker.global_position)
	var end_position: Vector3 = to_local(end_marker.global_position)

	var initial_distance: float = start_position.distance_to(end_position)

	max_endpoint_distance = maxf(
		initial_distance * cable_slack_ratio,
		initial_distance + extra_cable_length
	)

	max_endpoint_distance = maxf(max_endpoint_distance, 0.5)
	rest_segment_length = max_endpoint_distance / float(segments)

	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		var point: Vector3 = start_position.lerp(end_position, t)

		var sag_amount: float = extra_cable_length * 0.25
		point.y -= sin(t * PI) * sag_amount

		rope_points.append(point)
		previous_points.append(point)

	rope_points[0] = start_position
	rope_points[segments] = end_position
	previous_points[0] = start_position
	previous_points[segments] = end_position

	rope_initialized = true
	_update_cable_mesh()


# LIMIT MOVEMENT OF EITHER ENDPOINT

func constrain_endpoint(
	requested_position: Vector3,
	moving_start: bool = false
) -> Vector3:

	if not rope_initialized:
		return requested_position

	var fixed_position: Vector3

	if moving_start:
		fixed_position = end_marker.global_position
	else:
		fixed_position = start_marker.global_position

	var difference: Vector3 = requested_position - fixed_position
	var distance: float = difference.length()

	if distance > max_endpoint_distance and distance > 0.0001:
		return fixed_position + difference.normalized() * max_endpoint_distance

	return requested_position


# ROPE SIMULATION

func _simulate_rope(delta: float) -> void:
	if rope_points.size() != segments + 1:
		return

	var start_position: Vector3 = to_local(start_marker.global_position)
	var end_position: Vector3 = to_local(end_marker.global_position)

	gravity_vector = global_transform.basis.inverse() * Vector3.DOWN
	var gravity: Vector3 = gravity_vector.normalized() * gravity_strength

	# VERLET INTEGRATION

	for i in range(1, segments):
		var current_position: Vector3 = rope_points[i]
		var old_position: Vector3 = previous_points[i]

		var velocity: Vector3 = (current_position - old_position) * damping
		previous_points[i] = current_position

		rope_points[i] = (
			current_position
			+ velocity
			+ gravity * delta * delta
		)

	# FIX BOTH ENDPOINTS

	rope_points[0] = start_position
	rope_points[segments] = end_position
	previous_points[0] = start_position
	previous_points[segments] = end_position

	# LENGTH CONSTRAINTS

	for iteration in range(constraint_iterations):
		rope_points[0] = start_position
		rope_points[segments] = end_position

		for i in range(segments):
			var difference: Vector3 = rope_points[i + 1] - rope_points[i]
			var distance: float = difference.length()

			if distance <= rest_segment_length or distance < 0.0001:
				continue

			var error: float = distance - rest_segment_length
			var correction: Vector3 = (
				difference.normalized()
				* error
				* constraint_stiffness
			)

			if i == 0:
				rope_points[i + 1] -= correction
			elif i + 1 == segments:
				rope_points[i] += correction
			else:
				rope_points[i] += correction * 0.5
				rope_points[i + 1] -= correction * 0.5

	# OPTIONAL ENVIRONMENT COLLISION

	if enable_environment_collision:
		for iteration in range(collision_iterations):
			for i in range(1, segments):
				rope_points[i] = _resolve_environment_collision(rope_points[i])

	rope_points[0] = start_position
	rope_points[segments] = end_position
	previous_points[0] = start_position
	previous_points[segments] = end_position


# ENVIRONMENT COLLISION

func _resolve_environment_collision(local_point: Vector3) -> Vector3:
	if not enable_environment_collision:
		return local_point

	var world: World3D = get_world_3d()
	if world == null:
		return local_point

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = rope_collision_shape
	query.transform = Transform3D(Basis.IDENTITY, to_global(local_point))
	query.collision_mask = environment_collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result: Dictionary = world.direct_space_state.get_rest_info(query)

	if result.is_empty():
		return local_point

	var contact_point: Vector3 = result["point"]
	var contact_normal: Vector3 = result["normal"]

	if contact_normal.length_squared() < 0.001:
		return local_point

	var corrected_position: Vector3 = (
		contact_point
		+ contact_normal.normalized() * rope_collision_shape.radius
	)

	return to_local(corrected_position)


# UPDATE CABLE MESH

func _update_cable_mesh() -> void:
	if rope_points.size() < 2:
		return

	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(rope_points.size()):
		var tangent: Vector3

		if i == 0:
			tangent = rope_points[i + 1] - rope_points[i]
		elif i == rope_points.size() - 1:
			tangent = rope_points[i] - rope_points[i - 1]
		else:
			tangent = rope_points[i + 1] - rope_points[i - 1]

		if tangent.length_squared() < 0.0001:
			tangent = Vector3.FORWARD

		tangent = tangent.normalized()

		var side: Vector3 = tangent.cross(Vector3.UP)

		if side.length_squared() < 0.001:
			side = tangent.cross(Vector3.RIGHT)

		side = side.normalized()
		var up: Vector3 = tangent.cross(side).normalized()

		for j in range(radial_segments):
			var angle: float = (
				float(j) / float(radial_segments)
			) * TAU

			var normal: Vector3 = (
				side * cos(angle)
				+ up * sin(angle)
			).normalized()

			var vertex: Vector3 = rope_points[i] + normal * cable_radius

			surface_tool.set_normal(normal)
			surface_tool.add_vertex(vertex)

	for i in range(segments):
		for j in range(radial_segments):
			var current: int = i * radial_segments + j
			var next: int = i * radial_segments + (j + 1) % radial_segments
			var next_ring_current: int = (i + 1) * radial_segments + j
			var next_ring_next: int = (
				(i + 1) * radial_segments
				+ (j + 1) % radial_segments
			)

			surface_tool.add_index(current)
			surface_tool.add_index(next)
			surface_tool.add_index(next_ring_current)

			surface_tool.add_index(next)
			surface_tool.add_index(next_ring_next)
			surface_tool.add_index(next_ring_current)

	mesh = surface_tool.commit()


# RESET ROPE

func reset_rope() -> void:
	rope_initialized = false
	rope_points.clear()
	previous_points.clear()
	_initialize_rope()
