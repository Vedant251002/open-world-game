shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// DELEGATE - opaque world voxels.
//
// Deliberately never assigns ALPHA. Godot decides which pass a material belongs
// to by whether the shader writes ALPHA at all, and a single shader that always
// wrote it put all four hundred chunk meshes into the transparent pass, losing
// the depth prepass, early-Z and correct sorting in one go.

#define USE_PBR_TEXTURES

#include "res://scripts/core/voxel_common.gdshaderinc"

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (wave_amount > 0.0) {
		// Leaves sway. The offset is a smooth function of world position, so
		// two leaf voxels sharing a corner move it identically and no crack can
		// open between them. Chunk meshes are only translated, never rotated,
		// so a world-space offset can be added to the local vertex directly.
		VERTEX += wind_offset(world_pos, TIME) * wave_amount;
	}
}

void fragment() {
	VoxelSurface s = voxel_shade(COLOR.rgb, CAMERA_POSITION_WORLD);
	ALBEDO = s.albedo;
	ROUGHNESS = s.roughness;
	METALLIC = s.metallic;
	SPECULAR = s.specular;
	EMISSION = s.emission;
	AO = s.ao;
	AO_LIGHT_AFFECT = 0.25;
	if (backlight_amount > 0.0) {
		BACKLIGHT = s.backlight;
	}
	if (s.custom_normal) {
		NORMAL = normalize((VIEW_MATRIX * vec4(s.normal_world, 0.0)).xyz);
	}
}
