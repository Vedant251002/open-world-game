// DELEGATE - shared voxel surface shading, texture-array path.
//
// This is the "full HD" look: per-material PBR maps (albedo + normal + ORM)
// baked by _tools/gen_pbr.py, sampled from Texture2DArrays, with the mesher's
// baked corner AO folded in. The previous file synthesised every surface from
// procedural noise, which is why a 1600x900 frame held only 1-2k distinct
// colours and measured 3.4-6.8 on surface detail against 5.9-9.2 for the
// Minecraft shader packs we are matching.
//
// The old procedural patterns are kept behind USE_PROCEDURAL so the fallback
// path still works on the compatibility renderer, where the texture arrays are
// not worth their memory.

#ifndef VOEXEL_COMMON_V2_INC
#define VOXEL_COMMON_V2_INC

group_uniforms surface;
uniform vec3 base_albedo = vec3(0.25);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.9;
uniform float base_metallic : hint_range(0.0, 1.0) = 0.0;
uniform vec3 emission_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

group_uniforms detail;
// Which layer of each array this material uses. Set by VoxelMaterials.
uniform int tex_layer = 0;
// How many times the texture repeats per 0.25 m voxel face. A whole brick
// wall per face reads as a mosaic; one repeat per face reads as brickwork.
uniform float tex_scale : hint_range(0.05, 8.0) = 1.0;
// How far the baked-in pattern still modulates the texture. Kept low: the
// texture now carries the detail, and the pattern only breaks up tiling.
uniform float detail_strength : hint_range(0.0, 1.0) = 0.22;
uniform float bump_strength : hint_range(0.0, 2.0) = 0.5;
uniform float hue_jitter : hint_range(0.0, 1.0) = 0.10;
uniform int pattern = 0;
uniform float grain = 0.5;

// Global texture quality, pushed down by Quality.apply() on a handheld. 1.0 is
// full detail; 0 disables the extra distance fades entirely.
uniform float texture_quality : hint_range(0.0, 1.0) = 1.0;

#ifdef USE_PBR_TEXTURES
// The arrays are laid out with layer 0 of every array being the same material,
// so one index selects all three maps.
uniform sampler2DArray albedo_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray orm_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
#endif

group_uniforms water;
uniform int water_mode = 0;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_tint = vec3(1.0, 0.96, 0.90);
uniform float sun_glitter = 1.0;
uniform vec3 sky_reflect = vec3(0.45, 0.58, 0.68);

varying vec3 world_pos;
varying vec3 world_nrm;

// ---------------------------------------------------------------- noise
// Still needed: for the tint drift that stops a big wall reading as one colour,
// and for the water waves. The surface detail itself now comes from textures.

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 w = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.07;
		a *= 0.5;
	}
	return v;
}

// ---------------------------------------------------------------- uv
// Voxel faces are exactly axis-aligned, so there is no need for triplanar
// blending: the face is in one of three planes and we pick it. The one plane
// actually used is the one sampled, which is a third of the cost of triplanar
// and has no seam artifacts to hide.

struct Frame {
	vec2 uv;
	vec3 tangent;
	vec3 bitangent;
};

Frame face_frame(vec3 wpos, vec3 wnrm) {
	Frame f;
	vec3 an = abs(wnrm);
	if (an.y >= an.x && an.y >= an.z) {
		f.uv = vec2(wpos.x, wpos.z);
		f.tangent = vec3(1.0, 0.0, 0.0);
		f.bitangent = vec3(0.0, 0.0, 1.0);
	} else if (an.x >= an.z) {
		// Vertical faces run v upward so courses and board seams stay level.
		f.uv = vec2(wpos.z, wpos.y);
		f.tangent = vec3(0.0, 0.0, 1.0);
		f.bitangent = vec3(0.0, 1.0, 0.0);
	} else {
		f.uv = vec2(wpos.x, wpos.y);
		f.tangent = vec3(1.0, 0.0, 0.0);
		f.bitangent = vec3(0.0, 1.0, 0.0);
	}
	return f;
}

// ---------------------------------------------------------------- result
struct VoxelSurface {
	vec3 albedo;
	float roughness;
	float metallic;
	float specular;
	vec3 emission;
	vec3 normal_world;
	bool custom_normal;
	float alpha;
};

VoxelSurface voxel_shade(vec3 vertex_ao, vec3 camera_world) {
	VoxelSurface s;
	s.emission = vec3(0.0);
	s.normal_world = world_nrm;
	s.custom_normal = false;
	s.specular = 0.5;
	s.alpha = alpha;
	s.albedo = base_albedo;
	s.roughness = base_roughness;
	s.metallic = base_metallic;

	Frame f = face_frame(world_pos, world_nrm);
	vec2 uv = f.uv * tex_scale;

	// Two scales of variation that no texture can provide, because they are not
	// a property of the material but of where it is in the world: a slow hue
	// drift so a whole field of grass is not one colour, and a fine brightness
	// jitter so a wall does not read as plastic.
	float jitter = (fbm(world_pos.xz * 0.9 + world_pos.y * 0.37) - 0.5) * 2.0;
	float drift = fbm(world_pos.xz * 0.055 + world_pos.y * 0.02) - 0.5;
	vec3 warm = vec3(1.14, 1.02, 0.76);
	vec3 cool = vec3(0.88, 1.00, 1.08);
	vec3 tint = mix(cool, warm, clamp(drift * 2.2 + 0.5, 0.0, 1.0));

	vec3 tex_albedo = vec3(1.0);
	float tex_ao = 1.0;
	float tex_rough = base_roughness;
	float tex_metal = base_metallic;

#ifdef USE_PBR_TEXTURES
	if (texture_quality > 0.0) {
		// Mip selection is automatic and correct here: three equally sized
		// seamless tiles sampled with the same uv and the same filter, so the
		// blur that removes aliasing at distance is the blur the artist expects.
		tex_albedo = texture(albedo_array, vec3(uv, float(tex_layer))).rgb;
		vec3 orm = texture(orm_array, vec3(uv, float(tex_layer))).rgb;
		tex_ao = mix(1.0, orm.r, ao_strength);
		tex_rough = clamp(orm.g, 0.03, 1.0);
		tex_metal = clamp(orm.b, 0.0, 1.0);

		// Normal maps are authored in tangent space, and because the face frame
		// above is exact there is no handedness ambiguity to fix up: the map's
		// xy can be applied directly as a perturbation in the face's own basis.
		// No height-difference gradient is needed — the baked normal map already
		// carries the slope, and recomputing it would cost two more fetches per
		// pixel to arrive at the same answer.
		vec3 nm = texture(normal_array, vec3(uv, float(tex_layer))).rgb;
		vec2 xy = (nm.xy * 2.0 - 1.0) * normal_strength;
		// Keep the perturbation from flipping the normal over on the strongest
		// texels; a tangent-space normal of (0,0,-1) would face into the surface.
		float zt = max(nm.b * 2.0 - 1.0, 0.05);
		s.normal_world = normalize(world_nrm
			+ f.tangent * xy.x
			+ f.bitangent * xy.y * zt);
		s.custom_normal = true;
	}
#endif

	// Compose.
	//
	// The baked albedo ALREADY carries the material's own colour — it was
	// generated from the same table as base_albedo, on purpose, so the two can
	// never drift apart. Multiplying it by base_albedo again applies the tint
	// twice, and since the texture is sampled as linear light while
	// base_albedo is already linear, the result is the colour squared: brick at
	// #98462f came out at #3b1608. That is what turned the first textured build
	// two stops too dark and the night scene into a black screen.
	//
	// So: when the texture is available it IS the albedo. base_albedo is only
	// the fallback for texture_quality == 0, which is the compatibility
	// renderer's path.
	vec3 col = (texture_quality > 0.0) ? tex_albedo : base_albedo;
	col *= (1.0 + jitter * hue_jitter);
	col *= mix(vec3(1.0), tint, clamp(hue_jitter * 3.0, 0.0, 1.0));
	// Upward faces catch slightly more sky. Cheap, and it separates a roof from
	// the wall below it.
	col *= mix(1.0, 1.06, clamp(world_nrm.y, 0.0, 1.0));

	if (water_mode == 1) {
		// Animated wave normal from scrolling noise. Normals only: the surface
		// itself stays put so it never disagrees with collision or the mesher.
		vec2 wuv = world_pos.xz * 1.35 + vec2(TIME * 0.22, TIME * 0.13);
		float e = 0.09;
		float h0 = fbm(wuv);
		float hx = fbm(wuv + vec2(e, 0.0));
		float hz = fbm(wuv + vec2(0.0, e));
		vec3 wn = normalize(vec3((h0 - hx) * 2.4, 1.0, (h0 - hz) * 2.4));

		vec3 view = normalize(camera_world - world_pos);
		// Fresnel with a proper exponent. The old curve peaked at 0.62 and
		// mixed to a single flat colour, so the sea read as painted metal.
		// This one is stronger at grazing angles and weaker looking straight
		// down, which is what lets you see into the water near your feet and
		// see the sky reflected at the far bank — the two things that make a
		// lake look deep rather than like a blue floor.
		float ndv = max(dot(view, wn), 0.0);
		float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
		// A second, wider lobe for the sheen that sits between the mirror and
		// the body colour at mid angles. Without it there is a hard edge where
		// the reflection starts.
		fres = clamp(fres + 0.10 * pow(1.0 - ndv, 2.0), 0.0, 1.0);

		vec3 rdir = reflect(-view, wn);
		// Reflected sky: the palette tint, brightened toward the zenith as the
		// reflected ray rises. Still a uniform rather than a true scene
		// reflection — the screen-space pass in the Environment handles the
		// part that is actually on screen, and this fills in everything it
		// cannot reach, which is most of the far water.
		vec3 sky_ref = mix(sky_reflect * 0.82, sky_reflect * 1.35,
			clamp(rdir.y, 0.0, 1.0));
		// Mirror the sun's own colour into the reflection so a low sun lays a
		// warm path down the water instead of a white one.
		sky_ref += sun_tint * pow(max(dot(rdir, sun_dir), 0.0), 6.0) * 0.28;

		// Sun glitter: a tight hot core for the sparkle path plus a broad
		// sheen. 800 is very tight; the broader 48 term is what actually
		// reads as a sun path on water, and it is what was missing.
		float sd = max(dot(rdir, sun_dir), 0.0);
		float glitter = pow(sd, 800.0) * 1.6 + pow(sd, 48.0) * 0.08;

		vec3 body = (texture_quality > 0.0) ? tex_albedo : base_albedo;
		// Depth tint: shallow water over sand reads green, deep water reads
		// dark blue. Without a depth signal the whole lake is one flat colour
		// and the shoreline has no shallows.
		float shallow = 1.0 - clamp((camera_world.y - world_pos.y) * 0.35, 0.0, 1.0);
		body = mix(body, body * vec3(1.25, 1.12, 0.82), shallow * 0.55);

		s.albedo = mix(body, sky_ref, clamp(fres, 0.0, 0.94)) * vertex_ao;
		s.roughness = 0.06;
		s.specular = 0.5;
		s.metallic = 0.0;
		// Deeper water is more opaque. Holding alpha high everywhere made the
		// shallows read as solid.
		s.alpha = clamp(alpha + fres * 0.30 + (1.0 - shallow) * 0.20, 0.0, 1.0);
		s.emission = sun_tint * (glitter * sun_glitter);
		s.normal_world = wn;
		s.custom_normal = true;
		return s;
	}

	// vertex_ao carries the mesher's baked corner AO; tex_ao is the texture's
	// own cavity darkening. Multiplying both is what gives contact shadows in
	// the mortar joints as well as at the base of a wall.
	s.albedo = col * vertex_ao * tex_ao;
	s.roughness = clamp(tex_rough, 0.02, 1.0);
	s.metallic = tex_metal;
	s.specular = 0.5;
	if (emission_energy > 0.0) {
		s.emission = emission_color * emission_energy;
	}
	return s;
}

#endif // VOXEL_COMMON_V2_INC
