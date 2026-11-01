/*
 * Project   : ZEX Map Editor
 * Studio    : Zex Interactive
 * Author    : Paras Sharma
 * File      : water_surface.gdshader
 * Copyright : (c) Zex Interactive. All rights reserved.
 */

shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx, depth_draw_never;
// GTA-V style water. Depth is baked into the vertex colour (R * 4 m); presets only change the uniforms.
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_col : source_color = vec3(0.12, 0.66, 0.60);
uniform vec3 mid_col : source_color = vec3(0.05, 0.42, 0.50);
uniform vec3 deep_col : source_color = vec3(0.02, 0.20, 0.32);
uniform float wave_speed = 0.5;
uniform float wave_height = 0.012;
uniform float clarity = 1.0;       // 1 = clear, 0 = murky
uniform float foam_amount = 1.0;
uniform vec2 flow = vec2(0.0, 0.0); // river current direction (m/s-ish)

varying vec3 wpos;
varying float depth;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	depth = COLOR.r * 4.0;
	VERTEX.y += (sin(wpos.x * 0.8 + TIME * 1.1) + cos(wpos.z * 0.9 + TIME * 0.9)) * wave_height * smoothstep(0.0, 0.5, depth);
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 p = wpos.xz;
	vec2 fl = flow * TIME;
	float n1 = texture(noise_tex, p * 0.045 + vec2(t * 0.03, t * 0.02) - fl * 0.05).r;
	float n2 = texture(noise_tex, p * 0.11 - vec2(t * 0.04, -t * 0.03) - fl * 0.09).g;
	vec3 nrm = normalize(vec3((n1 - 0.5) * 0.9 + (n2 - 0.5) * 0.5, 1.0, (n2 - 0.5) * 0.9 - (n1 - 0.5) * 0.4));
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, normalize(VIEW)), 0.0, 1.0), 3.0);

	vec3 col = mix(shallow_col, mid_col, smoothstep(0.2, 1.4, depth));
	col = mix(col, deep_col, smoothstep(1.2, 3.2, depth));
	col *= 0.9 + n1 * 0.25;

	float pulse = 0.5 + 0.5 * sin(TIME * 1.4 + n2 * 6.0 + p.x * 0.15);
	float edge = depth + (n1 - 0.5) * 0.18 - pulse * 0.10;
	float foam = (1.0 - smoothstep(0.02, 0.32, edge)) * (0.75 + 0.25 * n2);
	float foam2 = (1.0 - smoothstep(0.36, 0.52, abs(edge - 0.55 - pulse * 0.12))) * 0.35 * (1.0 - smoothstep(0.4, 1.2, depth));
	float patch = smoothstep(0.72, 0.86, texture(noise_tex, p * 0.07 + vec2(t * 0.02, 0.0)).b) * 0.35 * smoothstep(0.3, 1.5, depth);
	float f = clamp((foam + foam2 + patch) * foam_amount, 0.0, 1.0);

	ALBEDO = mix(col, vec3(0.92, 0.97, 0.98), f);
	ROUGHNESS = mix(0.04, 0.6, f);
	SPECULAR = 0.7;
	EMISSION = f * vec3(0.05, 0.06, 0.06) + col * fres * 0.1;
	float alpha = mix(0.30 / max(clarity, 0.2), 0.92, smoothstep(0.0, 2.0 / max(clarity, 0.25), depth));
	alpha = mix(clamp(alpha, 0.0, 0.97), 0.95, f);
	ALPHA = clamp(alpha * smoothstep(0.0, 0.10, depth + f * 0.1) + fres * 0.1, 0.0, 1.0);
}
