shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// DELEGATE - water.
//
// Animated wave normals, fresnel, a self-contained sky reflection and sun
// glitter (all in voxel_common.gdshaderinc), plus depth-based colour: the water
// column under each pixel is measured from the scene depth texture, so the
// shallows go turquoise and transparent with a foam line where they meet the
// shore, and the deep goes dark blue. Reading the depth texture works in the
// compatibility renderer too; only the depth range differs, which is what the
// depth_ndc uniform corrects for (set by VoxelMaterials).

#define USE_PBR_TEXTURES

#include "res://scripts/core/voxel_common.gdshaderinc"

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
// ndc.z = depth * x + y. Forward+/Mobile: (1, 0). Compatibility: (2, -1).
uniform vec2 depth_ndc = vec2(1.0, 0.0);
uniform float wave_height : hint_range(0.0, 0.1) = 0.012;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// A gentle swell on the surface itself. A function of world position only,
	// so neighbouring water quads always agree on their shared edge.
	float w = sin(world_pos.x * 1.3 + world_pos.z * 0.9 + TIME * 1.1)
		+ sin(world_pos.x * 0.7 - world_pos.z * 1.7 + TIME * 0.8);
	VERTEX.y += w * wave_height * step(0.5, NORMAL.y);
}

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, d * depth_ndc.x + depth_ndc.y);
	vec4 scene = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float scene_z = scene.z / scene.w;
	// View space looks down -z, so the terrain behind the water is more
	// negative than the water's own fragment.
	float thick = max(VERTEX.z - scene_z, 0.0);

	VoxelSurface s = water_shade(COLOR.rgb, CAMERA_POSITION_WORLD, thick, vec3(0.1));
	ALBEDO = s.albedo;
	ROUGHNESS = s.roughness;
	METALLIC = 0.0;
	SPECULAR = s.specular;
	EMISSION = s.emission;
	ALPHA = s.alpha;
	NORMAL = normalize((VIEW_MATRIX * vec4(s.normal_world, 0.0)).xyz);
}
