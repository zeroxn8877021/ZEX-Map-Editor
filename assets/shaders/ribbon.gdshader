/*
 * Project   : ZEX Map Editor
 * Studio    : Zex Interactive
 * Author    : Paras Sharma
 * File      : ribbon.gdshader
 * Copyright : (c) Zex Interactive. All rights reserved.
 */

shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;
// Road / rail bed ribbon. UV.x across (0..1), UV.y along in metres / tile length. Soft edges via vertex alpha (COLOR.a).
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float edge_soft = 0.12;
void fragment() {
	vec3 c = texture(tex, UV).rgb * tint;
	ALBEDO = c;
	ROUGHNESS = 0.92;
	float e = min(UV.x, 1.0 - UV.x);
	ALPHA = smoothstep(0.0, edge_soft, e);
}
