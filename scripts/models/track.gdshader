// Cingoli (Agente F): maglie procedurali lungo l'asse Z del mezzo (scanalature scure, pattini lucidati dal terreno),
// rilievo simulato perturbando la normale. Il nastro SCORRE con il parametro per istanza `roll` (metri percorsi, lo stesso
// delle ruote in wheel.gdshader): la metà inferiore verso +Z, quella superiore verso -Z, come un cingolo vero.
// `mud` sporca di fango la parte bassa. Nessuna texture oltre al rumore, costo trascurabile.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

instance uniform float roll : instance_index(0) = 0.0;
instance uniform float mud : instance_index(1) = 0.0;
uniform float link = 0.17;    // passo della maglia (m)

varying vec3 o_pos;
varying vec3 o_nrm;

vec3 srgb_to_lin(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void vertex() {
	o_pos = VERTEX;
	o_nrm = NORMAL;
}

void fragment() {
	vec3 n = normalize(o_nrm);
	// coordinata lungo il nastro: sul tratto orizzontale è z, sulle rampe anteriore/posteriore segue anche y;
	// il nastro scorre in verso opposto sopra e sotto (il centro del nastro è a y ≈ 0.5)
	float dir = sign(o_pos.y - 0.5);
	float ramp = o_pos.y * sign(o_pos.z) * (1.0 - abs(n.y)) * (1.0 - abs(n.x));
	float s = (o_pos.z + ramp + dir * roll) / link;
	float f = fract(s);
	float groove = smoothstep(0.0, 0.1, f) * (1.0 - smoothstep(0.78, 0.9, f));
	// perni visibili sul fianco del nastro
	float side = abs(n.x);
	float pin = side * (1.0 - smoothstep(0.0, 0.12, abs(f - 0.84))) * step(0.5, fract(o_pos.y * 3.5 + 0.25));
	// dente di guida centrale sulla faccia superiore del nastro
	float guide = (1.0 - side) * step(0.5, n.y) * smoothstep(0.26, 0.2, abs(f - 0.45)) * 0.5;
	vec3 alb = srgb_to_lin(COLOR.rgb);
	alb *= mix(0.45, 1.05, groove);
	alb = mix(alb, vec3(0.2, 0.19, 0.18), pin * 0.6);
	alb *= 1.0 - guide * 0.3;
	// fango sul fianco (polvere chiara) a chiazze, più fango con la distanza percorsa
	float mudp = clamp(sin(o_pos.z * 3.1 + o_pos.y * 7.0) * 0.5 + 0.5, 0.0, 1.0) * side;
	alb = mix(alb, vec3(0.19, 0.15, 0.1), mudp * 0.35);
	float mk = mud * clamp(1.0 - o_pos.y * 0.9, 0.2, 1.0) * (0.5 + 0.5 * mudp);
	alb = mix(alb, vec3(0.21, 0.17, 0.11), clamp(mk, 0.0, 0.8));
	ALBEDO = alb;
	float polished = groove * smoothstep(0.3, 0.9, abs(n.y)) * (1.0 - mk);
	METALLIC = mix(0.25, 0.6, polished);
	ROUGHNESS = mix(0.85, 0.5, polished);
	// rilievo: derivata del profilo della maglia lungo Z dell'oggetto
	float dh = (smoothstep(0.0, 0.1, fract(s + 0.02)) - smoothstep(0.0, 0.1, fract(s - 0.02))) - (smoothstep(0.78, 0.9, fract(s + 0.02)) - smoothstep(0.78, 0.9, fract(s - 0.02)));
	vec3 zv = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	NORMAL = normalize(NORMAL - zv * dh * 2.5);
}
