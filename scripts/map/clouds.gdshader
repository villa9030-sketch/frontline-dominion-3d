// Tabellone: velo di nuvole leggere sopra l'oceano (più rade sulla terraferma) che si dirada avvicinandosi.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform vec2 world_size = vec2(160.0, 90.0);
uniform float fade = 1.0;      // 0 = invisibili (vicino), 1 = piene (vista d'insieme)
uniform float cover = 0.56;

#include "res://scripts/map/daynight.gdshaderinc"

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float a = 0.5, s = 0.0;
	for (int k = 0; k < 5; k++) { s += vnoise(p) * a; p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return s;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (fade < 0.01) discard;
	float t = TIME * 0.35;
	vec2 p = wpos.xz * 0.055 + vec2(t * 0.05, t * 0.012);
	vec2 q = vec2(fbm(p + vec2(0.0, t * 0.02)), fbm(p + vec2(5.2, 1.3)));
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float c = fbm(rot * (p * 1.3 + q * 1.4)) * 0.75 + fbm(rot * p * 3.1 + q) * 0.25;
	float d = smoothstep(cover, cover + 0.3, c);
	d *= d;
	// più rade sopra la terraferma
	vec2 uv = (wpos.xz + world_size * 0.5) / world_size;
	float land = 0.0;
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		land = smoothstep(-0.05, 0.25, texture(height_tex, uv).r);
	}
	// fuori dalla carta svaniscono
	vec2 o = max(abs(wpos.xz) - world_size * 0.5, 0.0);
	float out_f = 1.0 - smoothstep(0.0, 10.0, length(o));
	float a = d * mix(0.30, 0.06, land) * fade * out_f;
	if (a < 0.004) discard;
	float shade = 0.82 + 0.18 * smoothstep(0.3, 0.9, c);
	float day = dn_day(wpos);
	ALBEDO = vec3(0.86, 0.91, 0.95) * shade * mix(vec3(0.16, 0.19, 0.27), vec3(1.0), day) * mix(vec3(1.0), vec3(1.08, 0.86, 0.72), dn_twilight(wpos) * 0.6);
	ALPHA = a;
}
