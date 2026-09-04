// DELEGATE - shared voxel surface shading.
//
// Included by voxel.gdshader (opaque) and voxel_glass.gdshader (transparent).
// The split matters more than it looks: Godot decides whether a material goes
// in the opaque or the transparent pass by whether the shader assigns ALPHA at
// all. A single shader that always wrote ALPHA put all four hundred chunk
// meshes into the transparent pass, which cost the depth prepass, early-Z and
// correct sorting all at once.

group_uniforms surface;
// Albedo and emission arrive already converted to linear by VoxelMaterials, so
// they deliberately carry no source_color hint: Godot only applies the sRGB
// conversion to Color values, and these are set as vec3.
uniform vec3 base_albedo = vec3(0.25);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.9;
uniform float base_metallic : hint_range(0.0, 1.0) = 0.0;
uniform vec3 emission_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

group_uniforms detail;
uniform int pattern = 0;
uniform float grain = 0.5;        // feature size in metres
uniform float detail_strength : hint_range(0.0, 1.0) = 0.35;
uniform float bump_strength : hint_range(0.0, 2.0) = 0.6;
uniform float hue_jitter : hint_range(0.0, 1.0) = 0.10;

group_uniforms water;
uniform int water_mode = 0;        // 1 on the WATER material only
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);   // world space, pointing AT the sun
uniform vec3 sun_tint = vec3(1.0, 0.96, 0.90); // linear; pushed by SkyEnv
uniform float sun_glitter = 1.0;              // stronger at low sun
uniform vec3 sky_reflect = vec3(0.45, 0.58, 0.68); // linear horizon tint

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

// ---------------------------------------------------------------- patterns
// Each returns vec2(shade, height). shade tints albedo, height drives the
// derived normal.

vec2 pat_plain(vec2 p) {
	float n = fbm(p / max(grain, 0.02));
	return vec2(n, n * 0.35);
}

vec2 pat_masonry(vec2 p) {
	// Horizontal courses; every other course offset by half a stone.
	float course_h = max(grain, 0.06);
	float brick_w = course_h * 2.2;
	float row = floor(p.y / course_h);
	float x = p.x + mod(row, 2.0) * brick_w * 0.5;
	vec2 cell = vec2(floor(x / brick_w), row);
	vec2 f = vec2(fract(x / brick_w), fract(p.y / course_h));
	float mortar = smoothstep(0.0, 0.12, f.x) * smoothstep(1.0, 0.88, f.x)
	             * smoothstep(0.0, 0.20, f.y) * smoothstep(1.0, 0.80, f.y);

	// Stone-to-stone variation is what stops paving reading as bathroom tile,
	// so it is wide, and it is biased dark rather than centred.
	float tone = 0.55 + hash12(cell) * 0.62;
	float wear = fbm(p * 2.2) * 0.5 + fbm(p * 11.0) * 0.18;
	// Dirt collects in the joints and in low patches.
	float grime = smoothstep(0.35, 0.85, fbm(p * 0.8)) * 0.30;
	float face = tone * (0.72 + wear * 0.5) - grime;
	float shade = mix(0.20, face, mortar);
	return vec2(shade, mortar * 0.55);
}


vec2 pat_grain(vec2 p) {
	// Horizontal boards. The previous version stretched noise along x and read
	// as motion blur; what sells timber is the seam between boards and the
	// tone difference from one board to the next.
	float board = max(grain, 0.12);
	float row = floor(p.y / board);
	float f = fract(p.y / board);
	float seam = smoothstep(0.0, 0.10, f) * smoothstep(1.0, 0.90, f);

	float tone = 0.72 + hash12(vec2(row, 3.7)) * 0.42;
	// Grain runs along the board. Two frequencies: a slow wander that gives the
	// board its figure, and a fine streak at roughly finger width. Without the
	// fine term a plank reads as a smear rather than as sawn timber.
	float along = p.x / max(board, 0.12);
	float figure = fbm(vec2(along * 0.55, row * 12.7));
	float streak = fbm(vec2(along * 5.0, row * 31.1 + f * 3.0)) * 0.45;
	float knot = smoothstep(0.66, 0.96, fbm(vec2(along * 0.9, row * 7.3)));

	float shade = tone * (0.74 + figure * 0.30 + streak * 0.26) * mix(0.42, 1.0, seam);
	shade = mix(shade, shade * 0.55, knot);
	return vec2(shade, seam * 0.85 + streak * 0.12);
}


vec2 pat_corrugated(vec2 p) {
	float ridge = sin(p.x / max(grain, 0.05) * 6.2831) * 0.5 + 0.5;
	float dirt = fbm(p * 3.0) * 0.25;
	return vec2(0.55 + ridge * 0.45 - dirt, ridge);
}

vec2 pat_tile(vec2 p) {
	// Overlapping roof tiles: rows with a rounded lower edge.
	float row_h = max(grain, 0.1);
	float col_w = row_h * 1.15;
	float row = floor(p.y / row_h);
	float x = p.x + mod(row, 2.0) * col_w * 0.5;
	vec2 f = vec2(fract(x / col_w), fract(p.y / row_h));
	float lip = smoothstep(0.0, 0.22, f.y);
	float groove = smoothstep(0.0, 0.07, f.x) * smoothstep(1.0, 0.93, f.x);
	float tone = hash12(vec2(floor(x / col_w), row)) * 0.35 + 0.6;
	return vec2(tone * mix(0.5, 1.0, lip) * mix(0.65, 1.0, groove), lip * groove);
}

vec2 pat_thatch(vec2 p) {
	vec2 q = p / max(grain, 0.04);
	float straw = fbm(q * vec2(1.5, 26.0));
	float clump = fbm(q * 0.6);
	float shade = 0.45 + straw * 0.5 + clump * 0.25;
	return vec2(shade, straw);
}

vec2 pat_scatter(vec2 p) {
	// Three scales on purpose. The fine speck reads underfoot, the metre-scale
	// patch reads across a lawn, and the broad drift keeps a whole field from
	// looking like one flat colour from the far side of the town.
	vec2 q = p / max(grain, 0.03);
	float speck = fbm(q * 3.0);
	float patch = fbm(q * 0.30);
	float drift = fbm(p * 0.09);
	float shade = 0.42 + speck * 0.34 + patch * 0.40 + drift * 0.30;
	return vec2(shade, speck * 0.6);
}


vec2 pat_glass(vec2 p) {
	float smear = fbm(p * 1.4) * 0.25;
	return vec2(0.85 + smear, 0.0);
}

vec2 pat_panel(vec2 p) {
	float panel = max(grain, 0.4) * 3.0;
	vec2 f = fract(p / panel);
	float seam = smoothstep(0.0, 0.03, f.x) * smoothstep(1.0, 0.97, f.x)
	           * smoothstep(0.0, 0.03, f.y) * smoothstep(1.0, 0.97, f.y);
	float rivet = 1.0 - smoothstep(0.02, 0.05,
		length(fract(p / (panel * 0.25)) - 0.5) * 0.25);
	float brush = fbm(p * vec2(30.0, 2.0)) * 0.18;
	return vec2(0.7 + brush + rivet * 0.2, seam * 0.6 + rivet * 0.4);
}

vec2 pat_neon(vec2 p) {
	float pulse = fbm(p * 0.8) * 0.15;
	return vec2(0.9 + pulse, 0.0);
}

vec2 sample_pattern(vec2 p) {
	if (pattern == 1) { return pat_masonry(p); }
	if (pattern == 2) { return pat_grain(p); }
	if (pattern == 3) { return pat_corrugated(p); }
	if (pattern == 4) { return pat_tile(p); }
	if (pattern == 5) { return pat_thatch(p); }
	if (pattern == 6) { return pat_scatter(p); }
	if (pattern == 7) { return pat_glass(p); }
	if (pattern == 8) { return pat_panel(p); }
	if (pattern == 9) { return pat_neon(p); }
	return pat_plain(p);
}

// The varyings are filled directly in each shader's vertex() function, not
// here: Godot forbids assigning a varying from anything but the stage function
// itself, and a helper that tries to do it fails the whole shader compile.

// Everything the surface needs, returned rather than written: a plain function
// cannot assign fragment builtins, and the two shaders that include this file
// need to write a different subset of them.
struct VoxelSurface {
	vec3 albedo;
	float roughness;
	float metallic;
	float specular;
	vec3 emission;
	vec3 normal_world;   // world space; the caller converts to view space
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

	// Voxel faces are exactly axis-aligned, so triplanar blending is not an
	// approximation problem here — it is simply wasted work. Picking the one
	// plane the face actually lies in gives identical output for a third of
	// the pattern evaluations, which is the single biggest shader saving
	// available.
	vec3 an = abs(world_nrm);
	vec2 uv;
	vec3 tangent;
	vec3 bitan;
	if (an.y >= an.x && an.y >= an.z) {
		uv = vec2(world_pos.x, world_pos.z);
		tangent = vec3(1.0, 0.0, 0.0);
		bitan = vec3(0.0, 0.0, 1.0);
	} else if (an.x >= an.z) {
		// Vertical faces run the pattern with y as the "up" axis, so masonry
		// courses and board seams stay horizontal.
		uv = vec2(world_pos.z, world_pos.y);
		tangent = vec3(0.0, 0.0, 1.0);
		bitan = vec3(0.0, 1.0, 0.0);
	} else {
		uv = vec2(world_pos.x, world_pos.y);
		tangent = vec3(1.0, 0.0, 0.0);
		bitan = vec3(0.0, 1.0, 0.0);
	}
	vec2 det = sample_pattern(uv);

	// det.x is centred a little under 1 so the pattern reads as shading on the
	// material rather than as a brightness gain on top of it.
	float shade = mix(1.0, det.x * 1.05, detail_strength);

	// Two scales of variation. The fine jitter keeps a wall from reading as
	// plastic; the slow drift shifts the actual hue, which is what a big field
	// of grass needs — brightness variation alone still reads as one flat
	// colour from across the town.
	float jitter = (fbm(world_pos.xz * 0.9 + world_pos.y * 0.37) - 0.5) * 2.0;
	float drift = fbm(world_pos.xz * 0.055 + world_pos.y * 0.02) - 0.5;
	vec3 warm = vec3(1.14, 1.02, 0.76);
	vec3 cool = vec3(0.88, 1.00, 1.08);
	vec3 tint = mix(cool, warm, clamp(drift * 2.2 + 0.5, 0.0, 1.0));
	vec3 col = base_albedo * shade * (1.0 + jitter * hue_jitter)
		* mix(vec3(1.0), tint, clamp(hue_jitter * 3.0, 0.0, 1.0));

	// Upward faces catch slightly more light.
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
		float fres = 0.02 + 0.66 * pow(1.0 - max(dot(view, wn), 0.0), 4.0);
		vec3 rdir = reflect(-view, wn);
		vec3 sky_ref = mix(sky_reflect, sky_reflect * 1.3 + vec3(0.04, 0.05, 0.06),
			clamp(rdir.y, 0.0, 1.0));
		// Sun glitter: a tight hot core for the sparkle path plus a broad sheen.
		float sd = max(dot(rdir, sun_dir), 0.0);
		float glitter = pow(sd, 800.0) * 1.6 + pow(sd, 48.0) * 0.08;

		vec3 body = base_albedo * (0.55 + 0.45 * det.x);
		s.albedo = mix(body, sky_ref, clamp(fres, 0.0, 0.62)) * vertex_ao;
		s.roughness = 0.12;
		s.specular = 0.35;
		s.metallic = 0.0;
		s.alpha = clamp(alpha + fres * 0.25, 0.0, 1.0);
		s.emission = sun_tint * (glitter * sun_glitter);
		s.normal_world = wn;
		s.custom_normal = true;
		return s;
	}

	s.albedo = col * vertex_ao;        // vertex_ao carries the baked corner AO
	s.roughness = clamp(base_roughness - det.y * 0.18 + jitter * 0.05, 0.02, 1.0);
	s.metallic = base_metallic;
	if (emission_energy > 0.0) {
		s.emission = emission_color * emission_energy * (0.7 + det.x * 0.5);
	}

	// Derive a normal from the pattern height by finite differences in the
	// dominant plane. Cheap, and enough to make brick and corrugation catch
	// grazing light properly.
	if (bump_strength > 0.001) {
		float e2 = 0.012;
		float ph = det.y;
		float pu = sample_pattern(uv + vec2(e2, 0.0)).y;
		float pv = sample_pattern(uv + vec2(0.0, e2)).y;
		s.normal_world = normalize(world_nrm
			- tangent * (pu - ph) * bump_strength * 3.0
			- bitan * (pv - ph) * bump_strength * 3.0);
		s.custom_normal = true;
	}
	return s;
}
