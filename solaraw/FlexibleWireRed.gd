
extends MeshInstance3D

@onready var start_marker: Marker3D = $RedWireStart
@onready var end_marker: Marker3D = $RedWireEnd

@onready var panel_positive: Marker3D = get_node("/root/SimulationWorkspace/SolarPanel_1/Panel_Positive_Terminal")

@export var cable_radius: float = 0.025
@export var cable_sag: float = 0.15
@export var segments: int = 32
@export var radial_segments: int = 8

var cable_material: StandardMaterial3D


func _ready() -> void:
	cable_material = StandardMaterial3D.new()
	cable_material.albedo_color = Color(0.85, 0.02, 0.01)
	cable_material.roughness = 0.65

	material_override = cable_material

	update_cable()


func _process(_delta: float) -> void:
	start_marker.global_position = panel_positive.global_position
	update_cable()


func update_cable() -> void:
	if not is_instance_valid(start_marker):
		return

	if not is_instance_valid(end_marker):
		return

	var start_pos: Vector3 = to_local(start_marker.global_position)
	var end_pos: Vector3 = to_local(end_marker.global_position)

	var direction: Vector3 = end_pos - start_pos

	if direction.length() < 0.001:
		mesh = null
		return

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	var tangent: Vector3 = direction.normalized()
	var side: Vector3 = tangent.cross(Vector3.UP).normalized()

	if side.length() < 0.001:
		side = Vector3.RIGHT

	var up: Vector3 = tangent.cross(side).normalized()

	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		var point: Vector3 = start_pos.lerp(end_pos, t)

		point.y -= cable_sag * 4.0 * t * (1.0 - t)

		for j in range(radial_segments + 1):
			var angle: float = float(j) / float(radial_segments) * TAU

			var offset: Vector3 = (
				side * cos(angle) + up * sin(angle)
			) * cable_radius

			surface.add_vertex(point + offset)

	for i in range(segments):
		for j in range(radial_segments):
			var a: int = i * (radial_segments + 1) + j
			var b: int = a + radial_segments + 1
			var c: int = b + 1
			var d: int = a + 1

			surface.add_index(a)
			surface.add_index(c)
			surface.add_index(b)

			surface.add_index(a)
			surface.add_index(d)
			surface.add_index(c)

	surface.generate_normals()
	surface.set_material(cable_material)

	mesh = surface.commit()
