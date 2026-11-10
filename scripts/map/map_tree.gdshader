// Tabellone: alberi in miniatura (MultiMesh con le mesh di Props.tree_mesh): colore di vertice schiarito, luce avvolgente,
// buio sul lato notturno della carta come il rilievo (ciclo condiviso daynight).
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

#include "res://scripts/map/daynight.gdshaderinc"

uniform vec3 tint = vec3(1.45, 1.42, 1.2);   // moltiplicatore lineare (niente source_color: il valore è già lineare)

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 alb = pow(COLOR.rgb, vec3(2.2)) * tint;
	// compressione morbida: chiome innevate e colori chiari non superano 1 (niente bagliore bianco col glow)
	alb = min(alb / (1.0 + alb * 0.5), vec3(0.72));
	float day = dn_day(wpos);
	float night = 1.0 - day;
	alb *= mix(vec3(1.0), vec3(1.08, 0.9, 0.75), dn_twilight(wpos) * 0.5);
	alb = mix(alb, alb * vec3(0.10, 0.12, 0.17), night);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ALBEDO = alb;
	EMISSION = alb * 0.12 * day;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
