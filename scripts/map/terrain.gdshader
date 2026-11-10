// Tabellone: rilievo del mondo. Spostamento dei vertici dalla heightmap, colore naturale per tipo di terreno
// (con dettaglio che cresce avvicinandosi: campi coltivati, boschi, roccia), tinta del proprietario che si
// intensifica allontanandosi (lettura "politica" della vista d'insieme), confini nitidi a larghezza costante sullo schermo,
// fronti tra proprietari, continenti posseduti, evidenziazioni animate (selezione / passaggio / bersagli / marcature).
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D tid_tex : filter_nearest, repeat_disable;      // R8: id territorio + 1 (0 = mare)
uniform sampler2D field_tex : filter_linear, repeat_disable;     // r: dist. confine, g: dist. confine continente, b: dist. costa, a: vicino
uniform sampler2D ter1_tex : filter_linear, repeat_disable;      // pesi: montagna, deserto, artico, foresta
uniform sampler2D ter2_tex : filter_linear, repeat_disable;      // pesi: urbano, pianura
uniform sampler2D owner_tex : source_color, filter_nearest, repeat_disable; // 64×1: rgb colore proprietario
uniform sampler2D state_tex : filter_nearest, repeat_disable;    // 64×1: r sel, g hover, b bersaglio (0.5 proprio / 1 nemico), a marcato
uniform sampler2D cont_tex : source_color, filter_nearest, repeat_disable;  // 64×1: rgb colore del padrone del continente, a = posseduto
uniform sampler2D vis_tex : filter_nearest, repeat_disable;    // 64×1: r nebbia, g proprietario+1, b maschera partner di patto
uniform sampler2D front_tex : filter_nearest, repeat_disable;  // 64×1: r calore del fronte (confini contesi, attacchi recenti)
uniform vec2 tex_size = vec2(800.0, 450.0);
uniform vec2 world_size = vec2(160.0, 90.0);
uniform vec4 mark_color : source_color = vec4(0.45, 1.0, 0.6, 1.0);
uniform float tint = 0.40;
uniform float zoom = 0.5;          // 0 vicino .. 1 lontano
uniform float detail = 1.0;        // qualità: dettaglio procedurale
uniform float border_glow = 1.0;
uniform float city_lights = 2.0;   // 0 nessuna, 1 solo bagliore (qualità bassa), 2 puntini e bagliore
uniform float objective_glow = 0.0;

#include "res://scripts/map/daynight.gdshaderinc"

varying vec3 wpos;
varying vec2 muv;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { return vnoise(p) * 0.55 + vnoise(p * 2.07) * 0.28 + vnoise(p * 4.13) * 0.17; }
// rumore con interpolazione quintica (derivata continua): micro-rilievo senza pieghe lungo la griglia
float vnoise5(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm5(vec2 p) { return vnoise5(p) * 0.55 + vnoise5(p * 2.07 + vec2(5.2, 1.3)) * 0.28 + vnoise5(p * 4.13 + vec2(1.7, 9.2)) * 0.17; }

float hgt(vec2 uv) { return texture(height_tex, uv).r; }

// B-spline bicubica con 4 letture bilineari: linea di costa e spiagge continue anche da vicinissimo
vec4 bspline_w(float v) {
	vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
	vec4 s = n * n * n;
	float x = s.x;
	float y = s.y - 4.0 * s.x;
	float z = s.z - 4.0 * s.y + 6.0 * s.x;
	return vec4(x, y, z, 6.0 - x - y - z) * (1.0 / 6.0);
}
float hgt_smooth(vec2 uv) {
	vec2 c = uv * tex_size - 0.5;
	vec2 f = fract(c);
	c -= f;
	vec4 xc = bspline_w(f.x);
	vec4 yc = bspline_w(f.y);
	vec4 cc = c.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 s = vec4(xc.xz + xc.yw, yc.xz + yc.yw);
	vec4 off = (cc + vec4(xc.yw, yc.yw) / s) / tex_size.xxyy;
	float s0 = texture(height_tex, off.xz).r;
	float s1 = texture(height_tex, off.yz).r;
	float s2 = texture(height_tex, off.xw).r;
	float s3 = texture(height_tex, off.yw).r;
	float sx = s.x / (s.x + s.y);
	float sy = s.z / (s.z + s.w);
	return mix(mix(s3, s2, sx), mix(s1, s0, sx), sy);
}

// luci urbane: un puntino caldo per cella (presenza secondo la densità), raggio con un minimo in pixel
float city_dots(vec2 p, float cell, float dens, float pix) {
	if (pix > cell * 0.45) return 0.0;
	vec2 g = p / cell;
	vec2 id = floor(g);
	vec2 f = fract(g);
	float h = hash(id);
	if (h > dens) return 0.0;
	vec2 c = vec2(hash(id + 17.31), hash(id + 41.73)) * 0.64 + 0.18;
	float d = length(f - c) * cell;
	float r0 = cell * 0.09;
	float r = max(r0, pix * 0.9);
	float e = clamp(r0 / r, 0.4, 1.0);
	float fade = 1.0 - smoothstep(cell * 0.25, cell * 0.45, pix);
	return (1.0 - smoothstep(r * 0.25, r, d)) * e * fade * (0.55 + 0.9 * hash(id + 3.17));
}

void vertex() {
	vec2 uv = (VERTEX.xz + world_size * 0.5) / world_size;
	float h = hgt(uv);
	// la piattaforma costiera resta appena sopra il mare: il contorno vero lo ritaglia il frammento (hgt_smooth < 0)
	float y = h > -0.22 ? max(h, 0.012) : h;
	VERTEX.y = max(y, -0.35);
	vec2 e = 1.0 / tex_size;
	float cell = world_size.x / tex_size.x;
	float hl = hgt(uv - vec2(e.x, 0.0)), hr = hgt(uv + vec2(e.x, 0.0));
	float hu = hgt(uv - vec2(0.0, e.y)), hd = hgt(uv + vec2(0.0, e.y));
	NORMAL = normalize(vec3(hl - hr, 2.0 * cell, hu - hd));
	muv = uv;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// linea nitida a larghezza costante in pixel attorno a d = 0 (d in qualsiasi unità, fw = fwidth(d))
float px_line(float d, float fw, float px) {
	return 1.0 - smoothstep(px * fw, (px + 1.2) * fw, d);
}

void fragment() {
	vec2 uv = muv;
	vec2 e = 1.0 / tex_size;
	float cell = world_size.x / tex_size.x;
	float h = hgt(uv);
	float hl = hgt(uv - vec2(e.x, 0.0)), hr = hgt(uv + vec2(e.x, 0.0));
	float hu = hgt(uv - vec2(0.0, e.y)), hd = hgt(uv + vec2(0.0, e.y));
	// costa: contorno a livello del mare della superficie bicubica (niente scalini della maglia o dei texel)
	float hs = hgt_smooth(uv);
	if (hs < 0.0) discard;
	float gradlen = max(length(vec2(hr - hl, hd - hu)) / (2.0 * cell), 0.02);
	float sdw = hs / gradlen;   // distanza approssimata dalla costa, unità mondo
	vec3 n = normalize(vec3(hl - hr, 2.0 * cell, hu - hd));
	float near_k = (1.0 - smoothstep(0.08, 0.42, zoom)) * detail;   // dettaglio ravvicinato
	// micro-rilievo procedurale
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	vec2 mp = rot * wpos.xz * 2.3;
	float dn = fbm5(mp);
	vec2 g = vec2(fbm5(mp + vec2(0.12, 0.0)) - dn, fbm5(mp + vec2(0.0, 0.12)) - dn);
	n = normalize(n - vec3(g.x, 0.0, g.y) * (0.25 + 0.25 * near_k));
	float slope = 1.0 - n.y;

	vec4 t1 = texture(ter1_tex, uv);
	vec4 t2 = texture(ter2_tex, uv);
	float w_mtn = t1.r, w_des = t1.g, w_arc = t1.b, w_for = t1.a, w_urb = t2.r, w_pia = t2.g;
	float big = fbm5(rot * wpos.xz * 0.35);
	float fine = fbm(rot * wpos.xz * 5.0 + 3.7);

	// pianura: mosaico di campi coltivati (visibile da vicino)
	vec2 fp2 = rot * wpos.xz * 2.2 + vec2(big * 1.5, 0.0);
	vec2 fid = floor(fp2);
	float fh = hash(fid);
	vec2 ff = fract(fp2);
	float hedge = smoothstep(0.0, 0.06, min(min(ff.x, 1.0 - ff.x), min(ff.y, 1.0 - ff.y)));
	vec3 field = mix(vec3(0.38, 0.44, 0.20), vec3(0.58, 0.54, 0.30), fh);
	field = mix(field, vec3(0.30, 0.38, 0.17), step(0.72, fh));
	vec3 c_pia = mix(vec3(0.36, 0.42, 0.20), vec3(0.48, 0.49, 0.27), big);
	c_pia = mix(c_pia, field * mix(0.86, 1.0, hedge), near_k * 0.45 * smoothstep(0.35, 0.6, vnoise(wpos.xz * 0.6)) * (0.25 + 0.75 * dn_day(wpos)));
	vec3 c_for = mix(vec3(0.10, 0.20, 0.08), vec3(0.18, 0.28, 0.12), fine);
	c_for *= 0.75 + 0.5 * vnoise(wpos.xz * (14.0 + 30.0 * near_k));
	vec3 c_des = mix(vec3(0.70, 0.56, 0.34), vec3(0.82, 0.70, 0.47), big * 0.6 + fine * 0.4);
	// dune
	// (fase delle dune deformata da due rumori a orientamenti diversi: niente reticolo visibile del value noise)
	float dwarp = fbm5(mat2(vec2(0.36, 0.93), vec2(-0.93, 0.36)) * wpos.xz * 0.23 + vec2(7.0, 2.0)) * 3.2 + fbm5(rot * wpos.xz * 0.17 + vec2(1.0, 9.0)) * 3.2;
	c_des *= 0.9 + 0.12 * sin(dot(wpos.xz, vec2(3.1, 1.3)) + dwarp) * near_k;
	vec3 c_mtn = mix(vec3(0.33, 0.30, 0.24), vec3(0.48, 0.43, 0.35), fine);
	vec3 c_arc = mix(vec3(0.78, 0.84, 0.90), vec3(0.93, 0.95, 0.98), fine);
	// città: isolati e strade
	vec2 bp = wpos.xz * 6.0;
	float blk = hash(floor(bp));
	vec2 bf = fract(bp);
	float street = smoothstep(0.0, 0.12, min(min(bf.x, 1.0 - bf.x), min(bf.y, 1.0 - bf.y)));
	vec3 c_urb = mix(vec3(0.40, 0.40, 0.37), vec3(0.62, 0.60, 0.55), blk) * mix(1.0, mix(0.55, 1.0, street), near_k);
	float urb_mask = smoothstep(0.55, 0.75, vnoise(wpos.xz * 0.9) * 0.7 + vnoise(wpos.xz * 3.1) * 0.3);
	c_urb = mix(mix(c_pia, c_for, 0.3), mix(vec3(0.47, 0.47, 0.44), c_urb, 0.25 + 0.75 * near_k), urb_mask * (0.4 + 0.6 * mix(0.6, step(0.35, blk), near_k)));

	vec3 nat = c_pia * w_pia + c_for * w_for + c_des * w_des + c_mtn * w_mtn + c_arc * w_arc + c_urb * w_urb;
	float wsum = w_pia + w_for + w_des + w_mtn + w_arc + w_urb;
	nat /= max(wsum, 0.001);
	// roccia sui pendii, neve in quota
	vec3 rock = mix(vec3(0.30, 0.28, 0.25), vec3(0.42, 0.39, 0.35), fine);
	nat = mix(nat, rock, smoothstep(0.18, 0.45, slope) * (1.0 - w_arc * 0.7));
	float snow_line = mix(0.95, 0.35, w_arc);
	float snow = smoothstep(snow_line, snow_line + 0.25, h + (fine - 0.5) * 0.35 + (vnoise(wpos.xz * 9.0) - 0.5) * 0.08 + (big - 0.5) * 0.2) * (1.0 - smoothstep(0.30, 0.6, slope) * 0.7);
	nat = mix(nat, vec3(0.90, 0.92, 0.95), snow);
	// spiagge
	vec4 fld = texture(field_tex, uv);
	float coastd = fld.b * 255.0 / 2.0;  // celle dalla costa
	float pixw = length(fwidth(wpos.xz));
	float beach = (1.0 - smoothstep(0.05 + pixw, 0.16 + 1.5 * pixw, sdw + (fine - 0.5) * 0.06)) * (1.0 - w_arc);
	nat = mix(nat, vec3(0.74, 0.68, 0.52), beach * 0.55);
	// battigia: sabbia bagnata più scura sull'ultimo tratto
	nat = mix(nat, vec3(0.42, 0.40, 0.33), (1.0 - smoothstep(0.0, 0.025 + pixw * 1.2, sdw)) * 0.55 * (1.0 - w_arc * 0.7));
	// occlusione finta nelle valli
	nat *= 0.86 + 0.28 * smoothstep(-0.05, 0.6, h) * (1.0 - slope * 0.5);
	// rilievo da carta topografica: ombreggiatura fissa da nord-ovest (leggibile anche quando il sole è alto o di notte)
	// e isoipse sottili a quota costante, che svaniscono nella vista d'insieme e sotto la neve
	vec3 n0 = normalize(vec3(hl - hr, 2.0 * cell, hu - hd));
	float hsd = clamp(dot(n0, vec3(-0.55, 0.70, -0.45)), 0.0, 1.0);
	nat *= mix(1.0, 0.70 + 0.5 * hsd, 0.30 + 0.30 * zoom);
	float hc = h * 6.0;
	float fwh = max(fwidth(hc), 1e-4);
	float iso = 1.0 - smoothstep(0.5 * fwh, 1.5 * fwh, abs(fract(hc - 0.5) - 0.5));
	iso *= smoothstep(0.04, 0.1, h) * (1.0 - smoothstep(0.5, 0.85, zoom)) * (1.0 - 0.6 * snow) * (1.0 - smoothstep(0.15, 0.35, fwh));
	nat = mix(nat, nat * vec3(0.66, 0.62, 0.56), iso * 0.24 * detail);

	// --- proprietario (colori naturali definiti in sRGB -> lineare)
	nat = pow(nat, vec3(2.2));
	ivec2 tsz = ivec2(tex_size) - 1;
	vec2 fp = uv * tex_size - 0.5;
	ivec2 b0 = ivec2(floor(fp));
	vec2 fr = fp - floor(fp);
	vec4 ocw = vec4(0.0);
	vec4 st = vec4(0.0);
	vec4 ct = vec4(0.0);
	vec3 onb = vec3(0.0);
	float frontier = 0.0;
	float fogw = 0.0;
	float pactw = 0.0;
	float bldw = 0.0;
	float fheat = 0.0;
	int k_own[4];
	int k_mask[4];
	for (int k = 0; k < 4; k++) {
		ivec2 o = ivec2(k & 1, k >> 1);
		float w = (o.x == 1 ? fr.x : 1.0 - fr.x) * (o.y == 1 ? fr.y : 1.0 - fr.y);
		ivec2 c = clamp(b0 + o, ivec2(0), tsz);
		int id = int(texelFetch(tid_tex, c, 0).r * 255.0 + 0.5) - 1;
		k_own[k] = -1;
		k_mask[k] = 0;
		vec4 ow = vec4(0.5, 0.5, 0.5, 0.0);
		vec4 s4 = vec4(0.0);
		vec4 c4 = vec4(0.0);
		vec3 nb = ow.rgb;
		float fr1 = 0.0;
		if (id >= 0) {
			ow = texelFetch(owner_tex, ivec2(id, 0), 0);
			s4 = texelFetch(state_tex, ivec2(id, 0), 0);
			c4 = texelFetch(cont_tex, ivec2(id, 0), 0);
			nb = ow.rgb;
			int nid = int(texelFetch(field_tex, c, 0).a * 255.0 + 0.5) - 1;
			vec4 v4 = texelFetch(vis_tex, ivec2(id, 0), 0);
			fogw += v4.r * w;
			bldw += v4.a * w;
			k_own[k] = int(v4.g * 255.0 + 0.5) - 1;
			k_mask[k] = int(v4.b * 255.0 + 0.5);
			if (nid >= 0) {
				nb = texelFetch(owner_tex, ivec2(nid, 0), 0).rgb;
				fr1 = distance(nb, ow.rgb) > 0.01 ? 1.0 : 0.0;
				fheat += max(texelFetch(front_tex, ivec2(id, 0), 0).r, texelFetch(front_tex, ivec2(nid, 0), 0).r) * w * fr1;
				// patto di non aggressione tra i due proprietari del confine
				int on = int(texelFetch(vis_tex, ivec2(nid, 0), 0).g * 255.0 + 0.5) - 1;
				int mask = int(v4.b * 255.0 + 0.5);
				if (on >= 0 && fr1 > 0.5 && ((mask >> on) & 1) == 1) {
					pactw += w;
				}
			}
		}
		ocw += ow * w;
		st += s4 * w;
		ct += c4 * w;
		onb += nb * w;
		frontier += fr1 * w;
	}
	vec3 oc = ocw.rgb;
	float owned = ocw.a;
	float lum = dot(nat, vec3(0.3, 0.59, 0.11));
	float bd = fld.r * 255.0 / 16.0;   // celle dal confine
	float cd = fld.g * 255.0 / 16.0;
	float fwb = max(fwidth(bd), 0.002);
	float fwc = max(fwidth(coastd), 0.002);
	float fwd = max(fwidth(cd), 0.002);
	// tinta del proprietario: discreta da vicino, piena nella vista d'insieme
	vec3 pol = oc * (0.16 + lum * 1.25);
	vec3 alb = mix(nat, pol, tint * owned);
	// fascia interna lungo il fronte (colore pieno del proprietario), larghezza mista schermo/mondo
	float bandw = max(mix(7.0, 11.0, zoom) * fwb, 0.9);
	// a cavallo del confine i 4 campioni appartengono a territori diversi: patto diretto tra i loro proprietari
	float pact_edge = 0.0;
	for (int a = 0; a < 4; a++) {
		for (int b = a + 1; b < 4; b++) {
			if (k_own[a] >= 0 && k_own[b] >= 0 && k_own[a] != k_own[b] && ((k_mask[a] >> k_own[b]) & 1) == 1) {
				pact_edge = 1.0;
			}
		}
	}
	float pactf = max(clamp(pactw, 0.0, 1.0), pact_edge);
	float allf = frontier;
	frontier = max(frontier - pactf, 0.0);   // i confini con un partner di patto non sono fronti
	float band = (1.0 - smoothstep(0.0, bandw, bd)) * frontier * owned;
	alb = mix(alb, oc * (0.30 + lum * 0.9), band * 0.7);
	// confini nitidi: fronte = filo chiaro + bordo colorato, interni = filo sottile
	float core = px_line(bd, fwb, mix(0.9, 1.2, zoom));
	float edge_c = px_line(bd, fwb, mix(2.8, 3.6, zoom));
	vec3 lc = mix(oc, vec3(1.0), 0.55);
	vec3 emis = vec3(0.0);
	alb = mix(alb, oc * 0.9 + 0.05, edge_c * frontier * 0.85);
	alb = mix(alb, lc, core * frontier);
	emis += oc * (edge_c * 0.35 + band * 0.08) * frontier * border_glow;
	emis += lc * core * frontier * 0.25 * border_glow;
	float inner = px_line(bd, fwb, 0.45) * (1.0 - allf);
	// fronte attivo (confine conteso, attacchi recenti, truppe ammassate): filo che pulsa con scintille che scorrono
	// lungo la linea, bagliore caldo e terra bruciata ai lati
	if (fheat > 0.01) {
		float fh = clamp(fheat, 0.0, 1.0) * frontier;
		// larghezza in pixel con un minimo in celle (da vicino il campo di distanza non scende sotto ~mezza cella)
		float flw = max(mix(2.4, 3.2, zoom) * fwb, 0.6);
		float fl = 1.0 - smoothstep(flw, flw + max(1.2 * fwb, 0.18), bd);
		float run = fract((wpos.x * 0.9 - wpos.z * 0.7) * mix(1.4, 0.6, zoom) - TIME * 0.7);
		float dash = smoothstep(0.3, 0.5, run) * (1.0 - smoothstep(0.5, 0.7, run));
		float flick = 0.6 + 0.4 * sin(TIME * 9.0 + wpos.x * 13.0 + wpos.z * 7.0);
		vec3 fcol = mix(vec3(1.0, 0.35, 0.1), vec3(1.0, 0.82, 0.45), flick);
		float glow = 1.0 - smoothstep(0.0, max(12.0 * fwb, 2.4), bd);
		alb = mix(alb, vec3(0.10, 0.07, 0.05), glow * fh * 0.55);
		alb = mix(alb, fcol * 0.8, fl * fh * 0.5);
		emis += fcol * (fl * (0.25 + 0.75 * dash) * (0.9 + 1.6 * zoom) + glow * (0.12 + 0.3 * zoom) * flick) * fh;
	}
	// confine di patto: filo azzurro-bianco tratteggiato con alone tenue
	float pdash = step(0.35, fract((wpos.x * 0.7 - wpos.z * 0.7) * (0.75 / (0.25 + zoom))));
	// larghezza in pixel con un minimo in celle (da vicino il campo di distanza non scende sotto ~mezza cella)
	float pw0 = max(mix(1.8, 2.2, zoom) * fwb, 0.42);
	float pline = 1.0 - smoothstep(pw0, pw0 + max(1.2 * fwb, 0.12), bd);
	float pw1 = max(mix(3.6, 4.2, zoom) * fwb, 0.75);
	float pedge = 1.0 - smoothstep(pw1, pw1 + max(1.2 * fwb, 0.12), bd);
	float phalo = 1.0 - smoothstep(0.0, max(12.0 * fwb, 2.2), bd);
	vec3 pcol = vec3(0.72, 0.92, 1.0);
	alb = mix(alb, mix(alb, vec3(0.20, 0.42, 0.55), 0.55), phalo * pactf * 0.7);
	alb = mix(alb, vec3(0.02, 0.05, 0.08), pedge * pactf * 0.6);
	alb = mix(alb, pcol, pline * pdash * pactf);
	emis += pcol * (pline * pdash * 0.9 + phalo * 0.10) * pactf;
	alb = mix(alb, mix(alb, vec3(0.9, 0.9, 0.82), 0.5), inner * 0.55);
	// confini tra continenti (filo crema tratteggiato)
	float cline = px_line(cd, fwd, 0.6) * step(0.5, fract((wpos.x + wpos.z) * 1.2));
	alb = mix(alb, vec3(0.85, 0.80, 0.62), cline * 0.35 * (1.0 - frontier));
	// continente posseduto: filo costiero luminoso nel colore del padrone + leggera velatura
	float cown = ct.a;
	float cdist = min(coastd, cd * 1.0);
	float crim = px_line(cdist, max(fwc, fwd), 0.9);
	float cglow = 1.0 - smoothstep(0.0, max(14.0 * max(fwc, fwd), 1.5), cdist);
	emis += ct.rgb * (crim * 0.55 + cglow * 0.12) * cown;
	alb = mix(alb, ct.rgb * (0.2 + lum), cown * 0.06);
	// nebbia di guerra: foschia fredda che desatura (il colore del proprietario resta leggibile) con veli che scorrono
	float fogv = clamp(fogw, 0.0, 1.0);
	if (fogv > 0.001) {
		float fl = dot(alb, vec3(0.3, 0.59, 0.11));
		vec3 desat = mix(vec3(fl), alb, 0.62) * 0.66;
		float wisp = fbm(wpos.xz * 0.45 + vec2(TIME * 0.035, TIME * 0.015));
		wisp = smoothstep(0.3, 0.8, wisp + 0.15 * fbm(wpos.xz * 1.7 - vec2(TIME * 0.05, 0.0)));
		vec3 haze = vec3(0.03, 0.045, 0.065) * (0.5 + 1.1 * wisp);
		// tratteggio diagonale finissimo da carta operativa (solo da vicino)
		float hatch = step(0.86, fract((wpos.x + wpos.z) * 2.2)) * (1.0 - smoothstep(0.1, 0.5, zoom));
		vec3 fogged = desat + haze + vec3(0.025, 0.03, 0.035) * hatch;
		alb = mix(alb, fogged, fogv);
		emis *= 1.0 - 0.55 * fogv;
	}
	// evidenziazioni
	float pulse = 0.5 + 0.5 * sin(TIME * 4.0);
	float edged = min(bd, coastd);
	float fwe = max(fwidth(edged), 0.002);
	// passaggio del cursore
	emis += (oc * 0.08 + vec3(0.035)) * st.g;
	alb *= 1.0 + 0.10 * st.g;
	emis += vec3(0.9, 0.95, 1.0) * px_line(edged, fwe, 1.2) * st.g * 0.35;
	// selezione: contorno a trattini che scorre + alone interno
	float sel = smoothstep(0.35, 0.9, st.r);
	float ants = step(0.5, fract((wpos.x * 0.7 + wpos.z * 0.7) * (1.6 / (0.25 + zoom)) - TIME * 1.4));
	float sline = px_line(edged, fwe, 2.0);
	float shalo = 1.0 - smoothstep(0.0, max(18.0 * fwe, 2.5), edged);
	alb = mix(alb, vec3(1.0, 0.92, 0.6), sline * sel * mix(0.35, 1.0, ants));
	emis += vec3(1.0, 0.85, 0.45) * (sline * mix(0.25, 1.1, ants) + shalo * (0.10 + 0.12 * pulse)) * sel;
	emis += mix(oc, vec3(1.0), 0.5) * 0.05 * sel;
	// bersagli validi
	vec3 tcol = st.b > 0.62 ? vec3(1.0, 0.50, 0.12) : vec3(0.30, 0.80, 1.0);
	float tw = smoothstep(0.05, 0.4, st.b);
	float thalo = 1.0 - smoothstep(0.0, max(12.0 * fwe, 1.5), edged);
	emis += tcol * (px_line(edged, fwe, 1.4) * (0.6 + 0.4 * pulse) + thalo * 0.22 + 0.02) * tw;
	// marcature (bersagli di carte/OPS)
	emis += mark_color.rgb * (px_line(edged, fwe, 1.6) * (0.6 + 0.5 * pulse) + thalo * 0.25 * pulse + 0.05 * pulse) * st.a;
	// ciclo giorno/notte: crepuscolo caldo, lato notturno lunare, luci delle città
	float day = dn_day(wpos);
	float night = 1.0 - day;
	if (daynight > 0.5) {
		float twl = dn_twilight(wpos);
		alb *= mix(vec3(1.0), vec3(1.10, 0.84, 0.66), twl * 0.55);
		alb = mix(alb, alb * vec3(0.075, 0.09, 0.14), night);
		emis += vec3(1.0, 0.45, 0.18) * twl * 0.02 * (1.0 - fogv * 0.5);
		// il colore del proprietario resta leggibile anche di notte
		emis += oc * owned * night * mix(0.012, 0.05, zoom) * tint;
		if (city_lights > 0.5 && night > 0.01) {
			float coastband = 1.0 - smoothstep(0.08, 0.6, sdw);
			float dens = 0.035 * w_pia + 0.02 * w_for + 0.01 * w_des + 0.01 * w_mtn + 0.002 * w_arc + 0.60 * w_urb;
			dens += 0.22 * coastband * (1.0 - w_arc) * (1.0 - 0.6 * w_mtn);
			dens *= 0.55 + 1.2 * clamp(bldw, 0.0, 1.0);
			dens *= (1.0 - snow) * (1.0 - smoothstep(0.22, 0.45, slope));
			float clus = smoothstep(0.40, 0.74, 0.6 * fbm5(rot * wpos.xz * 0.7 + vec2(11.0, 3.0)) + 0.4 * fbm5(mat2(vec2(0.36, 0.93), vec2(-0.93, 0.36)) * wpos.xz * 1.1 + vec2(2.0, 8.0)));
			float cd2 = dens * (0.08 + 2.2 * clus);
			float glow = cd2 * clus * clus;
			float dots = 0.0;
			if (city_lights > 1.5) {
				dots = city_dots(wpos.xz, 0.6, cd2 * 0.8, pixw)
					+ city_dots(wpos.xz + vec2(3.3, 1.1), 0.21, cd2, pixw)
					+ 0.75 * city_dots(wpos.xz + vec2(7.1, 5.9), 0.085, cd2 * 0.9, pixw);
			}
			float lit = (dots * mix(2.2, 1.1, zoom) + glow * mix(0.12, 0.4, zoom)) * smoothstep(0.0, 0.03, sdw);
			emis += vec3(1.0, 0.56, 0.22) * lit * night * (1.0 - 0.55 * fogv);
		}
	}
	ALBEDO = alb;
	ROUGHNESS = mix(0.92, 0.55, snow) - w_urb * 0.1;
	SPECULAR = (0.25 + snow * 0.3) * (1.0 - 0.75 * night);
	EMISSION = emis;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
