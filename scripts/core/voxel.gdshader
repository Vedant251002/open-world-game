shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// DELEGATE - opaque world voxels.
//
// Deliberately never assigns ALPHA. Godot decides which pass a material belongs
// to by whether the shader writes ALPHA at all, and a single shader that always
// wrote it put all four hundred chunk meshes into the transparent pass, losing
// the depth prepass, early-Z and correct sorting in one go.

#include "res://scripts/core/voxel_common.gdshaderinc"

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	VoxelSurface s = voxel_shade(COLOR.rgb, CAMERA_POSITION_WORLD);
	ALBEDO = s.albedo;
	ROUGHNESS = s.roughness;
	METALLIC = s.metallic;
	SPECULAR = s.specular;
	EMISSION = s.emission;
	if (s.custom_normal) {
		NORMAL = normalize((VIEW_MATRIX * vec4(s.normal_world, 0.0)).xyz);
	}
}
