shader_type canvas_item;
// Photo-mode colour grade over the whole rendered frame.
// mode: 0 none, 1 warm, 2 cool, 3 vintage, 4 black and white.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform int mode = 0;
uniform float amount : hint_range(0.0, 1.0) = 1.0;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 src = texture(screen_tex, SCREEN_UV).rgb;
	vec3 c = src;
	vec2 uv = SCREEN_UV;
	float vig = smoothstep(0.95, 0.35, distance(uv, vec2(0.5)));
	if (mode == 1) {
		c = c * vec3(1.10, 1.02, 0.86) + vec3(0.025, 0.008, -0.02);
		c = mix(vec3(luma(c)), c, 1.12);
	} else if (mode == 2) {
		c = c * vec3(0.88, 1.0, 1.12) + vec3(-0.015, 0.0, 0.02);
		c = mix(vec3(luma(c)), c, 0.95);
	} else if (mode == 3) {
		float l = luma(c);
		vec3 sepia = vec3(l * 1.08, l * 0.92, l * 0.70);
		c = mix(c, sepia, 0.78);
		c = c * 0.86 + 0.09;                         // faded blacks and whites
		c *= mix(0.62, 1.0, vig);                    // dark corners
		c += (hash(uv * 900.0) - 0.5) * 0.05;        // grain
	} else if (mode == 4) {
		float l = luma(c);
		l = clamp((l - 0.5) * 1.18 + 0.5, 0.0, 1.0);
		c = vec3(l) * mix(0.82, 1.0, vig);
	}
	COLOR = vec4(mix(src, clamp(c, 0.0, 1.0), amount), 1.0);
}
