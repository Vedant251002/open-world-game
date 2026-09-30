shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// DELEGATE - figure paint, for the workers, animals and carts.
//
// Every figure in the game is built from twenty-odd axis-aligned boxes, and
// until this shader existed each one was a single flat albedo colour. Beside a
// wall carrying thatch grain and a normal map, a hen's flank at 0.1 m read as
// painted plastic, and that is most of what was on screen whenever you looked
// at another person.
//
// These are not surface materials — a hen's flank is wool, a worker's coat is
// cloth — so they cannot sample the world's 41 PBR maps. What they need is
// enough surface variation to break the specular highlight and the silhouette,
// which is what a weave gives: a fine high-frequency pattern derived from
// world-space position so it does not swim when the figure moves, plus a
// derived normal that makes the weave catch the light.
//
// Cost is one hash, two noise fetches and a normal mix. A figure is at most a
// few hundred pixels on screen, so this is not measurable in the frame time.

uniform vec3 paint_albedo = vec3(0.5);
uniform float paint_rough : hint_range(0.0, 1.0) = 0.88;
uniform float weave_scale : hint_range(1.0, 400.0) = 90.0;
uniform float weave_depth : hint_range(0.0, 1.0) = 0.35;
// Batched figures (BoxKit.Batch) carry colour per vertex, and roughness in its
// alpha, and give every face a metre-scale UV so the bevel below is constant.
uniform bool vertex_paint = false;

varying vec3 paint_world_pos;
varying vec3 paint_world_nrm;
varying vec4 paint_vcol;

float bk_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float bk_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 w = f * f * (3.0 - 2.0 * f);
	float a = bk_hash12(i);
	float b = bk_hash12(i + vec2(1.0, 0.0));
	float c = bk_hash12(i + vec2(0.0, 1.0));
	float d = bk_hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

void vertex() {
	paint_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	paint_world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	paint_vcol = COLOR;
}

void fragment() {
	vec3 an = abs(paint_world_nrm);
	vec2 uv;
	if (an.y >= an.x && an.y >= an.z) {
		uv = paint_world_pos.xz;
	} else if (an.x >= an.z) {
		uv = paint_world_pos.zy;
	} else {
		uv = paint_world_pos.xy;
	}

	// One noise fetch, not two, and the derived normal comes from screen-space
	// derivatives of that single value rather than from two more samples.
	//
	// The earlier version took three bk_vnoise calls for the normal and two more
	// for the colour, and it cost more than the entire rest of the frame: the
	// figures dropped the game from 30-90 fps to 5-32. There are ~170 boxes on
	// screen at once (every limb of every worker and animal, plus debris and
	// muzzle flashes), so five fetches each is 850 fetches of noise for detail
	// that occupies a few hundred pixels.
	//
	// dFdx/dFdy of one noise value gives the same slope for free, which is the
	// standard trick and the reason the hand-written version above was slower
	// than doing less.
	vec2 w = uv * weave_scale;
	float n = bk_vnoise(w);

	// Fade the weave out once a pixel covers more than one cell, or it turns
	// into crawling noise at any distance.
	float footprint = max(fwidth(w.x), fwidth(w.y));
	float legible = 1.0 - smoothstep(0.35, 1.4, footprint);

	vec3 base = paint_albedo;
	float rough = paint_rough;
	float wd = weave_depth;
	float edge;
	if (vertex_paint) {
		base = paint_vcol.rgb;
		rough = paint_vcol.a;
		// Skin and leather are smooth; only cloth and wool show a weave.
		wd *= smoothstep(0.55, 0.85, rough);
		vec2 e2 = min(UV, UV2 - UV);
		edge = 1.0 - smoothstep(0.0, 0.011, min(e2.x, e2.y));
	} else {
		// BoxMesh lays its six faces out in a 3x2 atlas.
		vec2 f = fract(UV * vec2(3.0, 2.0));
		vec2 e2 = min(f, 1.0 - f);
		edge = 1.0 - smoothstep(0.0, 0.06, min(e2.x, e2.y));
	}

	float shade = 1.0 + (n - 0.5) * 0.20 * wd * legible;
	// A pressed edge on every box: the rim of each face is a little darker,
	// which is most of what turns a stack of cuboids into a crafted figure.
	shade *= 1.0 - 0.17 * edge;
	// Undersides and shadowed flanks sit darker than the tops, as baked
	// occlusion, so a figure has weight even where the sun is flat on it.
	float up = paint_world_nrm.y * 0.5 + 0.5;
	shade *= mix(0.80, 1.04, up);

	// Pigments are never quite as saturated as a vertex colour says.
	base = mix(vec3(dot(base, vec3(0.299, 0.587, 0.114))), base, 0.9);
	ALBEDO = base * shade;
	// A little self-fill so a face under a hat brim is a face, not a hole.
	EMISSION = base * shade * 0.09;
	ROUGHNESS = clamp(rough + (n - 0.5) * 0.14 * legible, 0.05, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.35;
	// A soft cool rim, which is what lifts a small dark figure off the ground.
	RIM = 0.30;
	RIM_TINT = 0.55;

	// Derived normal, from the gradient of the one noise value. fwidth() is
	// already being computed above for the fade, so this is two more
	// instructions rather than two more texture fetches.
	if (wd * legible > 0.001) {
		vec2 slope = vec2(dFdx(n), dFdy(n)) * wd * legible * 2.2;
		vec3 t = (an.y >= an.x && an.y >= an.z)
			? vec3(1.0, 0.0, 0.0)
			: ((an.x >= an.z) ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0));
		vec3 b = (an.y >= an.x && an.y >= an.z)
			? vec3(0.0, 0.0, 1.0)
			: ((an.x >= an.z) ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 1.0, 0.0));
		NORMAL = normalize((VIEW_MATRIX
			* vec4(normalize(paint_world_nrm - t * slope.x - b * slope.y),
				0.0)).xyz);
	}
}
