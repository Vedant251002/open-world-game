shader_type sky;

// DELEGATE - full-sky replacement: scattering gradient, twilight belt, sun disc
// with mie halo, moon, stars, two layers of fake-volumetric clouds and the
// below-horizon sea haze, all driven by the day-cycle palette.
//
// A sky shader gets EYEDIR (the view ray) straight from the engine, so there
// is no dome mesh to follow the camera, nothing to cull, and the same sky
// automatically feeds sky reflections.
//
// Deliberately does NOT read TIME: a sky shader that uses TIME is re-rendered
// into its radiance cubemap every frame, which is the single most expensive
// thing it can do on the compatibility renderer. SkyEnv pushes `cloud_time`
// a few times a second instead, and the cubemap pass takes a cheap path.
//
// All colours arrive linear, converted by SkyEnv from the sRGB palette.

uniform vec3 sky_top = vec3(0.10, 0.25, 0.55);
uniform vec3 sky_horizon = vec3(0.55, 0.68, 0.80);
uniform vec3 cloud_lit = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_shadow = vec3(0.35, 0.42, 0.52);
uniform vec3 sun_tint = vec3(1.0, 0.96, 0.90);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float coverage : hint_range(0.0, 1.0) = 0.52;
uniform float brightness = 1.0;
uniform float night = 0.0;         // 0 day .. 1 full night
uniform float twilight = 0.0;      // 0 .. 1, strongest with the sun on the horizon
uniform float cloud_time = 0.0;
uniform float wind_speed = 0.0045;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
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

float fbm4(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

// Cumulus density at a projected sky position. One place, so the lighting
// probe below samples exactly the same field as the surface.
float cumulus(vec2 p, float th) {
	float base = fbm4(p * 0.85);
	float detail = vnoise(p * 3.3 + vec2(base * 3.0)) ;
	float d = base * 0.78 + detail * 0.22;
	return smoothstep(th - 0.10, th + 0.22, d);
}

void sky() {
	vec3 dir = EYEDIR;
	float up = dir.y;
	vec3 col;

	float sun_amt = max(dot(dir, sun_dir), 0.0);
	float sun_h = sun_dir.y;

	if (up < 0.0) {
		// Below the horizon: distant sea haze, darkening with depression angle
		// so the far field sits under the island instead of glowing through it.
		col = sky_horizon * mix(0.50, 0.96, clamp(1.0 + up * 4.0, 0.0, 1.0));
	} else {
		float h = clamp(up, 0.0, 1.0);

		// ---- Clear-sky scattering ----------------------------------------
		// Palette gives the zenith and horizon colours; Rayleigh shaping gives
		// the deep, saturated overhead blue and the warm, bright horizon band.
		float depth = pow(h, 0.45);
		vec3 clear = mix(sky_horizon, sky_top, depth);
		float path = 1.0 / max(h + 0.12, 0.12);
		float rayleigh = clamp((path - 1.0) * 0.16, 0.0, 1.0);
		clear = mix(clear, clear * vec3(1.14, 0.99, 0.82), rayleigh * 0.75 * (1.0 - night));
		clear += vec3(0.0, 0.010, 0.040) * depth * depth * (1.0 - night);
		// Overhead deepens a touch so the zenith reads rich, not milky.
		clear *= mix(1.0, 0.94, smoothstep(0.35, 1.0, h) * (1.0 - night));

		// Mie forward scatter: broad warm glow around the sun that hugs the
		// horizon as the sun sinks.
		float mie = pow(sun_amt, 6.0) * 0.20 + pow(sun_amt, 32.0) * 0.45;
		clear += sun_tint * mie * (1.0 - night) * (0.35 + 0.65 * exp(-h * 3.0));

		// Twilight belt: warm on the sun side of the horizon, a cool pink-violet
		// counter-glow opposite it (the belt of Venus).
		vec2 sxz = normalize(sun_dir.xz + vec2(1e-4));
		vec2 dxz = normalize(dir.xz + vec2(1e-4));
		float az = dot(sxz, dxz) * 0.5 + 0.5;
		float band = exp(-h * 5.5);
		clear += sun_tint * vec3(1.05, 0.62, 0.34) * pow(az, 3.0) * band * twilight * 0.42;
		clear += vec3(0.42, 0.30, 0.55) * pow(1.0 - az, 2.0) * exp(-h * 3.5) * twilight * 0.22;

		col = clear;

		// ---- Stars and moon ----------------------------------------------
		if (night > 0.02 && !AT_CUBEMAP_PASS) {
			vec3 sp = dir * 120.0;
			vec3 id = floor(sp);
			vec3 f = fract(sp) - 0.5;
			float r = hash13(id);
			vec3 jit = vec3(hash13(id + 7.3), hash13(id + 13.1), hash13(id + 3.7)) - 0.5;
			float sd = length(f - jit * 0.5);
			float star = step(0.955, r) * smoothstep(0.26, 0.0, sd);
			float tw = 0.75 + 0.25 * sin(cloud_time * 30.0 + r * 60.0);
			// Warm and cool stars.
			vec3 scol = mix(vec3(0.75, 0.85, 1.2), vec3(1.2, 0.95, 0.75), hash13(id + 1.7));
			// A faint milky way band across the sky.
			vec3 gn = normalize(vec3(0.35, 0.8, 0.5));
			float gband = exp(-pow(dot(dir, gn) * 4.5, 2.0));
			float gdust = fbm4(vec2(atan(dir.z, dir.x) * 3.0, dir.y * 6.0));
			float horizon_fade = smoothstep(0.0, 0.25, h);
			col += scol * star * tw * 4.0 * night * horizon_fade;
			col += vec3(0.20, 0.24, 0.42) * gband * gdust * 0.55 * night * horizon_fade;
		}
		float mu = dot(dir, moon_dir);
		if (night > 0.02 && mu > 0.985) {
			float disc = smoothstep(0.99962, 0.99972, mu);
			vec3 md = dir - moon_dir * mu;
			float crater = vnoise(md.xy * 900.0 + md.z * 500.0) * 0.5 + vnoise(md.xy * 300.0 + md.z * 170.0) * 0.5;
			vec3 mcol = vec3(0.95, 0.96, 1.0) * mix(0.60, 1.0, crater);
			col = mix(col, mcol * 3.0, disc * night);
		}
		if (night > 0.02) {
			col += vec3(0.30, 0.38, 0.60) * (pow(max(mu, 0.0), 300.0) * 0.5 + pow(max(mu, 0.0), 24.0) * 0.10) * night;
		}

		// ---- Clouds --------------------------------------------------------
		float t = cloud_time * wind_speed;
		float th = 1.0 - coverage;
		vec2 cuv = dir.xz / (up + 0.10);
		float fade = smoothstep(0.02, 0.30, up);

		// High, thin cirrus streaks: cheap, one octave-stack, no lighting probe.
		if (!AT_CUBEMAP_PASS) {
			vec2 cc = vec2(cuv.x * 0.35, cuv.y * 1.5) * 0.9 + vec2(t * 0.6, 3.1);
			float ci = smoothstep(0.50, 0.85, fbm4(cc)) * smoothstep(0.05, 0.4, up) * 0.22;
			vec3 ci_col = mix(cloud_shadow, cloud_lit, 0.85);
			col = mix(col, ci_col, ci * (1.0 - 0.6 * night));
		}

		vec2 p0 = cuv + vec2(t, t * 0.6);
		float dens = cumulus(p0, th);
		if (dens > 0.001) {
			// Fake volumetric shading: probe density one step toward the sun.
			// Where the probe is thinner than the surface the cloud is lit on
			// that side (bright rim, silver lining); where it is thicker the
			// cloud is self-shadowed (grey-blue belly).
			vec2 to_sun = normalize(sun_dir.xz + vec2(1e-4)) * 0.16 * clamp(1.0 - sun_h * 0.6, 0.4, 1.0);
			float d_s = AT_CUBEMAP_PASS ? dens : cumulus(p0 + to_sun, th);
			float thick = clamp(dens * 1.4, 0.0, 1.0);
			float lit = clamp(0.62 + (dens - d_s) * 2.6 - thick * 0.30, 0.0, 1.0);
			// Sun-facing side glows warmer; anti-sun side takes sky-blue shadow.
			lit = mix(lit, 1.0, pow(sun_amt, 12.0) * 0.4);
			vec3 ccol = mix(cloud_shadow, cloud_lit, lit);
			// Powder: darken the thick core slightly so puffs have body.
			ccol *= mix(1.0, 0.82, thick * thick * (1.0 - lit));
			// Silver lining on thin edges toward the sun.
			ccol += sun_tint * pow(sun_amt, 8.0) * (1.0 - thick) * 0.55 * (1.0 - night);
			// Twilight tints the underside of low clouds warm.
			ccol = mix(ccol, ccol * vec3(1.25, 0.82, 0.62) + sun_tint * 0.10, twilight * (1.0 - lit) * 0.6);
			col = mix(col, ccol, dens * fade);
		}

		// ---- Sun disc -------------------------------------------------------
		float disc = smoothstep(0.99975, 0.99988, sun_amt);
		col += sun_tint * (disc * 14.0 + pow(sun_amt, 900.0) * 1.4 + pow(sun_amt, 110.0) * 0.35);

		// Melt everything into the horizon haze.
		float hb = pow(1.0 - h, 4.5);
		col = mix(col, sky_horizon * mix(1.0, 1.10, 1.0 - night), clamp(hb * 1.25, 0.0, 1.0));
	}

	// Dither against banding in the smooth gradient.
	col += (hash12(FRAGCOORD.xy) - 0.5) * (1.5 / 255.0);
	COLOR = col * brightness;
}
