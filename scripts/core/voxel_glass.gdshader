shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// DELEGATE - see-through glass. Water has its own shader (voxel_water.gdshader)
// because it reads the depth buffer and glass should not pay for that.
// Everything else uses voxel.gdshader and stays in the opaque pass.

#define USE_PBR_TEXTURES

#include "res://scripts/core/voxel_common.gdshaderinc"

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	VoxelSurface s = voxel_shade(COLOR.rgb, CAMERA_POSITION_WORLD);
	vec3 view = normalize(CAMERA_POSITION_WORLD - world_pos);
	// Glass is clearest looking straight through and turns into a mirror at a
	// glancing angle: fresnel raises both the opacity and a pale sky sheen.
	float fres = 0.04 + 0.96 * pow(1.0 - clamp(abs(dot(view, world_nrm)), 0.0, 1.0), 4.0);
	ALBEDO = mix(s.albedo, sky_reflect * 0.9, fres * 0.6);
	ROUGHNESS = s.roughness;
	METALLIC = s.metallic;
	SPECULAR = 0.6;
	EMISSION = s.emission;
	ALPHA = clamp(s.alpha + fres * 0.55, 0.0, 1.0);
	if (s.custom_normal) {
		NORMAL = normalize((VIEW_MATRIX * vec4(s.normal_world, 0.0)).xyz);
	}
}
