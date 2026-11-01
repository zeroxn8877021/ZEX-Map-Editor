/*
 * Project   : ZEX Map Editor
 * Studio    : Zex Interactive
 * Author    : Paras Sharma
 * File      : terrain_splat.gdshader
 * Copyright : (c) Zex Interactive. All rights reserved.
 */

shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
// 8-layer splat terrain, one material per 50 m tile. The 8 layers live in one Texture2DArray; weights come from two
// small RGBA splat tiles (1 px / m, 1 px border). Brush ring / grid / layer tiling + tint are GLOBAL shader parameters, so
// moving the cursor or recolouring a layer touches no material. Layers with ~0 weight are skipped, steep slopes get a
// second (side projected) sample, and a rotated large-scale sample hides texture repeats.

global uniform vec4 zx_brush;        // x, z, radius, active
global uniform vec4 zx_brush_col;
global uniform float zx_grid;
global uniform vec4 zx_tile_a;       // metres per repeat, layers 0-3
global uniform vec4 zx_tile_b;       // layers 4-7
global uniform vec4 zx_tint0;
global uniform vec4 zx_tint1;
global uniform vec4 zx_tint2;
global uniform vec4 zx_tint3;
global uniform vec4 zx_tint4;
global uniform vec4 zx_tint5;
global uniform vec4 zx_tint6;
global uniform vec4 zx_tint7;

uniform sampler2DArray layer_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D splat0 : filter_linear, repeat_disable;
uniform sampler2D splat1 : filter_linear, repeat_disable;
uniform vec4 splat_xform = vec4(0.0, 0.0, 50.0, 50.0);   // origin x, z, size x, z in metres
uniform float macro_amt = 0.22;

varying vec3 wpos;
varying vec3 wnrm;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

vec3 layer_col(int i, float tile, vec4 tintd, vec2 uvA, vec2 dxA, vec2 dyA, vec2 uvB, vec2 dxB, vec2 dyB, float steep) {
	vec3 c = textureGrad(layer_tex, vec3(uvA / tile, float(i)), dxA / tile, dyA / tile).rgb;
	vec2 uvR = vec2(uvA.x * 0.8 - uvA.y * 0.6, uvA.x * 0.6 + uvA.y * 0.8);
	vec3 c3 = textureGrad(layer_tex, vec3(uvR / (tile * 3.1) + 0.37, float(i)), dxA / (tile * 3.1), dyA / (tile * 3.1)).rgb;
	float avg = max(dot(textureLod(layer_tex, vec3(0.5, 0.5, float(i)), 9.0).rgb, vec3(0.333)), 0.02);
	c *= mix(1.0, clamp(dot(c3, vec3(0.333)) / avg, 0.55, 1.6), 0.6 * tintd.a);
	if (steep > 0.03) {
		vec3 c2 = textureGrad(layer_tex, vec3(uvB / tile, float(i)), dxB / tile, dyB / tile).rgb;
		c = mix(c, c2, steep);
	}
	return c * tintd.rgb;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = NORMAL;
}

void fragment() {
	vec2 suv = (wpos.xz - splat_xform.xy) / splat_xform.zw;
	vec4 a = texture(splat0, suv);
	vec4 b = texture(splat1, suv);
	float tot = a.r + a.g + a.b + a.a + b.r + b.g + b.b + b.a;
	if (tot < 0.001) { a = vec4(1, 0, 0, 0); tot = 1.0; }
	a /= tot; b /= tot;

	vec2 uvA = wpos.xz;
	vec2 dxA = dFdx(uvA); vec2 dyA = dFdy(uvA);
	vec2 uvB = vec2(wpos.x + wpos.z, wpos.y * 1.4);
	vec2 dxB = dFdx(uvB); vec2 dyB = dFdy(uvB);
	float steep = smoothstep(0.30, 0.55, 1.0 - normalize(wnrm).y);

	vec3 col = vec3(0.0);
	if (a.r > 0.01) col += a.r * layer_col(0, zx_tile_a.x, zx_tint0, uvA, dxA, dyA, uvB, dxB, dyB, steep);
	if (a.g > 0.01) col += a.g * layer_col(1, zx_tile_a.y, zx_tint1, uvA, dxA, dyA, uvB, dxB, dyB, steep);
	if (a.b > 0.01) col += a.b * layer_col(2, zx_tile_a.z, zx_tint2, uvA, dxA, dyA, uvB, dxB, dyB, steep);
	if (a.a > 0.01) col += a.a * layer_col(3, zx_tile_a.w, zx_tint3, uvA, dxA, dyA, uvB, dxB, dyB, steep);
	if (b.r > 0.01) col += b.r * layer_col(4, zx_tile_b.x, zx_tint4, uvA, dxA, dyA, uvB, dxB, dyB, steep);
	if (b.g > 0.01) col += b.g * layer_col(5, zx_tile_b.y, zx_tint5, uvA, dxA, dyA, uvB, dxB, dyB, steep);
	if (b.b > 0.01) col += b.b * layer_col(6, zx_tile_b.z, zx_tint6, uvA, dxA, dyA, uvB, dxB, dyB, steep);
	if (b.a > 0.01) col += b.a * layer_col(7, zx_tile_b.w, zx_tint7, uvA, dxA, dyA, uvB, dxB, dyB, steep);

	float m = vnoise(wpos.xz * 0.045) * 0.6 + vnoise(wpos.xz * 0.19) * 0.4;
	col *= 1.0 - macro_amt * 0.5 + macro_amt * m;

	if (zx_brush.w > 0.5) {
		float d = length(wpos.xz - zx_brush.xy);
		float w = max(0.25, zx_brush.z * 0.025);
		float ring = smoothstep(zx_brush.z - w, zx_brush.z, d) * (1.0 - smoothstep(zx_brush.z, zx_brush.z + w, d));
		float fill = (1.0 - smoothstep(zx_brush.z * 0.6, zx_brush.z, d)) * 0.10;
		col = mix(col, zx_brush_col.rgb, clamp(ring + fill, 0.0, 1.0));
	}
	if (zx_grid > 0.5) {
		vec2 g = wpos.xz / 10.0;
		vec2 ag = abs(fract(g - 0.5) - 0.5) / max(fwidth(g), vec2(0.0001));
		float line = 1.0 - min(min(ag.x, ag.y), 1.0);
		vec2 g5 = (wpos.xz + 25.0) / 50.0;
		vec2 ag5 = abs(fract(g5 - 0.5) - 0.5) / max(fwidth(g5), vec2(0.0001));
		float line5 = 1.0 - min(min(ag5.x, ag5.y), 1.0);
		col = mix(col, vec3(1.0), line * 0.20);
		col = mix(col, vec3(1.0, 0.85, 0.25), line5 * 0.75);
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
