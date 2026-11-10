// Tabellone: isolati delle città in miniatura (un unico MultiMesh). Mesh = parallelepipedo unitario con base in y = 0;
// la trasformazione d'istanza dà l'ingombro. COLOR = tinta dei muri, CUSTOM = (seme, quota finestre accese 0..1,
// densità finestre 0..1, 0 = palazzo / 1 = capannone industriale). Di notte le finestre si accendono (ciclo condiviso daynight).
shader_type spatial;
render_mode cull_back, diffuse_lambert_wrap, specular_schlick_ggx;

#include "res://scripts/map/daynight.gdshaderinc"

uniform float window_cell = 0.055;   // unità mondo per finestra
uniform float lit_boost = 1.0;

varying vec3 wpos;
varying vec3 opos;
varying vec3 scl;
varying vec4 cust;
varying vec3 onrm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
	scl = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	cust = INSTANCE_CUSTOM;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 wall = pow(COLOR.rgb, vec3(2.2));
	float seed = cust.x * 97.0;
	float lit_q = cust.y;
	float dens = cust.z;
	float industrial = cust.w;
	float side = 1.0 - abs(onrm.y);
	// coordinate di facciata (unità mondo): orizzontale lungo la faccia, verticale
	float u = abs(onrm.x) > 0.5 ? opos.z * scl.z : opos.x * scl.x;
	float v = opos.y * scl.y;
	vec2 g = vec2(u, v) / window_cell;
	vec2 id = floor(g);
	vec2 f = fract(g);
	// cella di finestra: rettangolo centrato, margini stretti; ultima fila sotto il tetto esclusa
	float wx = smoothstep(0.22, 0.30, f.x) * (1.0 - smoothstep(0.70, 0.78, f.x));
	float wy = smoothstep(0.30, 0.38, f.y) * (1.0 - smoothstep(0.72, 0.80, f.y));
	float top_ok = step(v + window_cell * 0.9, scl.y);
	float bottom_ok = step(window_cell * 0.35, v);
	float present = step(hash(id + vec2(seed, onrm.x * 3.0 + onrm.z * 7.0)), dens);
	float win = wx * wy * side * top_ok * bottom_ok * present;
	if (industrial > 0.5) {
		// capannoni: fasce di finestre alte e strette, poche
		win = smoothstep(0.1, 0.16, f.x) * (1.0 - smoothstep(0.84, 0.90, f.x)) * smoothstep(0.55, 0.62, f.y) * (1.0 - smoothstep(0.82, 0.88, f.y)) * side * top_ok * present;
	}
	// ombra alla base e facciata leggermente più chiara in alto
	float ao = 0.72 + 0.28 * smoothstep(0.0, 0.5, opos.y);
	vec3 alb = wall * ao;
	// tetto: grigio tecnico con pannelli
	vec3 roof = mix(wall * 0.55, vec3(0.30, 0.30, 0.29), 0.6);
	if (industrial > 0.5) roof = mix(wall * 0.7, vec3(0.42, 0.44, 0.46), 0.5);
	alb = mix(alb, roof, step(0.5, onrm.y));
	// finestre: vetro scuro di giorno, accese di notte
	vec3 glass = vec3(0.12, 0.15, 0.19);
	alb = mix(alb, glass, win * 0.8);
	float night = 1.0 - dn_day(wpos);
	float twl = dn_twilight(wpos);
	alb *= mix(vec3(1.0), vec3(1.10, 0.86, 0.70), twl * 0.5);
	alb = mix(alb, alb * vec3(0.06, 0.07, 0.10), night);
	float lit = step(hash(id * 1.7 + vec2(seed * 0.37, 2.1)), lit_q) * win;
	float flick = 0.85 + 0.15 * sin(TIME * (1.5 + hash(id + seed) * 3.0) + hash(id) * 6.28);
	vec3 warm = mix(vec3(1.0, 0.72, 0.38), vec3(0.85, 0.92, 1.0), step(0.85, hash(id + vec2(seed, 5.0))));
	vec3 emis = warm * lit * night * flick * 0.9 * lit_boost;
	// sui tetti alti una lucina rossa di segnalazione
	float beacon = step(0.5, onrm.y) * step(0.42, scl.y) * step(length(opos.xz - vec2(0.5)) * max(scl.x, scl.z), 0.012) * (0.5 + 0.5 * sin(TIME * 2.5 + seed));
	emis += vec3(1.0, 0.15, 0.1) * beacon * 2.0;
	ALBEDO = alb;
	EMISSION = emis + alb * 0.2 * (1.0 - night);
	ROUGHNESS = mix(0.8, 0.3, win);
	SPECULAR = 0.3;
}
