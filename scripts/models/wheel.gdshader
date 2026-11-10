// Ruote animate (Agente F): ogni vertice porta in UV il centro dell'asse (y, z) e in UV2.x il raggio della ruota;
// il vertex shader ruota la ruota attorno all'asse X del modello di `roll` metri percorsi (parametro per istanza, lo stesso
// dei cingoli in track.gdshader). Sul fianco del mozzo un disegno a fori che gira con la ruota rende il moto leggibile;
// il pneumatico si sporca di fango con `mud`. Nessun costo CPU per ruota: una sola chiamata per mezzo quando si muove.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

instance uniform float roll : instance_index(0) = 0.0;
instance uniform float mud : instance_index(1) = 0.0;
uniform sampler2D grime_tex : repeat_enable, filter_linear_mipmap;
uniform float base_rough = 0.9;
uniform float base_metal = 0.0;
uniform float spec = 0.3;
uniform bool tyre = true;

varying vec3 w_off;     // offset dal centro prima della rotazione (il disegno gira con la ruota)
varying vec3 w_nrm;     // normale prima della rotazione
varying float w_r;

vec3 srgb_to_lin(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void vertex() {
	vec3 c = vec3(VERTEX.x, UV.x, UV.y);
	w_r = max(UV2.x, 0.05);
	float a = -roll / w_r;
	float cs = cos(a);
	float sn = sin(a);
	vec3 d = VERTEX - c;
	w_off = d;
	w_nrm = NORMAL;
	VERTEX = c + vec3(d.x, d.y * cs - d.z * sn, d.y * sn + d.z * cs);
	NORMAL = vec3(NORMAL.x, NORMAL.y * cs - NORMAL.z * sn, NORMAL.y * sn + NORMAL.z * cs);
}

void fragment() {
	vec3 alb = srgb_to_lin(COLOR.rgb);
	float rough = base_rough;
	float side = abs(normalize(w_nrm).x);
	float rr = length(w_off.yz) / w_r;
	if (side > 0.7) {
		// fianco: anello esterno del cerchione, fori/razze che girano, dado centrale
		float ang = atan(w_off.z, w_off.y);
		float holes = smoothstep(0.35, 0.55, abs(fract(ang * 5.0 / 6.2831853 + 0.5) - 0.5) * 2.0) * smoothstep(0.78, 0.62, rr) * smoothstep(0.28, 0.4, rr);
		if (tyre) {
			// scanalature del battistrada viste di fianco e banda scura del tallone
			alb *= mix(0.75, 1.0, smoothstep(0.9, 0.96, rr));
		} else {
			alb *= mix(1.0, 0.55, holes);
			alb *= mix(1.0, 0.8, smoothstep(0.85, 0.95, rr));
			rough = mix(rough, 0.95, holes);
		}
	} else if (tyre) {
		// battistrada: tasselli che girano con la ruota
		float ang = atan(w_off.z, w_off.y);
		float lug = step(0.5, fract(ang * 14.0 / 6.2831853)) * step(0.5, fract(w_off.x * 7.0 + 0.25));
		alb *= mix(0.78, 1.0, lug);
	}
	// fango sul pneumatico e sul mozzo (accumulo con la distanza percorsa)
	float g = texture(grime_tex, w_off.yz * 1.3 + vec2(w_off.x * 2.0, 0.0)).r;
	float mk = mud * (0.35 + 0.65 * smoothstep(0.3, 0.75, g)) * (tyre ? 0.8 : 0.5);
	alb = mix(alb, vec3(0.2, 0.16, 0.11), clamp(mk, 0.0, 0.85));
	ALBEDO = alb;
	ROUGHNESS = clamp(max(rough, mk), 0.2, 1.0);
	METALLIC = base_metal * (1.0 - mk);
	SPECULAR = spec;
}
