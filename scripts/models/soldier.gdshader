// Soldati animati (Agente F): scheletro procedurale nel vertex shader, zero costo CPU per soldato.
// Ogni vertice porta in UV la posizione (x, z) del soldato nel modello della squadra e in UV2 (imbardata, osso + 16 * indice).
// Ossa: 1 busto, 2 testa, 3/4 coscia/stinco sinistri, 5/6 coscia/stinco destri, 7 braccia+fucile, 8 braccia+lanciarazzi.
// La mesh è costruita nella posa a riposo (in piedi, fucile in mira); qui si ricavano camminata/corsa, respiro, sguardo,
// in ginocchio, a terra, mira con rinculo e caduta del caduto. Parametri per istanza (uno per squadra, impostato dalla battaglia):
//   anim.x fase del passo (rad, integrata dalla CPU con la velocità: niente piedi che scivolano)
//   anim.y velocità (m/s nella scala del modello); se < 0: caduto da (-anim.y - 1) secondi
//   anim.z accovacciamento 0..1 (in ginocchio; il quinto soldato si sdraia), anim.w mira 0..1; anim.w > 1: mira (w - 1) e fa fuoco (rinculo)
// Il frammento è la vernice di paint.gdshader (mimetica triplanare sulla posa a riposo: la stoffa non "scorre"), con
// variazione per soldato: tono della pelle (`skin`: solo dove l'alfa del colore di vertice è 1) e stoffa più o meno stinta.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://scripts/models/soldier_rig.gdshaderinc"

uniform sampler2D camo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grime_tex : repeat_enable, filter_linear_mipmap;
uniform bool use_camo = true;
uniform float camo_scale = 0.16;
uniform float sharp = 4.0;
uniform float base_rough = 0.8;
uniform float base_metal = 0.1;
uniform float wear = 1.0;
uniform float spec = 0.45;
uniform vec3 emit : source_color = vec3(0.0);
uniform float emit_k = 0.0;
uniform vec3 dust_col : source_color = vec3(0.58, 0.52, 0.41);
uniform bool skin = false;          // pelle: tono diverso per soldato (dal chiaro allo scuro)
uniform float tone_var = 0.0;       // stoffa: ±tone_var di luminosità e un poco di tinta per soldato

varying vec3 o_pos;
varying vec3 o_nrm;
varying float v_rnd;

void vertex() {
	o_pos = VERTEX;
	o_nrm = NORMAL;
	float sidx = floor(UV2.y / 16.0 + 0.001);
	v_rnd = fract(sin(sidx * 91.7 + seed * 13.31 + 4.0) * 43758.5453);
	soldier_pose(VERTEX, NORMAL, UV, UV2, TIME);
}

vec3 srgb_to_lin(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void fragment() {
	vec3 n = normalize(o_nrm);
	vec3 alb = srgb_to_lin(COLOR.rgb);
	if (use_camo) {
		vec3 w = pow(abs(n), vec3(sharp));
		w /= (w.x + w.y + w.z + 1e-4);
		vec3 p = o_pos * camo_scale;
		vec3 c = texture(camo_tex, p.zy).rgb * w.x + texture(camo_tex, p.xz).rgb * w.y + texture(camo_tex, p.xy).rgb * w.z;
		alb *= c;
	}
	if (skin) {
		// toni: chiaro, olivastro, bruno, scuro (il colore di vertice è il tono medio)
		vec3 tn = v_rnd < 0.3 ? vec3(1.06, 1.0, 0.95) : (v_rnd < 0.62 ? vec3(0.9, 0.84, 0.78) : (v_rnd < 0.85 ? vec3(0.68, 0.6, 0.53) : vec3(0.42, 0.36, 0.31)));
		alb *= mix(vec3(1.0), tn, COLOR.a);
	} else if (tone_var > 0.0) {
		float k = (v_rnd - 0.5) * 2.0 * tone_var;
		alb *= vec3(1.0 + k, 1.0 + k * 0.85, 1.0 + k * 0.6);
	}
	float rough = base_rough;
	if (wear > 0.0) {
		float blot = texture(grime_tex, (o_pos.xz + o_pos.yy * 0.7) * 0.11).r;
		float up = clamp(n.y, 0.0, 1.0);
		alb = mix(alb, srgb_to_lin(dust_col), wear * (up * up * smoothstep(0.35, 0.8, blot) * 0.38 + smoothstep(0.62, 0.9, blot) * 0.1));
		// stoffa stinta a chiazze e fango/polvere su stivali e ginocchia (parte bassa del soldato, a riposo)
		float fade = texture(grime_tex, (o_pos.xz * 0.6 + o_pos.y * vec2(0.17, 0.11)) * 0.9).r;
		alb *= 1.0 + wear * (fade - 0.5) * 0.14 * (1.0 - COLOR.a * float(skin));
		float low = clamp(1.0 - o_pos.y / 0.75, 0.0, 1.0);
		float dl = wear * smoothstep(0.15, 0.95, low + (blot - 0.5) * 0.3) * 0.5 * (1.0 - COLOR.a * float(skin));
		alb = mix(alb, srgb_to_lin(dust_col) * 0.7, dl);
		rough = clamp(base_rough + (blot - 0.5) * 0.18 + dl * 0.15, 0.25, 1.0);
	}
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = base_metal;
	SPECULAR = spec;
	EMISSION = emit * emit_k;
}
