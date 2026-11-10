// Tabellone: scintille del fronte (MultiMesh di quad a cartellone). CUSTOM = (fase 0..1, tipo, intensità 0..1, seme).
// Tipi: 0 fuoco che guizza, 1 fumo che sale, 2 vampata d'artiglieria (lampo breve e raro), 3 fumo industriale (ciminiere, chiaro
// e continuo), 4 fumo di conquista (denso, scuro, più grande). Lo stesso codice viene compilato in due varianti (additiva per
// fuoco e lampi, normale per il fumo): WorldMap sostituisce la riga render_mode.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float size_mul = 1.0;
uniform float cam_dist = 30.0;

varying vec4 cust;
varying float kind;
varying float alpha_k;
varying float heat;

float hash1(float p) { return fract(sin(p * 127.1) * 43758.5453); }

void vertex() {
	cust = INSTANCE_CUSTOM;
	kind = cust.y;
	heat = cust.z;
	float phase = cust.x;
	float seed = cust.w;
	float t = TIME;
	vec3 off = vec3(0.0);
	float s = 1.0;
	alpha_k = 1.0;
	// dimensione sullo schermo quasi costante: cresce con la distanza della telecamera
	float dk = clamp(cam_dist / 22.0, 0.7, 2.6);
	if (kind < 0.5) {
		// fuoco: guizza, leggermente più grande quando più caldo
		float fl = 0.6 + 0.4 * sin(t * (6.0 + seed * 4.0) + phase * 6.2831) * sin(t * 11.0 + seed * 9.0);
		s = (0.24 + 0.22 * heat) * (0.75 + 0.35 * fl);
		off.y = 0.08 + 0.05 * fl;
		alpha_k = 0.55 + 0.45 * fl;
	} else if (kind < 1.5) {
		// fumo: sale e si allarga, poi svanisce e riparte (ciclo di ~4 s per fase)
		float cyc = fract(t * (0.22 + 0.08 * hash1(seed)) + phase);
		s = (0.18 + 0.55 * cyc) * (0.7 + 0.6 * heat);
		off.y = 0.1 + cyc * 1.1;
		off.x = (hash1(seed + 3.0) - 0.5) * 0.4 * cyc + sin(t * 0.7 + seed) * 0.08 * cyc;
		alpha_k = (1.0 - cyc) * (0.35 + 0.35 * heat) * smoothstep(0.0, 0.12, cyc);
	} else if (kind < 2.5) {
		// lampo d'artiglieria: visibile per una frazione di secondo ogni 5–14 s
		float per = 5.0 + 9.0 * hash1(seed);
		float ph = fract(t / per + phase);
		float on = 1.0 - smoothstep(0.0, 0.035, ph);
		s = 0.42 * on * (0.6 + 0.5 * heat);
		off.y = 0.2;
		alpha_k = on * 0.9;
	} else if (kind < 3.5) {
		// fumo industriale: pennacchio chiaro e continuo, piegato dal vento
		float cyc = fract(t * 0.18 + phase);
		s = 0.10 + 0.32 * cyc;
		off.y = 0.02 + cyc * 0.75;
		off.x = cyc * cyc * 0.45 + sin(t * 0.9 + seed) * 0.04 * cyc;
		alpha_k = (1.0 - cyc) * 0.42 * smoothstep(0.0, 0.1, cyc);
	} else {
		// fumo di conquista: colonne dense e scure
		float cyc = fract(t * 0.16 + phase);
		s = (0.2 + 0.55 * cyc) * (0.6 + 0.4 * heat);
		off.y = 0.12 + cyc * 1.3;
		off.x = (hash1(seed + 1.0) - 0.5) * 0.4 * cyc;
		alpha_k = (1.0 - cyc) * 0.42 * heat * smoothstep(0.0, 0.1, cyc);
	}
	s *= size_mul * dk;
	// cartellone: la quad guarda sempre la telecamera
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	vec3 v = VERTEX * s;
	vec4 wp = bb * vec4(v, 1.0);
	wp.xyz += off * (0.5 + 0.5 * dk);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * wp;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float soft = 1.0 - smoothstep(0.2, 1.0, r);
	vec3 col;
	float a;
	if (kind < 0.5) {
		col = mix(vec3(1.0, 0.25, 0.05), vec3(1.0, 0.85, 0.4), soft * soft) * 2.2;
		a = soft * alpha_k;
	} else if (kind < 1.5) {
		col = vec3(0.22, 0.21, 0.20);
		a = soft * soft * alpha_k;
	} else if (kind < 2.5) {
		col = mix(vec3(1.0, 0.5, 0.15), vec3(1.0, 0.9, 0.6), soft * soft) * 1.8;
		a = soft * alpha_k;
	} else if (kind < 3.5) {
		col = vec3(0.62, 0.62, 0.60);
		a = soft * soft * alpha_k;
	} else {
		col = vec3(0.12, 0.11, 0.10);
		a = soft * soft * alpha_k;
	}
	if (a < 0.01) discard;
	ALBEDO = col;
	ALPHA = a;
}
