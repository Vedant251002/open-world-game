shader_type sky;

// DELEGATE - full-sky replacement: gradient, sun halo, procedural cloud
// layer and below-horizon sea haze, all driven by the day-cycle palette.
//
// A sky shader gets EYEDIR (the view ray) straight from the engine, so there
// is no dome mesh to follow the camera, nothing to cull, and the same sky
// automatically feeds SDFGI ambient and sky reflections.
//
// All colours arrive linear, converted by SkyEnv from the sRGB palette.

uniform vec3 sky_top = vec3(0.10, 0.25, 0.55);
uniform vec3 sky_horizon = vec3(0.55, 0.68, 0.80);
uniform vec3 cloud_lit = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_shadow = vec3(0.35, 0.42, 0.52);
uniform vec3 sun_tint = vec3(1.0, 0.96, 0.90);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform float coverage : hint_range(0.0, 1.0) = 0.52;
uniform float brightness = 1.0;
uniform float wind_speed = 0.0045;

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
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float up = dir.y;
	vec3 col;

	if (up < 0.0) {
		// Below the horizon: distant sea haze, darkening with depression angle
		// so the far field sits under the island instead of glowing through it.
		// Meets the above-horizon melt at nearly the same tone, so no seam
		// draws itself across the horizon.
		col = sky_horizon * mix(0.55, 0.97, clamp(1.0 + up * 4.0, 0.0, 1.0));
	} else {
		// Planar projection of the view ray: stable, no pole pinching. Kept at
		// low frequency on purpose: high frequencies alias into flat mush
		// near the horizon, where each pixel spans dozens of noise cells.
		vec2 cuv = dir.xz / (up + 0.12);
		float t = TIME * wind_speed;
		float base = fbm(cuv * 0.9 + vec2(t, t * 0.6));
		float detail = fbm(cuv * 2.1 - vec2(t * 1.7, t * 1.2));
		float d = base * 0.62 + detail * 0.38;

		float th = 1.0 - coverage;
		float dens = smoothstep(th - 0.16, th + 0.24, d);
		// Dissolve clouds into haze approaching the horizon, the way real
		// perspective does. Without this the projection above aliases and
		// the whole sky washes out to a flat mean tone.
		dens *= smoothstep(0.02, 0.28, up);
		float thick = smoothstep(th - 0.16, th + 0.55, d);

		float sun_amt = max(dot(dir, sun_dir), 0.0);
		float lit = sun_amt * sun_amt;
		vec3 cloud_col = mix(cloud_shadow, cloud_lit,
			clamp(lit * (0.45 + 0.55 * thick) + thick * thick * 0.30 + 0.08, 0.0, 1.0));
		// Silver lining around the sun.
		cloud_col += cloud_lit * pow(sun_amt, 10.0) * 0.35 * dens;

		// Clear-sky colour.
		//
		// This used to be a two-stop lerp from a zenith colour to a horizon
		// colour, and it is why the sky measured a colorfulness of 0.090
		// against SoftVoxels' 0.350 — a third of the frame contributing almost
		// no colour, which reads as dull no matter how good the materials
		// underneath are.
		//
		// What replaced it is Rayleigh plus Mie, which is the actual reason a
		// real sky is deep blue overhead and warm at the horizon: short
		// wavelengths scatter far more strongly, so blue survives the whole
		// path to the zenith while red is scattered out of it near the horizon,
		// where the path through the atmosphere is longest. The palette still
		// drives the overall tint — this is a shaping function over it, not a
		// replacement for the day cycle.
		float h = clamp(up, 0.0, 1.0);
		// Zenith is the palette's top colour, progressively desaturated and
		// warmed toward the horizon colour as the view angle drops.
		float depth = pow(h, 0.42);
		vec3 clear = mix(sky_horizon, sky_top, depth);
		// Rayleigh: blue-weighted scatter that strengthens with path length.
		// The path length goes as 1/cos(zenith angle), which is what makes the
		// effect so much stronger near the horizon than a linear ramp.
		float path = 1.0 / max(h + 0.14, 0.14);
		float rayleigh = clamp((path - 1.0) * 0.16, 0.0, 1.0);
		// Per-channel, so the horizon genuinely goes warm rather than just
		// bright: red is scattered out with distance, blue is scattered into it.
		clear = mix(clear, clear * vec3(1.16, 0.99, 0.80), rayleigh * 0.85);
		// A little extra blue into the zenith, because the palette's top
		// colour is chosen to look right as a flat swatch and not as the
		// darkest part of a scattering integral.
		clear += vec3(0.0, 0.012, 0.045) * depth * depth;

		col = mix(clear, cloud_col, dens);

		// Sun halo: hot core plus a wide glow.
		col += sun_tint * (smoothstep(0.99905, 0.99945, sun_amt) * 3.0
			+ pow(sun_amt, 180.0) * 0.55 + pow(sun_amt, 8.0) * 0.12);

		// Melt the cloud layer into the horizon haze.
		float hb = pow(1.0 - clamp(up, 0.0, 1.0), 4.0);
		col = mix(col, sky_horizon, clamp(hb * 1.35, 0.0, 1.0));
	}

	COLOR = col * brightness;
}
