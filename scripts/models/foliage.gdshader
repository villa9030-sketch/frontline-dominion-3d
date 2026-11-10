// Fogliame (Agente F): colore di vertice con variazione a macchie in spazio oggetto, luce "avvolgente" e trasluce
// controluce (chiome morbide invece di blocchi sfaccettati), leggero ondeggiare al vento proporzionale all'altezza.
// Funziona anche con MultiMesh (la fase del vento usa la posizione dell'istanza).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

uniform sampler2D grime_tex : repeat_enable, filter_linear_mipmap;
uniform float wind = 1.0;

varying vec3 o_pos;
varying vec3 w_pos;

vec3 srgb_to_lin(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void vertex() {
	o_pos = VERTEX;
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 org = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(VERTEX.y - 1.5, 0.0);
	float ph = org.x * 0.21 + org.z * 0.17;
	float sway = sin(TIME * 1.1 + ph) * 0.6 + sin(TIME * 2.3 + ph * 1.7) * 0.25;
	VERTEX.x += sway * h * h * 0.0016 * wind;
	VERTEX.z += sin(TIME * 0.9 + ph * 1.3) * h * h * 0.0009 * wind;
}

void fragment() {
	vec3 alb = srgb_to_lin(COLOR.rgb);
	float dcam = length(w_pos - CAMERA_POSITION_WORLD);
	bool near = dcam < 320.0;
	float n1 = texture(grime_tex, (o_pos.xz + o_pos.yy * vec2(0.6, -0.4)) * 0.22).r;
	float n2 = near ? texture(grime_tex, (o_pos.zy + o_pos.xx * 0.5) * 0.9).r : 0.5;
	// macchie di foglie più chiare/scure e lieve deriva verso il giallo-verde nelle zone chiare
	float v = (n1 - 0.5) * 0.5 + (n2 - 0.5) * 0.35;
	alb *= 1.0 + v;
	alb = mix(alb, alb * vec3(1.08, 1.06, 0.8), clamp(v * 2.0, 0.0, 1.0));
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
		alb *= 0.75;
	}
	// ciuffi di foglie: rilievo fine in spazio mondo (rompe le facce piatte della chioma low-poly) e cavità più scure
	float bk = 1.0 - smoothstep(90.0, 320.0, dcam);
	float lh = texture(grime_tex, w_pos.xz * 0.55 + w_pos.y * vec2(0.31, -0.27)).r * 0.6
		+ (near ? texture(grime_tex, w_pos.zy * 1.35 + w_pos.x * 0.21).r : 0.5) * 0.4;
	if (bk > 0.001) {
		vec3 dpx = dFdx(VERTEX);
		vec3 dpy = dFdy(VERTEX);
		float dhx = dFdx(lh);
		float dhy = dFdy(lh);
		vec3 r1 = cross(dpy, NORMAL);
		vec3 r2 = cross(NORMAL, dpx);
		float dt = dot(dpx, r1);
		vec3 grad = sign(dt) * (dhx * r1 + dhy * r2);
		NORMAL = normalize(abs(dt) * NORMAL - grad * 2.2 * bk);
	}
	float cav = smoothstep(0.25, 0.6, lh);
	alb *= mix(0.62, 1.12, cav);
	alb = mix(alb, alb * vec3(1.1, 1.08, 0.78), smoothstep(0.62, 0.8, lh) * 0.5);
	ALBEDO = alb;
	ROUGHNESS = 0.82;
	SPECULAR = 0.25;
	BACKLIGHT = alb * 0.55;
}
