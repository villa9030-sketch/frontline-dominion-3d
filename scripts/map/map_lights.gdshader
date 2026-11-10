// Tabellone: superfici luminose delle strutture (luci di gru, fari, torce dei pozzi, finestre di capannoni).
// Colore di vertice; tenui di giorno, accese di notte (ciclo condiviso daynight), con un lieve tremolio.
shader_type spatial;
render_mode unshaded, cull_back;

#include "res://scripts/map/daynight.gdshaderinc"

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float night = 1.0 - dn_day(wpos);
	float flick = 0.9 + 0.1 * sin(TIME * 3.0 + wpos.x * 7.0 + wpos.z * 5.0);
	vec3 c = COLOR.rgb;
	ALBEDO = c * 0.5;
	EMISSION = c * (0.25 + 2.2 * night) * flick;
}
