// Vernice dei mezzi (Agente F): mimetica triplanare in spazio oggetto (texture della fazione) moltiplicata per il colore
// di vertice, più invecchiamento procedurale economico: colature di sporco sulle pareti verticali, polvere sulle facce
// rivolte in alto, scheggiature della vernice (metallo nudo) e rugosità variabile. Un solo campionamento di rumore in più.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D camo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grime_tex : repeat_enable, filter_linear_mipmap;   // rumore in scala di grigi (R)
uniform bool use_camo = true;
uniform float camo_scale = 0.16;
uniform float sharp = 4.0;
uniform float base_rough = 0.8;
uniform float base_metal = 0.1;
uniform float wear = 1.0;          // 0 = vernice nuova, 1 = mezzo in servizio
uniform vec3 dust_col : source_color = vec3(0.58, 0.52, 0.41);
// fango accumulato in battaglia sulla parte bassa dello scafo (per istanza: lo imposta la vista con la distanza percorsa;
// stesso indice di wheel/track.gdshader così scafo, ruote e cingoli si sporcano insieme)
instance uniform float roll : instance_index(0) = 0.0;
instance uniform float mud : instance_index(1) = 0.0;
uniform float mud_h = 1.35;         // altezza (m, spazio modello) fino a cui arriva il fango

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
	vec3 w = pow(abs(n), vec3(sharp));
	w /= (w.x + w.y + w.z + 1e-4);
	vec3 alb = srgb_to_lin(COLOR.rgb);
	if (use_camo) {
		vec3 p = o_pos * camo_scale;
		vec3 c = texture(camo_tex, p.zy).rgb * w.x + texture(camo_tex, p.xz).rgb * w.y + texture(camo_tex, p.xy).rgb * w.z;
		alb *= c;
	}
	// rumore di invecchiamento: grana larga (macchie), colature verticali, grana fine (scheggiature)
	vec2 side_uv = vec2(o_pos.x + o_pos.z, o_pos.y * 0.18);
	float streak = texture(grime_tex, side_uv * vec2(1.6, 1.0)).r;
	float blot = texture(grime_tex, (o_pos.xz + o_pos.yy * 0.7) * 0.11).r;
	float fine = texture(grime_tex, (o_pos.xz * 1.9 + o_pos.y * vec2(1.3, -1.7)) * 1.4).r;
	float vert = 1.0 - abs(n.y);
	float up = clamp(n.y, 0.0, 1.0);
	// colature scure sulle pareti
	alb *= 1.0 - wear * vert * smoothstep(0.45, 0.85, streak) * 0.22;
	// polvere sulle superfici orizzontali e macchie larghe
	alb = mix(alb, srgb_to_lin(dust_col), wear * (up * up * smoothstep(0.35, 0.8, blot) * 0.38 + smoothstep(0.62, 0.9, blot) * 0.1));
	// scheggiature: piccole isole di metallo nudo
	float chip = wear * smoothstep(0.78, 0.84, fine) * (0.45 + 0.55 * up);
	alb = mix(alb, vec3(0.16, 0.155, 0.15), chip * 0.7);
	// fango di battaglia: schizzi che salgono dal basso con bordo frastagliato dal rumore
	float low = clamp(1.0 - o_pos.y / mud_h, 0.0, 1.0);
	float mk = mud * smoothstep(0.0, 0.6, low + (streak - 0.5) * 0.5) * (0.6 + 0.4 * blot) * (1.0 - up * 0.5);
	alb = mix(alb, vec3(0.2, 0.16, 0.11), clamp(mk, 0.0, 0.85));
	ALBEDO = alb;
	ROUGHNESS = clamp(base_rough + (blot - 0.5) * 0.18 - up * 0.04 - chip * 0.35 + mk * 0.3, 0.25, 1.0);
	METALLIC = mix(base_metal, 0.75, chip) * (1.0 - mk);
	SPECULAR = 0.45;
}
