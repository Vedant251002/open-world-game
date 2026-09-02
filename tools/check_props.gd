extends SceneTree

func _init() -> void:
	var l := DirectionalLight3D.new()
	var names := []
	for p in l.get_property_list():
		if "shadow" in p["name"]:
			names.append(p["name"])
	print("SHADOW_PROPS ", names)
	quit()
