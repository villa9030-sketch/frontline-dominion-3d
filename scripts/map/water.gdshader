// Tabellone: oceano. Colore secondo la profondità (piattaforma costiera turchese → abissi blu notte), onde leggere
// con riflesso del sole, schiuma costiera, reticolo da sala operativa sobrio (maglia fine + meridiani principali)
// che si adatta allo zoom, cornice della carta.
shader_type spatial;
render_mode cull_back, specular_schlick_ggx, shadows_disabled;

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D field_tex : filter_linear, repeat_disable;
uniform vec2 world_size = vec2(160.0, 90.0);
uniform vec3 shallow : source_color = vec3(0.10, 0.36, 0.38);
uniform vec3 mid : source_color = vec3(0.035, 0.16, 0.24);
uniform vec3 deep : source_color = vec3(0.012, 0.045, 0.095);
uniform float grid_alpha = 0.05;
uniform float zoom = 0.5;   // 0 vicino .. 1 lontano
uniform vec2 tex_size = vec2(800.0, 450.0);

#include "res://scripts/map/daynight.gdshaderinc"

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float waves(vec2 p, float t) {
	float h = 0.0;
	h += vnoise(p * 0.9 + vec2(t * 0.25, t * 0.12)) * 0.5;
	h += vnoise(p * 2.3 - vec2(t * 0.31, -t * 0.2)) * 0.3;
	h += vnoise(p * 5.1 + vec2(-t * 0.5, t * 0.4)) * 0.2;
	return h;
}

float grid(vec2 p, float spacing, float px) {
	vec2 gp = p / spacing;
	vec2 gd = abs(fract(gp - 0.5) - 0.5);
	vec2 fw = fwidth(gp);
	vec2 l = 1.0 - smoothstep(fw * px, fw * (px + 1.0), gd);
	return max(l.x, l.y);
}

// onde come somma di sinusoidi direzionali (gradiente analitico: nessun artefatto a griglia)
vec2 wave_grad(vec2 p, float t) {
	float ph = vnoise(p * 0.21) * 6.2831;
	vec2 g = vec2(0.0);
	vec2 d1 = vec2(0.8, 0.6); vec2 d2 = vec2(-0.45, 0.89); vec2 d3 = vec2(0.96, -0.28); vec2 d4 = vec2(-0.7, -0.71);
	g += d1 * 1.6 * cos(dot(d1, p) * 1.6 + t * 0.9 + ph) * 0.05;
	g += d2 * 2.7 * cos(dot(d2, p) * 2.7 + t * 1.3 + ph * 1.7) * 0.03;
	g += d3 * 4.3 * cos(dot(d3, p) * 4.3 - t * 1.7 + ph * 0.6) * 0.018;
	g += d4 * 7.1 * cos(dot(d4, p) * 7.1 + t * 2.3 + ph * 2.3) * 0.009;
	return g;
}

// B-spline bicubica (stessa del terreno): la costa del mare coincide con quella ritagliata sul rilievo
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

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (wpos.xz + world_size * 0.5) / world_size;
	bool inside = uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
	float depth = 1.6;
	float coastd = 99.0;
	if (inside) {
		depth = max(-texture(height_tex, uv).r, 0.0);
		coastd = texture(field_tex, uv).b * 255.0 / 2.0;
		// vicino alla costa: distanza continua dalla superficie bicubica (in celle) al posto del campo a gradini
		if (coastd < 6.0) {
			vec2 e = 1.0 / tex_size;
			float hs = hgt_smooth(uv);
			float gx = texture(height_tex, uv + vec2(e.x, 0.0)).r - texture(height_tex, uv - vec2(e.x, 0.0)).r;
			float gy = texture(height_tex, uv + vec2(0.0, e.y)).r - texture(height_tex, uv - vec2(0.0, e.y)).r;
			float gl = max(length(vec2(gx, gy)) * 0.5, 0.004);
			float sdc = 2.0 * max(-hs, 0.0) / gl;   // mezze celle, come il campo
			coastd = mix(sdc, coastd, smoothstep(3.0, 6.0, coastd));
		}
	}
	// variazione lenta del colore degli abissi (correnti)
	float cur = vnoise(wpos.xz * 0.05) * 0.6 + vnoise(wpos.xz * 0.13) * 0.4;
	vec3 dcol = deep * (0.85 + 0.35 * cur);
	vec3 col = mix(shallow, mid, smoothstep(0.02, 0.35, depth));
	col = mix(col, dcol, smoothstep(0.3, 1.25, depth));
	float t = TIME;
	float aa = 1.0 / (1.0 + fwidth(wpos.x) * 25.0);
	vec2 wg = wave_grad(wpos.xz, t) * aa;
	vec3 n = normalize(vec3(-wg.x, 1.0, -wg.y));
	// isobate da carta nautica: fili chiari a profondità costante sulla piattaforma (solo da vicino/medio)
	if (inside) {
		float dc = depth * 6.0;
		float fwd2 = max(fwidth(dc), 1e-4);
		float isob = 1.0 - smoothstep(0.5 * fwd2, 1.5 * fwd2, abs(fract(dc - 0.5) - 0.5));
		isob *= (1.0 - smoothstep(0.4, 0.75, zoom)) * smoothstep(0.03, 0.08, depth) * (1.0 - smoothstep(0.6, 0.9, depth)) * step(fwd2, 0.4);
		col = mix(col, col * 1.4 + vec3(0.01, 0.02, 0.025), isob * 0.22);
	}
	// schiuma lungo le coste
	float foam_band = 1.0 - smoothstep(0.0, 1.2, coastd);
	float foam = foam_band * smoothstep(0.45, 0.75, vnoise(wpos.xz * 6.0 + vec2(t * 0.6, 0.0)) * 0.6 + foam_band * 0.5 + 0.15 * sin(coastd * 6.0 - t * 2.5));
	foam *= mix(1.0, 0.5, zoom);
	col = mix(col, vec3(0.80, 0.88, 0.90), foam * 0.38);
	// linea di costa sottile (contorno della carta nautica)
	float fwc = max(fwidth(coastd), 0.002);
	float cl = 1.0 - smoothstep(1.5 * fwc, 2.6 * fwc, abs(coastd - 2.2 * fwc - 0.25));
	// reticolo: maglia fine (5 u) che sparisce da lontano, meridiani principali (20 u) sempre
	float edge = 1.0;
	if (!inside) {
		vec2 o = max(abs(wpos.xz) - world_size * 0.5, 0.0);
		edge = 1.0 - smoothstep(0.0, 14.0, length(o));
	}
	float g_minor = grid(wpos.xz + vec2(80.0, 45.0), 5.0, 0.5) * (1.0 - smoothstep(0.35, 0.7, zoom));
	float g_major = grid(wpos.xz + vec2(80.0, 45.0), 20.0, 0.8);
	float g = max(g_minor * 0.45, g_major);
	float land_fade = smoothstep(0.6, 2.5, coastd);
	vec3 emis = vec3(0.30, 0.70, 0.80) * g * grid_alpha * edge * land_fade;
	emis += vec3(0.45, 0.75, 0.80) * cl * 0.06 * float(inside);
	// cornice della carta (doppio filo)
	vec2 ed = abs(wpos.xz) - world_size * 0.5;
	float m = max(ed.x, ed.y);
	float fm = max(fwidth(m), 0.001);
	float frame = (1.0 - smoothstep(fm * 1.0, fm * 2.2, abs(m))) + 0.5 * (1.0 - smoothstep(fm * 0.6, fm * 1.6, abs(m - 1.2)));
	emis += vec3(0.45, 0.80, 0.85) * frame * 0.35;
	// fuori dalla carta: tavolo scuro
	col = mix(col, vec3(0.008, 0.02, 0.035), smoothstep(0.0, 1.0, m) * 0.85);
	// notte: oceano più scuro e opaco, il reticolo resta
	float day = dn_day(wpos);
	float night = 1.0 - day;
	float twl = dn_twilight(wpos);
	col *= mix(vec3(1.0), vec3(0.16, 0.20, 0.30), night);
	col *= mix(vec3(1.0), vec3(1.06, 0.90, 0.80), twl * 0.5);
	emis += vec3(1.0, 0.45, 0.18) * twl * 0.012 * edge;
	emis *= 1.0 + 0.35 * night;
	ALBEDO = col;
	EMISSION = emis;
	SPECULAR = 0.35 * (1.0 - 0.97 * night);
	ROUGHNESS = mix(mix(mix(0.35, 0.22, aa), 0.45, foam), 0.7, night);
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
