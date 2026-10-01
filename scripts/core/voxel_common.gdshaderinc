// DELEGATE - shared voxel surface shading, texture-array path.
//
// Per-material PBR maps (albedo + normal + ORM) baked by _tools/gen_pbr.py,
// sampled from Texture2DArrays, with the mesher's baked corner AO folded in.
// This is the path both renderers use: Texture2DArray exists in the
// compatibility (WebGL2) renderer too, so the web build gets the same maps.
//
// Everything here must stay cheap enough for a laptop browser: a handful of
// texture fetches and a few value-noise evaluations per pixel, no loops over
// lights, no screen-space passes.

#ifndef VOXEL_COMMON_V2_INC
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
// Repeats of the baked tile per METRE of world. A tile is authored to be a
// natural size (cobble 1 m, brick 1.3 m), so this is roughly 1 / tile size.
uniform float tex_scale : hint_range(0.05, 8.0) = 1.0;
// Legacy knobs from the procedural path; VoxelMaterials still sets them.
uniform float detail_strength : hint_range(0.0, 1.0) = 0.22;
uniform float bump_strength : hint_range(0.0, 2.0) = 0.5;
// Amount of fine world-space colour breakup (per material).
uniform float hue_jitter : hint_range(0.0, 1.0) = 0.10;
uniform int pattern = 0;
uniform float grain = 0.5;

// Global texture quality, pushed down by Quality.apply() on a handheld. 1.0 is
// full detail; 0 falls back to flat base colour.
uniform float texture_quality : hint_range(0.0, 1.0) = 1.0;

#ifdef USE_PBR_TEXTURES
// Layer 0 of every array is the same material, so one index selects all three.
uniform sampler2DArray albedo_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray orm_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_strength : hint_range(0.0, 3.0) = 1.0;
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
#endif

group_uniforms world;
// How far the baked tile is blended with a second, differently scaled and
// offset sample of itself. Breaks the visible repeat on big flat ground.
uniform float antitile : hint_range(0.0, 1.0) = 0.0;
// Strength of the world-space brightness / hue drift across large surfaces.
uniform float macro_strength : hint_range(0.0, 1.0) = 0.5;
// Leaf sway, in metres of vertex displacement. Zero for everything else.
uniform float wave_amount : hint_range(0.0, 0.2) = 0.0;
// Leaf translucency: how much sun shows through the far side of a leaf.
uniform float backlight_amount : hint_range(0.0, 1.0) = 0.0;
// How much the albedo texture drives the emission (lava cracks, lamp glass).
uniform float emission_from_tex : hint_range(0.0, 1.0) = 0.0;
// Foliage recolour. One baked leaf/bark/grass tile serves every species: the
// tile is multiplied by albedo_tint, after being blended toward its own
// greyscale by `recolor` (1 = keep only the light/dark pattern, so brown bark
// can become white birch). Linear light; (1,1,1) and 0 leave a material alone.
uniform vec3 albedo_tint = vec3(1.0);
uniform float recolor : hint_range(0.0, 1.0) = 0.0;
// How far the tile's light/dark pattern is flattened toward its mean luminance
// (recolor_mean) before tinting: 0 keeps every leaf vein, 1 is a flat colour.
// Small bright things (petals, grain, bark) clip to white without it.
uniform float recolor_flat : hint_range(0.0, 1.0) = 0.0;
uniform float recolor_mean : hint_range(0.0, 1.0) = 0.1;
// Winter: how far the upward faces of this material are under snow. Set per
// material by SeasonFx (scripts/obj/season_fx.gd); 0 leaves a material alone.
uniform float snow_cover : hint_range(0.0, 1.0) = 0.0;

group_uniforms water;
uniform int water_mode = 0;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_tint = vec3(1.0, 0.96, 0.90);
uniform float sun_glitter = 1.0;
uniform vec3 sky_reflect = vec3(0.45, 0.58, 0.68);

varying vec3 world_pos;
varying vec3 world_nrm;

// ---------------------------------------------------------------- noise
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

// Value noise plus its analytic gradient: x = value, yz = d/dp. One evaluation
// gives a wave height AND its slope, so the water needs no finite differences.
vec3 vnoise_d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec2 du = 6.0 * f * (1.0 - f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	float k = a - b - c + d;
	float v = a + (b - a) * u.x + (c - a) * u.y + k * u.x * u.y;
	vec2 g = du * vec2((b - a) + k * u.y, (c - a) + k * u.x);
	return vec3(v, g);
}

float fbm3(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p *= 2.07;
		a *= 0.5;
	}
	return v / 0.875;
}

// ---------------------------------------------------------------- uv
// Voxel faces are exactly axis-aligned, so there is no need for triplanar
// blending: the face is in one of three planes and we pick it.

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
	vec3 backlight;
	float ao;
};

// sRGB -> linear. The baked albedo maps are authored in sRGB (how a painter
// picks colours); sampling them raw treated 0.5 as half the light when it is a
// fifth. That is what blew the grass out to mint.
//
// ALBEDO_GAIN lifts the decoded value so the authored palette lands on the
// 0.2-0.6 linear reflectance real materials have; the maps are painted a touch
// dark on purpose so the gain, not the paint, sets the overall exposure.
const float ALBEDO_GAIN = 1.4;
vec3 srgb_to_lin(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(2.2)) * ALBEDO_GAIN;
}

// Wind: a slow travelling gust plus a fast flutter, as a world-space vector.
vec3 wind_offset(vec3 wp, float t) {
	float gust = 0.65 + 0.35 * sin(t * 0.35 + wp.x * 0.07 + wp.z * 0.05);
	vec3 o = vec3(
		sin(t * 1.30 + wp.x * 1.9 + wp.z * 1.3),
		sin(t * 1.70 + wp.x * 1.1 + wp.y * 2.3) * 0.5,
		cos(t * 1.10 + wp.z * 2.1 + wp.y * 1.4));
	return o * gust;
}

// Water. `thick` is the water column under this pixel in metres (from the depth
// buffer); negative means unknown, in which case a middling depth is assumed.
VoxelSurface water_shade(vec3 vertex_ao, vec3 camera_world, float thick, vec3 tex_lin) {
	VoxelSurface s;
	s.backlight = vec3(0.0);
	s.ao = 1.0;
	s.emission = vec3(0.0);
	s.specular = 0.5;
	s.metallic = 0.0;
	s.roughness = 0.05;

	vec3 to_cam = camera_world - world_pos;
	float dist = length(to_cam);
	vec3 view = to_cam / max(dist, 0.001);
	float far_fade = 1.0 - smoothstep(30.0, 110.0, dist);

	// Four crossing swells, coarse to fine, each scrolling its own way. Slopes
	// come straight from the noise gradient. The finest layers fade with
	// distance, which keeps far water calm instead of shimmering.
	vec2 p = world_pos.xz;
	float T = TIME;
	vec3 n1 = vnoise_d(p * 0.55 + vec2(T * 0.09, T * 0.05));
	vec3 n2 = vnoise_d(p * 1.45 + vec2(-T * 0.16, T * 0.11) + 7.3);
	vec3 n3 = vnoise_d(p * 4.20 + vec2(T * 0.38, T * 0.27) - 3.1);
	vec3 n4 = vnoise_d(p * 9.50 + vec2(-T * 0.55, T * 0.62) + 11.7);
	vec2 slope = n1.yz * (0.55 * 0.30) + n2.yz * (1.45 * 0.10)
		+ (n3.yz * (4.2 * 0.030) + n4.yz * (9.5 * 0.012)) * far_fade;
	vec3 wn = normalize(vec3(-slope.x, 1.0, -slope.y));

	float ndv = clamp(dot(view, wn), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
	vec3 rdir = reflect(-view, wn);

	// Sky reflection: horizon colour low, zenith colour high, plus the sun's
	// tint as a warm sheen. Screen-space reflection does not exist in the
	// compatibility renderer, so the water carries its own sky.
	vec3 sky_ref = mix(sky_reflect * 0.85, sky_reflect * 1.30, clamp(rdir.y * 1.4, 0.0, 1.0));
	float sd = max(dot(rdir, sun_dir), 0.0);
	sky_ref += sun_tint * pow(sd, 8.0) * 0.16;

	// Sun glitter: a hot core for the sparkle path and a wider sheen, only
	// while the sun is up.
	float up = smoothstep(0.0, 0.12, sun_dir.y);
	float glitter = (pow(sd, 700.0) * 3.5 + pow(sd, 60.0) * 0.20) * up;

	// Depth tint. Shallow water over sand is turquoise, deep water is dark
	// blue.
	float t = (thick < 0.0) ? 1.8 : thick;
	float deep = 1.0 - exp(-t * 0.55);
	vec3 shallow_c = vec3(0.05, 0.30, 0.30);
	vec3 deep_c = vec3(0.010, 0.055, 0.14);
	vec3 body = mix(shallow_c, deep_c, deep);
	float lum = dot(tex_lin, vec3(0.3, 0.59, 0.11));
	body *= 0.5 + 1.5 * lum;
	// Light scattering back out of the column: noon water is glassy turquoise,
	// dusk water is inky.
	body *= 0.55 + 0.9 * up;

	float shore = 1.0 - smoothstep(0.0, 0.22, t);
	float foam_n = vnoise(p * 6.0 + vec2(T * 0.35, -T * 0.2)) * 0.6 + vnoise(p * 15.0 - T * 0.3) * 0.4;
	float foam = shore * smoothstep(0.40, 0.72, foam_n + shore * 0.25) * smoothstep(0.0, 0.02, t);
	// crest foam where the swell is steep
	foam = max(foam, smoothstep(0.42, 0.62, length(slope) + foam_n * 0.1) * 0.25 * far_fade);

	float refl = clamp(fres * 0.75, 0.0, 0.85);
	s.albedo = mix(body, sky_ref, refl) * vertex_ao;
	s.albedo = mix(s.albedo, vec3(0.55, 0.60, 0.62) * vertex_ao, foam);
	s.roughness = mix(0.05, 0.6, foam);
	// Transparent in the shallows, opaque in the deep, always opaque at glancing
	// angles where the surface is a mirror; soft where it meets the shore.
	float a = mix(0.30, 0.95, 1.0 - exp(-t * 1.3));
	a = max(a, refl);
	a = max(a, foam * 0.9);
	a *= smoothstep(0.0, 0.05, t);
	s.alpha = clamp(a, 0.0, 1.0);
	s.emission = sun_tint * (glitter * sun_glitter);
	s.normal_world = wn;
	s.custom_normal = true;
	return s;
}

VoxelSurface voxel_shade(vec3 vertex_ao, vec3 camera_world) {
	VoxelSurface s;
	s.emission = vec3(0.0);
	s.normal_world = world_nrm;
	s.custom_normal = false;
	s.specular = 0.45;
	s.alpha = alpha;
	s.albedo = base_albedo;
	s.roughness = base_roughness;
	s.metallic = base_metallic;
	s.backlight = vec3(0.0);
	s.ao = 1.0;

	Frame f = face_frame(world_pos, world_nrm);
	vec2 uv = f.uv * tex_scale;
	float dist = length(camera_world - world_pos);

	vec3 tex_albedo = base_albedo;
	float tex_ao = 1.0;
	float tex_rough = base_roughness;
	float tex_metal = base_metallic;

#ifdef USE_PBR_TEXTURES
	if (texture_quality > 0.0) {
		vec3 layer_uv = vec3(uv, float(tex_layer));
		tex_albedo = texture(albedo_array, layer_uv).rgb;
		if (antitile > 0.0) {
			// A second sample at another scale and offset, mixed in through a
			// slow noise: the two tiles never line up, so the repeat vanishes.
			// Only worth its fetch on organic ground.
			vec3 b = texture(albedo_array, vec3(uv * 0.317 + vec2(0.37, 0.61), float(tex_layer))).rgb;
			float m = smoothstep(0.25, 0.75, vnoise(f.uv * 0.45 + 3.1));
			tex_albedo = mix(tex_albedo, b, m * 0.55 * antitile);
		}
		tex_albedo = srgb_to_lin(tex_albedo);
		if (recolor > 0.0) {
			float tl = dot(tex_albedo, vec3(0.3, 0.59, 0.11));
			tex_albedo = mix(tex_albedo, vec3(mix(tl, recolor_mean, recolor_flat)), recolor);
		}
		tex_albedo *= albedo_tint;
		vec3 orm = texture(orm_array, layer_uv).rgb;
		tex_ao = mix(1.0, orm.r, ao_strength);
		tex_rough = clamp(orm.g, 0.03, 1.0);
		tex_metal = clamp(orm.b, 0.0, 1.0);

		// Tangent-space normal, applied in the face's own exact basis. Fades out
		// with distance: the mip chain averages it to flat anyway and what is
		// left over is what shimmers.
		vec3 nm = texture(normal_array, layer_uv).rgb;
		float nfade = 1.0 - smoothstep(25.0, 90.0, dist);
		vec2 xy = (nm.xy * 2.0 - 1.0) * normal_strength * nfade;
		float zt = max(nm.b * 2.0 - 1.0, 0.05);
		s.normal_world = normalize(world_nrm
			+ f.tangent * xy.x
			+ f.bitangent * xy.y * zt);
		s.custom_normal = true;
	}
#endif

	if (water_mode == 1) {
		return water_shade(vertex_ao, camera_world, -1.0, tex_albedo);
	}

	// World-space variation no tile can carry, because it belongs to WHERE the
	// surface is, not to what it is made of. Three scales: a wide hue drift
	// (whole meadows go yellow-green or blue-green), patches tens of metres
	// wide that are lighter or darker, and a fine breakup at voxel scale so a
	// wall does not read as one flat plane of plastic.
	vec2 wp2 = world_pos.xz + vec2(world_pos.y * 0.7, world_pos.y * 0.4);
	float drift = vnoise(wp2 * 0.045 + 5.0) - 0.5;
	float patch_n = fbm3(wp2 * 0.16 + 17.0) - 0.5;
	float fine_n = vnoise(world_pos.xz * 1.7 + world_pos.y * 0.9) - 0.5;
	vec3 warm = vec3(1.10, 1.02, 0.84);
	vec3 cool = vec3(0.92, 1.00, 1.08);
	vec3 tint = mix(cool, warm, clamp(drift * 2.4 + 0.5, 0.0, 1.0));

	vec3 col = (texture_quality > 0.0) ? tex_albedo : base_albedo;
	col *= 1.0 + (patch_n * 0.55 + fine_n * hue_jitter * 1.4) * macro_strength * 1.6;
	col *= mix(vec3(1.0), tint, clamp(hue_jitter * 3.0, 0.0, 1.0) * macro_strength * 1.5);
	// Upward faces catch a little more sky.
	col *= mix(1.0, 1.05, clamp(world_nrm.y, 0.0, 1.0));
	// Settled snow on the tops of things.
	if (snow_cover > 0.0) {
		col = mix(col, vec3(0.70, 0.74, 0.82), snow_cover * smoothstep(0.6, 0.95, world_nrm.y));
	}

	// vertex_ao is the mesher's baked corner AO; tex_ao the texture's own
	// cavity darkening. Together they give contact shadow in the joints and at
	// the foot of a wall.
	// Half of it darkens the albedo (so the crevice reads even in direct sun) and
	// the whole of it also goes to the ambient-only AO channel.
	float vao = vertex_ao.r;
	float occ = vao * tex_ao;
	s.ao = occ;
	s.albedo = col * mix(1.0, occ, 0.5);
	s.roughness = clamp(tex_rough, 0.02, 1.0);
	s.metallic = tex_metal;
	s.specular = mix(0.5, 0.36, smoothstep(0.55, 0.9, tex_rough) * (1.0 - tex_metal));
	if (emission_energy > 0.0) {
		float l = dot(tex_albedo, vec3(0.3, 0.59, 0.11));
		float k = mix(1.0, 0.15 + 1.25 * smoothstep(0.01, 0.30, l), emission_from_tex);
		s.emission = emission_color * emission_energy * k;
	}
	if (backlight_amount > 0.0) {
		// Light through a leaf is the leaf's own colour, warmed and brightened.
		s.backlight = col * vec3(1.1, 1.0, 0.5) * backlight_amount;
	}
	return s;
}

#endif // VOXEL_COMMON_V2_INC
