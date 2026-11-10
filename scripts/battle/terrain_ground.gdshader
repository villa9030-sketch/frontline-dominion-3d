// FRONTLINE DOMINION 3D — suolo della battaglia (Fase 7, BattleTerrain).
// Materiali per pendenza (erba/terra/ghiaione/roccia/neve), variazione di colore a grande scala, campi coltivati con siepi
// e capezzagne (pianura), alvei di fiumi/uadi, lago ghiacciato, strade sterrate con bordi, crateri della battaglia,
// occlusione d'ambiente cotta nei colori dei vertici (r = AO, g = cresta/cavità, b = alveo, a = ghiaccio del lago),
// vista d'insieme "da carta tattica" (ombreggiatura del rilievo e curve di livello), nebbia tattica e anelli di gittata.
shader_type spatial;
render_mode cull_back;
uniform vec3 c_ground : source_color;
uniform vec3 c_ground2 : source_color;
uniform vec3 c_dirt : source_color;
uniform vec3 c_rock : source_color;
uniform vec3 c_snow : source_color;
uniform vec3 c_sand : source_color;
uniform vec3 c_asphalt : source_color;
uniform vec3 c_concrete : source_color;
uniform vec3 c_park : source_color;
uniform float rock_slope = 0.3;
uniform float snow_line = 9999.0;
uniform int ttype = 0;
uniform bool has_sea = false;
uniform float river_wet = 1.0;      // 1 fiume (fango, ghiaia bagnata) / 0 uadi asciutto (sabbia, ciottoli)
uniform float overview = 0.0;       // 0 vicino ... 1 vista d'insieme
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D mask_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D scorch_tex : filter_linear, repeat_disable;
// Fase 8 (FX): solchi dei cingoli/ruote (r = terra smossa, g = fango/neve pressata), dipinti dalla vista sul rettangolo field_rect
uniform sampler2D track_tex : filter_linear, repeat_disable;
uniform float track_on = 0.0;
uniform float wetness = 0.0;       // 0 asciutto .. 1 pioggia battente: suolo scuro e lucido, pozzanghere nelle conche
uniform float snow_cover = 0.0;    // 0 .. 1 neve fresca che si accumula sopra tutto (artico/montagna)
uniform float relief_k = 1.0;      // intensità dell'ombreggiatura del rilievo (hillshade) e dell'AO cotta
// campi coltivati: r = tipo (0..5)/255, g = tinta, b > 0.6 bordo a capezzagna, a = 1 dove ci sono campi;
// texture in un riferimento ruotato: field_xf = (cos, sin, lato in m, attivo)
uniform sampler2D field_tex : filter_nearest, repeat_disable;
// stessa texture filtrata: bordo morbido e irregolare dei ritagli (boschi, lago) invece degli scalini dei texel
uniform sampler2D field_lin : filter_linear, repeat_disable;
uniform float detail_k = 1.0;
// texture fotografiche CC0 (Poly Haven, assets/textures/terrain): dettaglio reale sopra i colori del terreno.
// Si usano come "modulazione": colore della texture / suo colore medio, così tinte di campi, strade e stagioni restano.
uniform float tex_k = 0.0;          // 0 spente (vecchio aspetto), 1 accese
uniform float tex_two = 1.0;        // 1 = due scale mescolate (niente ripetizione visibile); 0 = una sola (qualità bassa)
uniform sampler2D t_grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D n_grass : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_dirt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D n_dirt : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D n_rock : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_snow : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D n_snow : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_sand : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D n_sand : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_leaf : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D n_leaf : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 a_grass : source_color = vec3(0.431, 0.376, 0.243);
uniform vec3 a_dirt : source_color = vec3(0.451, 0.357, 0.243);
uniform vec3 a_rock : source_color = vec3(0.431, 0.361, 0.204);
uniform vec3 a_snow : source_color = vec3(0.647, 0.647, 0.655);
uniform vec3 a_sand : source_color = vec3(0.620, 0.541, 0.506);
uniform vec3 a_leaf : source_color = vec3(0.557, 0.439, 0.227);
uniform float sat_k = 1.0;          // saturazione finale (1 = naturale)
// paesaggio esteso (BattleLandscape): mosaico di campi, masse boscose, neve sulle montagne lontane, ombre delle nuvole
uniform float far_on = 0.0;
uniform float far_snow = 9999.0;    // quota della neve sulle montagne lontane
uniform float forest_amt = 0.25;    // quota di territorio coperta da boschi (0..1)
uniform float mosaic_on = 1.0;      // 0 = niente campi coltivati lontani (deserto, artico)
uniform float cloud_k = 0.0;        // ombre delle nuvole sul terreno
uniform vec4 woods[64];             // boschi del campo (X, Z, raggio, 0): da lontano chioma dipinta al posto degli alberi 3D
uniform int wood_n = 0;
uniform vec3 horizon_col : source_color = vec3(0.68, 0.74, 0.8);       // dettaglio ravvicinato (ciuffi, sassi, strisce di sfalcio): 0 su qualità bassa
uniform vec4 field_xf = vec4(1.0, 0.0, 2000.0, 0.0);
uniform vec4 mask_rect;
uniform vec4 field_rect;
// nebbia tattica: texture (bianco = in vista) sul rettangolo del campo; 0 = spenta
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform float fog_on = 0.0;
// anelli di gittata/vista delle unità selezionate: (X, Z, raggio, tipo 0 arma / 1 vista / 2 gittata minima)
uniform vec4 rings[48];
uniform int ring_n = 0;
uniform vec3 ring_col : source_color = vec3(1.0, 0.8, 0.4);
// vista strategica (BattleStrategic): influenza r = attaccante, g = difensore (48×27 sul campo), front_k 0..1 con la quota
uniform sampler2D front_tex : filter_linear, repeat_disable;
uniform float front_k = 0.0;
uniform vec3 front_col_a : source_color = vec3(0.3, 0.5, 1.0);
uniform vec3 front_col_d : source_color = vec3(1.0, 0.3, 0.25);
varying vec3 wpos;
varying vec3 wnrm;
varying vec4 vcol;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR;
	TANGENT = normalize(cross(vec3(0.0, 0.0, 1.0), NORMAL));
	BINORMAL = normalize(cross(NORMAL, TANGENT));
}

// 1 grano maturo, 2 coltura verde, 3 arato (solchi), 4 stoppie, 5 erba medica scura
vec3 crop(float t, vec2 q, float tint, float n3, float n4, float fine) {
	if (t < 1.5) { return vec3(0.56, 0.46, 0.23) * (0.9 + 0.2 * tint) * (0.93 + 0.1 * n4 * fine + 0.05 * sin(q.y * 2.4) * fine); }
	if (t < 2.5) { return vec3(0.26, 0.4, 0.13) * (0.88 + 0.22 * tint) * (0.95 + 0.08 * sin(q.y * 3.1) * fine); }
	if (t < 3.5) {
		float furrow = 0.5 + 0.5 * sin(q.y * 4.2);
		return mix(vec3(0.27, 0.21, 0.15), vec3(0.38, 0.3, 0.22), furrow * (0.3 + 0.7 * fine) + n3 * 0.2) * (0.92 + 0.15 * tint);
	}
	if (t < 4.5) { return vec3(0.5, 0.44, 0.27) * (0.9 + 0.15 * tint) * (0.96 + 0.07 * sin(q.y * 5.0) * fine); }
	return vec3(0.17, 0.29, 0.1) * (0.9 + 0.2 * tint);
}

// texture a due scale (la seconda ruotata): la ripetizione della piastrella non si vede
vec3 tx2(sampler2D t, vec2 ua, vec2 ub, float k) {
	vec3 a = texture(t, ua).rgb;
	return k > 0.001 ? mix(a, texture(t, ub).rgb, k) : a;
}
vec3 nx2(sampler2D t, vec2 ua, vec2 ub, float k) {
	vec3 a = texture(t, ua).rgb;
	return k > 0.001 ? mix(a, texture(t, ub).rgb, k) : a;
}

float hash12(vec2 v) {
	v = fract(v * vec2(123.34, 456.21));
	v += dot(v, v + 45.32);
	return fract(v.x * v.y);
}

// Maschera dei boschi del paesaggio (stessa formula in BattleLandscape.forest_at): 0 aperto .. 1 bosco fitto
float forest_mask(vec2 p, float amt) {
	float a = texture(noise_tex, p / 2600.0 + vec2(0.13, 0.77)).r * 0.8 + texture(noise_tex, p / 700.0 + vec2(0.51, 0.29)).r * 0.2;
	float th = 0.69 - 0.4 * amt;   // calibrata sulla distribuzione della texture di rumore: amt ≈ frazione coperta
	return smoothstep(th, th + 0.02, a);
}

void fragment() {
	vec2 p = wpos.xz;
	float n1 = texture(noise_tex, p / 211.0).r;
	float n2 = texture(noise_tex, p / 37.0 + 0.3).r;
	float n3 = texture(noise_tex, p / 7.1 + 0.6).r;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	// oltre ~1 km (vista strategica) le letture fini sono sotto il pixel: si saltano (costano quanto tutto il resto)
	bool near_px = dist < 1000.0;
	float far_k = smoothstep(650.0, 1000.0, dist);
	float n4 = near_px ? texture(noise_tex, p / 1.37).r : 0.5;
	float macro2 = texture(noise_tex, p / 1300.0 + 0.71).r;
	float fine = 1.0 - smoothstep(60.0, 260.0, dist);
	vec3 nrm = normalize(wnrm);
	float slope = 1.0 - nrm.y;
	vec2 fh = field_rect.zw * 0.5;
	vec2 ofd = max(abs(p) - fh, vec2(0.0));
	float far_d = length(ofd);
	float far_mix = smoothstep(250.0, 700.0, far_d);
	float ao = vcol.r;
	float ridge = vcol.g - 0.5;
	float wet = vcol.b;
	float ice = vcol.a;
	vec3 col = mix(c_ground, c_ground2, smoothstep(0.32, 0.68, n1 * 0.55 + n2 * 0.45));
	col *= 0.86 + 0.28 * n3 + (n4 - 0.5) * 0.22 * fine;
	float w_dirt = smoothstep(0.6, 0.82, n2 * 0.6 + n3 * 0.4) * 0.45;
	col = mix(col, c_dirt * (0.85 + 0.3 * n3), w_dirt);
	float macro = texture(noise_tex, p / 520.0 + 0.17).r;
	col *= mix(vec3(0.92, 0.95, 0.88), vec3(1.06, 1.02, 0.94), macro);
	col *= mix(vec3(0.88, 0.92, 0.86), vec3(1.08, 1.04, 0.95), macro2);
	// lontano: versanti erbosi, roccia solo se ripidi; verso la quota della neve torna la roccia (creste nude)
	float rs = mix(rock_slope, max(rock_slope, 0.3) - 0.2 * smoothstep(far_snow * 0.45, far_snow * 0.9, wpos.y), far_mix);
	float rk = smoothstep(rs, rs * 2.0 + 0.01, slope + (n3 - 0.5) * 0.06);
	// ghiaione / terra smossa sui pendii medi
	float scree = smoothstep(rs * 0.38, rs * 0.85, slope + (n2 - 0.5) * 0.08) * (1.0 - rk);
	float strata = near_px ? texture(noise_tex, vec2(p.x * 0.05 + p.y * 0.05, wpos.y * 0.35)).r * (1.0 - smoothstep(200.0, 600.0, dist)) : 0.0;
	float dry = smoothstep(0.55, 0.75, texture(noise_tex, p / 90.0 + 0.41).r) * (1.0 - rk);
	col = mix(col, col * vec3(1.18, 1.08, 0.82), dry * 0.35 * float(ttype != 2));
	// tinta "dipinta": chiazze ampie che virano tra verde-giallo caldo e verde-azzurro freddo
	float hue = detail_k > 0.5 ? texture(noise_tex, p / 160.0 + vec2(0.53, 0.11)).r : n1;
	col *= mix(vec3(0.95, 1.0, 1.06), vec3(1.07, 1.02, 0.88), smoothstep(0.3, 0.7, hue)) * float(ttype != 5) + vec3(1.0) * float(ttype == 5);
	// ciuffi d'erba (macchie scure con punte chiare) e sassi: solo vicino alla telecamera
	float near_d = fine * detail_k;
	// (letture saltate da lontano: la vista alta copre tutto lo schermo di terreno)
	float tuft = 0.0;
	float pebble = 0.0;
	float peb_n = 0.0;
	if (near_d > 0.001) {
		float tuft_n = texture(noise_tex, p / 0.55 + vec2(0.13, 0.71)).r;
		tuft = smoothstep(0.6, 0.74, tuft_n) * near_d * (1.0 - rk) * float(ttype != 1 && ttype != 5);
		float tip = smoothstep(0.36, 0.24, tuft_n) * near_d * (1.0 - rk);
		col *= 1.0 - 0.22 * tuft;
		col = mix(col, col * vec3(1.12, 1.14, 1.0) + vec3(0.015, 0.02, 0.0), tip * 0.45);
		peb_n = texture(noise_tex, p / 0.27 + vec2(0.77, 0.29)).r;
		pebble = smoothstep(0.82, 0.88, peb_n) * near_d;
	}
	// campi coltivati, siepi e capezzagne (solo dove il terreno è dolce)
	if (field_xf.w > 0.5) {
		vec2 q = vec2(p.x * field_xf.x + p.y * field_xf.y, -p.x * field_xf.y + p.y * field_xf.x);
		vec2 fuv = q / field_xf.z + 0.5;
		if (fuv.x > 0.0 && fuv.y > 0.0 && fuv.x < 1.0 && fuv.y < 1.0) {
			vec4 fd = texture(field_tex, fuv);
			float e1 = 1.6 / field_xf.z;
			vec4 fa = texture(field_tex, fuv + vec2(e1, 0.0));
			vec4 fb = texture(field_tex, fuv + vec2(0.0, e1));
			float edge = step(0.002, abs(fa.r - fd.r) + abs(fa.g - fd.g) + abs(fb.r - fd.r) + abs(fb.g - fd.g));
			// fascia d'erba incolta lungo i confini (4.5 m, su entrambi i lati): cornice dei campi da "plastico"
			float verge = 0.0;
			if (detail_k > 0.5) {   // qualità bassa: niente fascia d'erba (4 letture in meno)
				float e2 = 4.5 / field_xf.z;
				vec4 fc = texture(field_tex, fuv - vec2(e2, 0.0));
				vec4 fe = texture(field_tex, fuv - vec2(0.0, e2));
				vec4 ff = texture(field_tex, fuv + vec2(e2, 0.0));
				vec4 fg = texture(field_tex, fuv + vec2(0.0, e2));
				verge = step(0.002, abs(fc.r - fd.r) + abs(fc.g - fd.g) + abs(fe.r - fd.r) + abs(fe.g - fd.g)
					+ abs(ff.r - fd.r) + abs(ff.g - fd.g) + abs(fg.r - fd.r) + abs(fg.g - fd.g));
			}
			// ritaglio morbido e irregolare (boschi, lago): alfa filtrata con una leggera deformazione a rumore
			float fal = detail_k > 0.5 ? smoothstep(0.38, 0.62, texture(field_lin, fuv + (vec2(n2, n1) - 0.5) * (10.0 / field_xf.z)).a) : fd.a;
			float fw = (1.0 - smoothstep(0.035, 0.1, slope)) * (1.0 - smoothstep(0.0, 0.3, wet)) * fal;
			float t = fd.r * 255.0;
			if (t > 0.5) {
				vec3 cc = crop(t, q, fd.g, n3, n4, fine);
				// strisce di sfalcio/raccolto (direzione e passo per campo) e sfumatura ampia dentro il campo
				float dir = step(0.5, fract(fd.g * 7.3));
				float lane = mix(q.x, q.y, dir) / (5.0 + fd.g * 4.0) + fd.g * 11.0;
				float stripe = smoothstep(0.35, 0.5, abs(fract(lane) - 0.5) * 2.0);
				float sk = (t < 1.5 || t > 3.5) ? 0.09 : 0.05;
				cc *= 1.0 + (stripe - 0.5) * sk * (0.4 + 0.6 * fine) * (0.5 + 0.5 * detail_k);
				cc *= 0.93 + 0.14 * (detail_k > 0.5 ? texture(noise_tex, q / 75.0 + fd.g * 3.0).r : n2);
				col = mix(col, cc, fw * 0.92);
				// arato: terra; stoppie e grano: terra che affiora tra gli steli
				w_dirt = max(w_dirt, fw * (t > 2.5 && t < 3.5 ? 0.95 : (t > 3.5 && t < 4.5 ? 0.45 : (t < 1.5 ? 0.3 : 0.0))));
				col = mix(col, mix(col, vec3(0.3, 0.38, 0.16) * (0.85 + 0.3 * n3), 0.75), verge * (1.0 - edge) * fw * 0.8);
			}
			vec3 border = fd.b > 0.6 ? c_dirt * (1.0 + 0.2 * n3) : vec3(0.15, 0.22, 0.08) * (0.8 + 0.3 * n3);
			col = mix(col, border, edge * fw * 0.9);
			w_dirt = max(w_dirt, edge * fw * float(fd.b > 0.6));
		}
	}
	col = mix(col, c_dirt * (0.8 + 0.3 * n3), scree * (ttype == 5 ? 0.25 : 0.55));
	w_dirt = max(w_dirt, scree * 0.8);
	vec3 rockc = c_rock * (0.7 + 0.45 * n4 * fine + 0.25 * strata);
	rockc *= 0.9 + 0.16 * sin(wpos.y * 1.9 + n2 * 5.0) * float(ttype == 1 || ttype == 3);
	col = mix(col, rockc, rk);
	float sn = smoothstep(snow_line, snow_line + 10.0, wpos.y + (n2 - 0.5) * 22.0) * (1.0 - smoothstep(0.42, 0.62, slope));
	col = mix(col, c_snow * (0.93 + 0.07 * n4), sn);
	if (ttype == 5) {
		// neve: creste dei cumuli più luminose, conche azzurrine
		col *= 1.0 + ridge * 0.3;
		col = mix(col, col * vec3(0.84, 0.91, 1.05), clamp(-ridge * 3.0, 0.0, 1.0) * 0.6);
	}
	// alvei: fango e ghiaia bagnata (fiume) o sabbia e ciottoli (uadi)
	if (wet > 0.0) {
		// fiume: erba umida piu' scura sulle sponde, fango solo a ridosso dell'acqua; uadi: sabbia e ciottoli
		vec3 bank = river_wet > 0.5
			? mix(col * vec3(0.7, 0.78, 0.58), c_dirt * 0.55, smoothstep(0.45, 0.95, wet + (n3 - 0.5) * 0.3))
			: mix(c_sand * 0.96, c_rock * 0.9, smoothstep(0.62, 0.85, n3));
		if (ttype == 5) { bank = mix(bank, vec3(0.78, 0.82, 0.86), 0.6); }
		col = mix(col, bank * (0.88 + 0.2 * n4 * fine), smoothstep(0.1, 0.8, wet) * (1.0 - rk * 0.5));
		w_dirt = max(w_dirt, smoothstep(0.3, 0.9, wet));
	}
	// lago ghiacciato: ghiaccio con crepe e neve spazzata dal vento
	if (ice > 0.0) {
		float crack = 1.0 - smoothstep(0.0, 0.012, abs(n2 - 0.5));
		float crack2 = 1.0 - smoothstep(0.0, 0.01, abs(texture(noise_tex, p / 13.0 + 0.2).r - 0.5));
		vec3 icec = mix(vec3(0.56, 0.7, 0.8), vec3(0.76, 0.86, 0.92), n1) * (0.95 + 0.08 * n4);
		icec = mix(icec, vec3(0.92, 0.95, 0.98), smoothstep(0.55, 0.75, texture(noise_tex, p / 29.0 + vec2(0.1, 0.4)).r) * 0.75);
		icec = mix(icec, icec * 0.7, max(crack, crack2 * 0.7) * (0.3 + 0.7 * fine));
		col = mix(col, icec, ice);
	}
	float wet_s = 0.0;
	float w_beach = 0.0;
	if (has_sea) {
		float b = 1.0 - smoothstep(0.9, 1.7, wpos.y + (n3 - 0.5) * 0.5);
		w_beach = b;
		col = mix(col, c_sand * (0.88 + 0.22 * n4), b);
		wet_s = 1.0 - smoothstep(-0.3, 0.6, wpos.y);
		col *= mix(1.0, 0.62, wet_s);
		col = mix(col, col * vec3(0.55, 0.75, 0.8), smoothstep(0.0, -3.0, wpos.y));
	}
	vec2 muv = (p - mask_rect.xy) / mask_rect.zw;
	float inm = step(0.0, muv.x) * step(muv.x, 1.0) * step(0.0, muv.y) * step(muv.y, 1.0);
	vec4 m = texture(mask_tex, muv) * inm;
	float road = 0.0;
	if (ttype == 2) {
		if (inm < 0.5) { m = vec4(0.0, 1.0, 0.0, 0.0); }
		vec3 asph = c_asphalt * (0.85 + 0.25 * n4 * fine + 0.12 * n3);
		asph = mix(asph, asph * 0.7, smoothstep(0.55, 0.75, n2) * 0.6);
		vec3 conc = c_concrete * (0.82 + 0.18 * n4 * fine + 0.1 * n2);
		float tiles = step(0.06, fract(p.x * 0.5)) * step(0.06, fract(p.y * 0.5));
		conc *= mix(0.86, 1.0, tiles * fine + (1.0 - fine));
		vec3 park = c_park * (0.8 + 0.35 * n3 + 0.15 * n4);
		vec3 uc = col;
		uc = mix(uc, conc, clamp(m.g, 0.0, 1.0));
		uc = mix(uc, park, clamp(m.b, 0.0, 1.0));
		uc = mix(uc, asph, clamp(m.r, 0.0, 1.0) * (1.0 - m.g));
		uc = mix(uc, vec3(0.86, 0.84, 0.72), m.a * 0.9);
		col = mix(col, uc, 1.0 - rk);
		// terrapieno ferroviario: massicciata
		col = mix(col, vec3(0.42, 0.4, 0.37) * (0.8 + 0.4 * n4), scree * 0.8 * (1.0 - m.g));
	} else {
		// strada sterrata: carreggiata compatta, bordi d'erba più scura, solchi delle ruote
		road = smoothstep(0.3, 0.7, m.r + (n3 - 0.5) * 0.3) * (has_sea ? smoothstep(0.6, 1.2, wpos.y) : 1.0);
		float shoulder = smoothstep(0.03, 0.3, m.r) * (1.0 - road);
		// margine: fosso d'erba scura all'esterno, ciglio di ghiaia chiara subito dentro la carreggiata
		float ditch = smoothstep(0.02, 0.12, m.r) * (1.0 - smoothstep(0.18, 0.32, m.r));
		col = mix(col, col * 0.8, shoulder * 0.55);
		col = mix(col, col * vec3(0.66, 0.72, 0.6), ditch * 0.6);
		vec3 dirt = c_dirt * (0.82 + 0.35 * n4 * fine + 0.12 * n3) * 1.12;
		dirt *= 1.0 - 0.14 * smoothstep(0.8, 0.97, m.r) * fine;
		float lip = smoothstep(0.45, 0.6, m.r) * (1.0 - smoothstep(0.75, 0.92, m.r));
		dirt = mix(dirt, c_dirt * 1.45 + vec3(0.03), lip * 0.55);
		if (ttype == 5) { dirt = mix(dirt, vec3(0.6, 0.6, 0.6), 0.5); }
		col = mix(col, dirt, road * 0.95);
		w_dirt = max(w_dirt, road);
		pebble = max(pebble, smoothstep(0.78, 0.84, peb_n) * near_d * road);
	}
	// sassi: puntini chiari con l'ombra in basso (su ghiaioni, strade, terra secca, rocce)
	float peb_area = clamp(scree + rk + dry * 0.5 + 0.25 + float(ttype == 1) * 0.4, 0.0, 1.0) * (1.0 - wet);
	col = mix(col, mix(c_rock * 1.25, vec3(0.72, 0.7, 0.64), 0.4) * (0.85 + 0.3 * n4), pebble * peb_area * 0.75);
	// ---- paesaggio esteso: oltre il campo di battaglia, mosaico di campi e grandi boschi
	float canopy = 0.0;
	if (far_on > 0.5 && far_d > 120.0) {
		float fk = smoothstep(120.0, 520.0, far_d);
		bool in_ftex = false;
		if (field_xf.w > 0.5) {
			vec2 q0 = vec2(p.x * field_xf.x + p.y * field_xf.y, -p.x * field_xf.y + p.y * field_xf.x);
			vec2 fu0 = q0 / field_xf.z + 0.5;
			in_ftex = fu0.x > 0.02 && fu0.y > 0.02 && fu0.x < 0.98 && fu0.y < 0.98;
		}
		// solo terreno dolce: sui versanti i bordi dei campi diventavano "curve di livello"
		float flat_ok = (1.0 - smoothstep(0.03, 0.09, slope)) * (1.0 - rk) * (1.0 - smoothstep(far_snow * 0.55, far_snow * 0.8, wpos.y));
		if (mosaic_on > 0.05 && !in_ftex && flat_ok > 0.01) {
			// appezzamenti a file sfalsate, orientamento costante per regione di 1,7 km (un angolo che variasse con
			// continuità piegava i confini in curve)
			vec2 cellp = floor(p / 1700.0);
			float ang = (hash12(cellp + 0.37) - 0.5) * 2.4;
			vec2 pc = p - (cellp + 0.5) * 1700.0;
			vec2 q = vec2(pc.x * cos(ang) + pc.y * sin(ang), -pc.x * sin(ang) + pc.y * cos(ang)) + cellp * 977.0;
			float rowh = 45.0 + 40.0 * hash12(vec2(floor(q.y / 90.0), 3.1));
			float ry = floor(q.y / rowh);
			float cw = 50.0 + 90.0 * hash12(vec2(ry, 7.7));
			float rx = floor((q.x + hash12(vec2(ry, 1.3)) * 300.0) / cw);
			float h1 = hash12(vec2(rx, ry));
			float h2 = hash12(vec2(ry, rx) + 0.5);
			float ct = h1 < 0.28 ? 0.0 : floor(1.0 + h2 * 5.0);
			vec2 lq = vec2(fract((q.x + hash12(vec2(ry, 1.3)) * 300.0) / cw) * cw, fract(q.y / rowh) * rowh);
			float edge_d = min(min(lq.x, cw - lq.x), min(lq.y, rowh - lq.y));
			float hedge = 1.0 - smoothstep(1.2, 3.2, edge_d);
			vec3 mc = ct > 0.5 ? crop(ct, q, h2, n3, n4, fine) : col * (0.92 + 0.16 * h2);
			// colori dei campi lontani più vicini tra loro (niente scacchiera): mosaico leggibile ma morbido
			mc = mix(mc, col, 0.35);
			float mw = fk * flat_ok * mosaic_on;
			col = mix(col, mc, mw * 0.8);
			col = mix(col, vec3(0.13, 0.2, 0.08) * (0.8 + 0.3 * n3), hedge * mw * 0.7 * (1.0 - smoothstep(600.0, 2200.0, dist)));
			w_dirt = max(w_dirt, mw * (ct > 2.5 && ct < 3.5 ? 0.9 : (ct > 3.5 && ct < 4.5 ? 0.4 : 0.0)));
		}
		// grandi boschi (chiome dipinte: da lontano gli alberi 3D non servono)
		canopy = forest_mask(p, forest_amt) * fk * (1.0 - smoothstep(0.45, 0.7, slope)) * (1.0 - smoothstep(far_snow * 0.85, far_snow, wpos.y)) * (1.0 - wet);
		if (canopy > 0.001) {
			float crowns = texture(noise_tex, p / 7.0 + 0.4).r * 0.6 + texture(noise_tex, p / 23.0 + 0.1).r * 0.4;
			bool conif = ttype == 3 || ttype == 5 || wpos.y > far_snow * 0.45;
			vec3 cc = conif ? vec3(0.04, 0.062, 0.038) : vec3(0.05, 0.08, 0.034);
			cc *= 0.62 + 0.76 * crowns;
			cc *= 0.8 + 0.4 * texture(noise_tex, p / 140.0 + 0.6).r;
			// margine del bosco più scuro (ombra delle chiome sul prato)
			cc *= mix(0.75, 1.0, smoothstep(0.0, 0.6, canopy));
			col = mix(col, cc, canopy);
		}
		// neve sulle montagne lontane
		float snf = smoothstep(far_snow, far_snow + 60.0, wpos.y + (n2 - 0.5) * 90.0) * (1.0 - smoothstep(0.6, 0.85, slope)) * fk * (1.0 - canopy);
		if (snf > 0.001) {
			col = mix(col, c_snow * (0.9 + 0.1 * n4), snf);
			sn = max(sn, snf);
		}
	}
	// boschi del campo visti da lontano (gli alberi 3D spariscono oltre ~1.4 km)
	if (wood_n > 0 && dist > 950.0) {
		float wk = smoothstep(950.0, 1350.0, dist);
		float inw = 0.0;
		for (int i = 0; i < wood_n; i++) {
			vec4 w = woods[i];
			float dd = length(p - w.xy);
			inw = max(inw, 1.0 - smoothstep(w.z * 0.85, w.z * 1.05, dd + (n2 - 0.5) * w.z * 0.25));
		}
		if (inw > 0.001) {
			float crowns = texture(noise_tex, p / 7.0 + 0.4).r * 0.6 + texture(noise_tex, p / 23.0 + 0.1).r * 0.4;
			vec3 cc = (ttype == 3 || ttype == 5) ? vec3(0.055, 0.085, 0.05) : vec3(0.07, 0.11, 0.045);
			col = mix(col, cc * (0.7 + 0.6 * crowns), inw * wk);
			canopy = max(canopy, inw * wk);
		}
	}
	// ---- texture fotografiche: modulazione del colore e rilievo fine
	vec3 tex_n = vec3(0.5, 0.5, 1.0);
	float tex_on = tex_k * (1.0 - ice) * float(ttype != 2 || inm < 0.5 || m.g < 0.5);
	if (tex_on > 0.001) {
		vec2 ua = p / 3.2;
		vec2 ub = vec2(p.x * 0.8 - p.y * 0.6, p.x * 0.6 + p.y * 0.8) / 8.9 + vec2(0.37, 0.71);
		float kb = tex_two * (0.35 + 0.3 * smoothstep(0.3, 0.7, n2));
		// fondo: erba (sabbia nel deserto, neve nell'artico, sottobosco a chiazze in foresta)
		vec3 base_a = ttype == 1 ? a_sand : (ttype == 5 ? a_snow : a_grass);
		vec3 det = vec3(1.0);
		vec3 tn = vec3(0.5, 0.5, 1.0);
		if (near_px) {
			vec3 base_c; vec3 base_n;
			if (ttype == 1) {
				base_c = tx2(t_sand, ua, ub, kb); base_n = nx2(n_sand, ua, ub, kb);
			} else if (ttype == 5) {
				base_c = tx2(t_snow, ua, ub, kb); base_n = nx2(n_snow, ua, ub, kb);
			} else {
				base_c = tx2(t_grass, ua, ub, kb); base_n = nx2(n_grass, ua, ub, kb);
				if (ttype == 4) {
					float lf = smoothstep(0.5, 0.7, n2 * 0.7 + n3 * 0.3);
					if (lf > 0.001) {
						base_c = mix(base_c, texture(t_leaf, ua * 0.8).rgb * (a_grass / a_leaf), lf);
						base_n = mix(base_n, texture(n_leaf, ua * 0.8).rgb, lf);
					}
				}
			}
			det = base_c / max(base_a, vec3(0.03));
			tn = base_n;
		}
		// macro: la stessa foto letta a 40-180 m dà chiazze naturali visibili anche dall'alto
		vec3 mac;
		if (ttype == 1) { mac = texture(t_sand, p / 61.0 + 0.2).rgb / a_sand; }
		else if (ttype == 5) { mac = texture(t_snow, p / 61.0 + 0.2).rgb / a_snow; }
		else { mac = texture(t_grass, p / 47.0 + 0.2).rgb / a_grass; }
		vec3 mac2 = texture(t_dirt, vec2(p.x * 0.6 - p.y * 0.8, p.x * 0.8 + p.y * 0.6) / 173.0 + 0.5).rgb / a_dirt;
		// terra (campi arati, strade, sponde, ghiaioni)
		float wd = clamp(w_dirt, 0.0, 1.0) * float(ttype != 1 && ttype != 5) * float(near_px);
		if (wd > 0.01) {
			vec3 dc = tx2(t_dirt, ua * 1.15, ub, kb);
			det = mix(det, dc / max(a_dirt, vec3(0.03)), wd);
			tn = mix(tn, nx2(n_dirt, ua * 1.15, ub, kb), wd);
		}
		// sabbia delle spiagge
		if (w_beach > 0.01 && ttype != 1 && near_px) {
			det = mix(det, texture(t_sand, ua).rgb / max(a_sand, vec3(0.03)), w_beach);
			tn = mix(tn, texture(n_sand, ua).rgb, w_beach);
		}
		// roccia sui pendii: proiezione dai tre assi (niente stiramento sulle pareti)
		if (rk > 0.01 && near_px) {
			vec3 bw = pow(abs(nrm), vec3(4.0));
			bw /= (bw.x + bw.y + bw.z);
			vec3 rc = texture(t_rock, wpos.zy / 6.0).rgb * bw.x + texture(t_rock, wpos.xz / 6.0).rgb * bw.y + texture(t_rock, wpos.xy / 6.0).rgb * bw.z;
			det = mix(det, rc / max(a_rock, vec3(0.03)), rk);
			tn = mix(tn, texture(n_rock, wpos.xz / 6.0).rgb, rk * bw.y);
		}
		// neve in quota
		if (sn > 0.01 && ttype != 5 && near_px) {
			det = mix(det, texture(t_snow, ua).rgb / max(a_snow, vec3(0.03)), sn);
			tn = mix(tn, texture(n_snow, ua).rgb, sn);
		}
		// il dettaglio della texture resta forte da vicino e si attenua con la distanza (i mipmap lo mediano già)
		float dk = tex_on * mix(0.75, 1.0, fine) * (1.0 - canopy * 0.8) * (1.0 - far_k);
		det = 1.0 + (det - 1.0) * 1.7;   // più contrasto: la foto è morbida, dal punto di vista RTS si perdeva
		// tinta verso quella reale della foto (verdi oliva, sabbia beige): via i colori "da cartone" della vecchia palette
		float lc = dot(col, vec3(0.3, 0.55, 0.15));
		vec3 ph = base_a / max(dot(base_a, vec3(0.3, 0.55, 0.15)), 0.02);
		float pull = (ttype == 1 ? 0.55 : 0.3) * (1.0 - clamp(w_dirt, 0.0, 1.0) * 0.6) * (1.0 - rk) * tex_on * (1.0 - canopy);
		col = mix(col, lc * ph, pull);
		col *= mix(vec3(1.0), clamp(det, vec3(0.2), vec3(2.6)), dk);
		// le macro-chiazze sono proiettate dall'alto: sui versanti ripidi si stirerebbero in strisce
		float mac_k = tex_on * (1.0 - canopy) * (1.0 - smoothstep(0.25, 0.55, slope));
		col *= mix(vec3(1.0), clamp(1.0 + (mac - 1.0) * 1.4, vec3(0.5), vec3(1.6)), 0.6 * mac_k);
		col *= mix(vec3(1.0), clamp(1.0 + (mac2 - 1.0) * 1.2, vec3(0.6), vec3(1.5)), 0.4 * mac_k);
		tex_n = mix(vec3(0.5, 0.5, 1.0), tn, tex_on);
	}
	// saturazione finale: naturale (le texture portano già la varietà di colore)
	float lum0 = dot(col, vec3(0.3, 0.55, 0.15));
	col = max(mix(vec3(lum0), col, sat_k), vec3(0.0));
	vec2 suv = (p - field_rect.xy) / field_rect.zw;
	float ins = step(0.0, suv.x) * step(suv.x, 1.0) * step(0.0, suv.y) * step(suv.y, 1.0);
	// neve che si accumula (Fase 8): copre tutto salvo i pendii ripidi, le strade battute e l'acqua
	if (snow_cover > 0.001) {
		float sc_n = snow_cover * (1.0 - smoothstep(0.3, 0.55, slope)) * (1.0 - road * 0.45) * (1.0 - smoothstep(0.3, 0.8, wet));
		sc_n *= smoothstep(0.0, 0.5, snow_cover + (n3 - 0.5) * 0.5);
		col = mix(col, c_snow * (0.9 + 0.1 * n4), clamp(sc_n, 0.0, 1.0));
	}
	// occlusione d'ambiente cotta (valli e fossi), creste leggermente più chiare — anche sulla neve (il rilievo deve leggersi)
	col *= mix(mix(0.62, 0.5, clamp(relief_k - 1.0, 0.0, 1.0)), 1.0, ao) * (1.0 + ridge * 0.22 * float(ttype != 5));
	// ombreggiatura del rilievo sempre attiva: i versanti si leggono anche con luce diffusa (Fase 8: più marcata)
	float hs0 = clamp(dot(nrm, normalize(vec3(-0.55, 0.7, -0.45))), 0.0, 1.0);
	float hsk = ((ttype == 1 || ttype == 5 || snow_cover > 0.5) ? 1.6 : 1.0) * relief_k;   // sabbia e neve: colori chiari, serve più contrasto
	col *= mix(1.0 - 0.3 * hsk, 1.0 + 0.14 * hsk, hs0);
	// solchi dei mezzi: terra smossa più scura (r), fango/neve pressata (g)
	float trk = 0.0; float trk_g = 0.0;
	if (track_on > 0.5) {
		vec2 tk = texture(track_tex, suv).rg * ins;
		trk = tk.r; trk_g = tk.g;
		vec3 rut = (ttype == 5 || snow_cover > 0.4) ? c_dirt * 0.78 : c_dirt * 0.7;
		col = mix(col, rut * (0.85 + 0.3 * n4 * fine), smoothstep(0.06, 0.6, trk) * 0.62);
		col = mix(col, c_dirt * 0.4, smoothstep(0.2, 0.9, trk_g) * 0.65);
	}
	float sc = texture(scorch_tex, suv).r * ins;
	float rim = smoothstep(0.05, 0.3, sc) * (1.0 - smoothstep(0.3, 0.6, sc));
	col = mix(col, c_dirt * 0.75, rim * 0.6);
	col = mix(col, vec3(0.05, 0.045, 0.04) * (0.8 + 0.4 * n4), smoothstep(0.35, 0.9, sc) * 0.9);
	// pioggia (Fase 8): suolo scuro e lucido, pozzanghere nelle conche pianeggianti e nei solchi
	float puddle = 0.0;
	if (wetness > 0.001) {
		float flat_k = 1.0 - smoothstep(0.02, 0.09, slope);
		puddle = smoothstep(0.52, 0.72, n2 * 0.6 + (1.0 - ao) * 0.5 + trk_g * 0.4 + n3 * 0.15) * flat_k * smoothstep(0.25, 1.0, wetness);
		puddle *= (1.0 - ice) * (1.0 - snow_cover);
		col *= mix(1.0, 0.66, wetness * (1.0 - snow_cover));
		col = mix(col, col * vec3(0.55, 0.6, 0.68), puddle * 0.8);
	}
	// vista d'insieme: ombreggiatura del rilievo, AO più marcata, curve di livello ogni 5 m (più marcate ogni 25 m)
	float ov = overview * smoothstep(150.0, 450.0, dist) * 0.35;   // carta tattica appena accennata: il terreno resta fotografico
	if (ov > 0.001) {
		float hs = clamp(dot(nrm, normalize(vec3(-0.5, 0.62, -0.6))), 0.0, 1.0);
		col *= mix(1.0, 0.5 + 0.7 * hs, ov * 0.6);
		col *= mix(1.0, mix(0.72, 1.0, ao), ov * 0.6);
		float ci = wpos.y / 5.0;
		float fwc = max(fwidth(ci), 1e-4);
		float dc = min(fract(ci), 1.0 - fract(ci)) / fwc;
		float major = 1.0 - step(0.1, abs(fract(floor(ci + 0.5) / 5.0 + 0.1) - 0.1));
		float cl = (1.0 - smoothstep(0.4, 1.3, dc)) * (1.0 - smoothstep(0.3, 0.6, fwc));
		col = mix(col, col * 0.55, cl * ov * (0.25 + 0.25 * major) * (1.0 - wet_s) * float(ttype != 2) * (1.0 - far_on));
		col = mix(col, c_dirt * 1.35, road * ov * 0.4);
	}
	vec3 emis = vec3(0.0);
	if (fog_on > 0.5) {
		float fv = texture(fog_tex, clamp(suv, vec2(0.002), vec2(0.998))).r;
		float lum = dot(col, vec3(0.3, 0.55, 0.15));
		col = mix(mix(col, vec3(lum), 0.1) * vec3(0.86, 0.85, 0.82), col, smoothstep(0.62, 0.95, fv));
	}
	if (front_k > 0.001) {
		// plancia: terreno un po' desaturato e caldo, come una carta stampata
		float lumf = dot(col, vec3(0.3, 0.55, 0.15));
		col = mix(col, vec3(lumf) * vec3(1.06, 1.0, 0.86) + vec3(0.03, 0.025, 0.0), 0.12 * front_k);
		if (ins > 0.5) {
			// influenza sfumata (9 campioni su una griglia grossa) e linea del fronte tratteggiata in movimento
			vec2 tx = vec2(1.0 / 48.0, 1.0 / 27.0) * 0.9;
			vec2 inf = texture(front_tex, suv).rg * 0.2;
			inf += texture(front_tex, suv + vec2(tx.x, tx.y)).rg * 0.2;
			inf += texture(front_tex, suv + vec2(-tx.x, tx.y)).rg * 0.2;
			inf += texture(front_tex, suv + vec2(tx.x, -tx.y)).rg * 0.2;
			inf += texture(front_tex, suv + vec2(-tx.x, -tx.y)).rg * 0.2;
			float tot = inf.r + inf.g;
			float pres = smoothstep(0.004, 0.05, tot);
			float sgn = (inf.r - inf.g) / (tot + 0.004);
			vec3 tint = sgn > 0.0 ? front_col_a : front_col_d;
			col = mix(col, mix(col, tint, 0.42), pres * smoothstep(0.15, 0.6, abs(sgn)) * front_k);
			float fw = max(fwidth(sgn), 1e-4);
			float both = smoothstep(0.004, 0.03, min(inf.r, inf.g));
			float line = (1.0 - smoothstep(1.2, 2.6, abs(sgn) / fw)) * both;
			float dash = step(0.42, fract((p.x - p.y) / 18.0 - TIME * 0.35));
			vec3 lc = vec3(1.0, 0.86, 0.45);
			col = mix(col, lc, line * mix(0.45, 1.0, dash) * front_k);
			emis += lc * line * dash * 0.5 * front_k;
		}
	}
	if (ring_n > 0) {
		float d0 = 1e6; float d1 = 1e6; float d2 = 1e6;
		for (int i = 0; i < ring_n; i++) {
			vec4 r = rings[i];
			float d = length(p - r.xy) - r.z;
			if (r.w < 0.5) { d0 = min(d0, d); } else if (r.w < 1.5) { d1 = min(d1, d); } else { d2 = min(d2, abs(d)); }
		}
		float lw = 0.35 + dist * 0.0022;
		float l0 = 1.0 - smoothstep(lw * 0.5, lw, abs(d0));
		float dash = step(0.45, fract((p.x + p.y) / (5.0 + dist * 0.03)));
		float l1 = (1.0 - smoothstep(lw * 0.4, lw * 0.8, abs(d1))) * dash;
		float l2 = (1.0 - smoothstep(lw * 0.5, lw, abs(d2))) * (0.4 + 0.6 * dash);
		float inside = step(d0, 0.0) * 0.07;
		col = mix(col, ring_col, inside);
		col = mix(col, ring_col, l0 * 0.85);
		col = mix(col, vec3(0.75, 0.88, 1.0), l1 * 0.7);
		col = mix(col, vec3(1.0, 0.32, 0.25), l2 * 0.85);
		emis += ring_col * l0 * 0.35 + vec3(0.6, 0.75, 0.9) * l1 * 0.25 + vec3(0.8, 0.2, 0.15) * l2 * 0.3;
	}
	if (cloud_k > 0.001) {
		// ombre delle nuvole (stessa forma dello strato di nuvole, che evita il campo di battaglia)
		float cn = texture(noise_tex, p / 1500.0 + vec2(TIME * 0.0016, TIME * 0.0007)).r * 0.7 + texture(noise_tex, p / 520.0 + vec2(TIME * 0.0021, 0.3)).r * 0.3;
		float cs = smoothstep(0.56, 0.68, cn) * smoothstep(350.0, 1100.0, far_d) * cloud_k;
		col *= 1.0 - 0.38 * cs;
	}
	// foschia d'orizzonte: le montagne lontane sfumano nel colore del cielo (profondità, niente bordo del mondo)
	float hz = smoothstep(4500.0, 12000.0, dist) * far_on;
	col = mix(col, horizon_col * 0.62, hz * 0.7);
	ALBEDO = col;
	EMISSION = emis + horizon_col * 0.35 * hz * hz;
	AO = mix(1.0, ao, 0.7);
	AO_LIGHT_AFFECT = 0.2;
	float wet_k = wetness * (1.0 - snow_cover);
	ROUGHNESS = clamp(0.93 - sn * 0.35 - wet_s * 0.6 - wet * river_wet * 0.25 - ice * 0.55 - (1.0 - n3) * 0.06 - (ttype == 2 ? m.r * 0.08 : 0.0)
		- wet_k * 0.45 - puddle * 0.4 - snow_cover * 0.15, 0.05, 1.0);
	SPECULAR = 0.35 + ice * 0.2 + puddle * 0.3 + wet_k * 0.15;
	if (near_px) {
		vec3 nA = texture(noise_nrm, p / 3.1).rgb;
		vec3 nB = fine > 0.001 ? texture(noise_nrm, p / 0.9 + 0.5).rgb : nA;
		NORMAL_MAP = normalize(mix(mix(nA, nB, 0.35 * fine + 0.3 * tuft), tex_n, tex_on));
		NORMAL_MAP_DEPTH = (mix(0.65 * fine + 0.6 * tuft, 1.0, tex_on) + rk * 0.8 + 0.8 * pebble) * (1.0 - ice * 0.7) * (1.0 - puddle) * (1.0 - snow_cover * 0.6) * (1.0 - far_k);
	}
}
