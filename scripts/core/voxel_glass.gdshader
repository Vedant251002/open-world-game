shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// DELEGATE - the only two see-through world materials, glass and water.
// Everything else uses voxel.gdshader and stays in the opaque pass.

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
	ALPHA = s.alpha;
	if (s.custom_normal) {
		NORMAL = normalize((VIEW_MATRIX * vec4(s.normal_world, 0.0)).xyz);
	}
}
