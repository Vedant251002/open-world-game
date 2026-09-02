extends Object
## Runtime pastel tinting for GLB kit models — gives every building/car its own
## Vice-City color while preserving the kit's baked textures and shading.


static func tint(node: Node, target: Color, amount: float = 0.62) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh != null:
			var mi: MeshInstance3D = child
			for i in range(mi.mesh.get_surface_count()):
				var mat = mi.mesh.surface_get_material(i)
				if mat is StandardMaterial3D:
					var m: StandardMaterial3D = mat.duplicate()
					m.albedo_color = m.albedo_color.lerp(target, amount)
					mi.set_surface_override_material(i, m)
		elif child is Node:
			tint(child, target, amount)
