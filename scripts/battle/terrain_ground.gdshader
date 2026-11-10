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

void fragment() {
	vec2 p = wpos.xz;
	float n1 = texture(noise_tex, p / 211.0).r;
	float n2 = texture(noise_tex, p / 37.0 + 0.3).r;
	float n3 = texture(noise_tex, p / 7.1 + 0.6).r;
	float n4 = texture(noise_tex, p / 1.37).r;
	float macro2 = texture(noise_tex, p / 1300.0 + 0.71).r;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float fine = 1.0 - smoothstep(60.0, 260.0, dist);
	vec3 nrm = normalize(wnrm);
	float slope = 1.0 - nrm.y;
	float ao = vcol.r;
	float ridge = vcol.g - 0.5;
	float wet = vcol.b;
	float ice = vcol.a;
	vec3 col = mix(c_ground, c_ground2, smoothstep(0.32, 0.68, n1 * 0.55 + n2 * 0.45));
	col *= 0.86 + 0.28 * n3 + (n4 - 0.5) * 0.22 * fine;
	col = mix(col, c_dirt * (0.85 + 0.3 * n3), smoothstep(0.6, 0.82, n2 * 0.6 + n3 * 0.4) * 0.45);
	float macro = texture(noise_tex, p / 520.0 + 0.17).r;
	col *= mix(vec3(0.92, 0.95, 0.88), vec3(1.06, 1.02, 0.94), macro);
	col *= mix(vec3(0.88, 0.92, 0.86), vec3(1.08, 1.04, 0.95), macro2);
	float rk = smoothstep(rock_slope, rock_slope * 2.0 + 0.01, slope + (n3 - 0.5) * 0.06);
	// ghiaione / terra smossa sui pendii medi
	float scree = smoothstep(rock_slope * 0.38, rock_slope * 0.85, slope + (n2 - 0.5) * 0.08) * (1.0 - rk);
	float strata = texture(noise_tex, vec2(p.x * 0.05 + p.y * 0.05, wpos.y * 0.35)).r;
	float dry = smoothstep(0.55, 0.75, texture(noise_tex, p / 90.0 + 0.41).r) * (1.0 - rk);
	col = mix(col, col * vec3(1.18, 1.08, 0.82), dry * 0.35 * float(ttype != 2));
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
			float fw = (1.0 - smoothstep(0.035, 0.1, slope)) * (1.0 - smoothstep(0.0, 0.3, wet)) * fd.a;
			float t = fd.r * 255.0;
			if (t > 0.5) {
				col = mix(col, crop(t, q, fd.g, n3, n4, fine), fw * 0.9);
			}
			vec3 border = fd.b > 0.6 ? c_dirt * (1.0 + 0.2 * n3) : vec3(0.19, 0.26, 0.11) * (0.8 + 0.3 * n3);
			col = mix(col, border, edge * fw * 0.85);
		}
	}
	col = mix(col, c_dirt * (0.8 + 0.3 * n3), scree * (ttype == 5 ? 0.25 : 0.55));
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
	if (has_sea) {
		float b = 1.0 - smoothstep(0.9, 1.7, wpos.y + (n3 - 0.5) * 0.5);
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
		col = mix(col, col * 0.8, shoulder * 0.55);
		vec3 dirt = c_dirt * (0.82 + 0.35 * n4 * fine + 0.12 * n3) * 1.12;
		dirt *= 1.0 - 0.14 * smoothstep(0.8, 0.97, m.r) * fine;
		if (ttype == 5) { dirt = mix(dirt, vec3(0.6, 0.6, 0.6), 0.5); }
		col = mix(col, dirt, road * 0.95);
	}
	// leggera saturazione: i verdi e le terre non devono sembrare pastello
	float lum0 = dot(col, vec3(0.3, 0.55, 0.15));
	col = max(mix(vec3(lum0), col, 1.14), vec3(0.0));
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
		vec3 rut = (ttype == 5 || snow_cover > 0.4) ? c_dirt * 0.75 : c_dirt * 0.58;
		col = mix(col, rut * (0.85 + 0.3 * n4 * fine), smoothstep(0.06, 0.5, trk) * 0.92);
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
	float ov = overview * smoothstep(150.0, 450.0, dist);
	if (ov > 0.001) {
		float hs = clamp(dot(nrm, normalize(vec3(-0.5, 0.62, -0.6))), 0.0, 1.0);
		col *= mix(1.0, 0.5 + 0.7 * hs, ov * 0.6);
		col *= mix(1.0, mix(0.72, 1.0, ao), ov * 0.6);
		float ci = wpos.y / 5.0;
		float fwc = max(fwidth(ci), 1e-4);
		float dc = min(fract(ci), 1.0 - fract(ci)) / fwc;
		float major = 1.0 - step(0.1, abs(fract(floor(ci + 0.5) / 5.0 + 0.1) - 0.1));
		float cl = (1.0 - smoothstep(0.4, 1.3, dc)) * (1.0 - smoothstep(0.3, 0.6, fwc));
		col = mix(col, col * 0.55, cl * ov * (0.25 + 0.25 * major) * (1.0 - wet_s) * float(ttype != 2));
		col = mix(col, c_dirt * 1.35, road * ov * 0.4);
	}
	vec3 emis = vec3(0.0);
	if (fog_on > 0.5) {
		float fv = texture(fog_tex, clamp(suv, vec2(0.002), vec2(0.998))).r;
		float lum = dot(col, vec3(0.3, 0.55, 0.15));
		col = mix(mix(col, vec3(lum), 0.1) * vec3(0.86, 0.85, 0.82), col, smoothstep(0.62, 0.95, fv));
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
		emis = ring_col * l0 * 0.35 + vec3(0.6, 0.75, 0.9) * l1 * 0.25 + vec3(0.8, 0.2, 0.15) * l2 * 0.3;
	}
	ALBEDO = col;
	EMISSION = emis;
	AO = mix(1.0, ao, 0.7);
	AO_LIGHT_AFFECT = 0.2;
	float wet_k = wetness * (1.0 - snow_cover);
	ROUGHNESS = clamp(0.93 - sn * 0.35 - wet_s * 0.6 - wet * river_wet * 0.25 - ice * 0.55 - (1.0 - n3) * 0.06 - (ttype == 2 ? m.r * 0.08 : 0.0)
		- wet_k * 0.45 - puddle * 0.4 - snow_cover * 0.15, 0.05, 1.0);
	SPECULAR = 0.35 + ice * 0.2 + puddle * 0.3 + wet_k * 0.15;
	vec3 nA = texture(noise_nrm, p / 3.1).rgb;
	vec3 nB = texture(noise_nrm, p / 0.9 + 0.5).rgb;
	NORMAL_MAP = normalize(mix(nA, nB, 0.35 * fine));
	NORMAL_MAP_DEPTH = (0.65 * fine + rk * 0.8) * (1.0 - ice * 0.7) * (1.0 - puddle) * (1.0 - snow_cover * 0.6);
}
