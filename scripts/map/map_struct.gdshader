// Tabellone: strutture in miniatura (porti, aeroporti, fabbriche, QG, fortificazioni) con colore di vertice (sRGB),
// che si spengono sul lato notturno della carta come il rilievo (ciclo condiviso daynight) e un lieve crepuscolo caldo.
shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap, specular_schlick_ggx;

#include "res://scripts/map/daynight.gdshaderinc"

uniform float roughness = 0.86;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 alb = pow(COLOR.rgb, vec3(2.2));
	float day = dn_day(wpos);
	float night = 1.0 - day;
	float twl = dn_twilight(wpos);
	alb *= mix(vec3(1.0), vec3(1.10, 0.86, 0.70), twl * 0.5);
	alb = mix(alb, alb * vec3(0.10, 0.12, 0.17), night);
	ALBEDO = alb;
	// luce di riempimento "da sala operativa": le facce in ombra restano leggibili
	EMISSION = alb * 0.22 * day;
	ROUGHNESS = roughness;
	SPECULAR = 0.3 * (1.0 - 0.7 * night);
}
