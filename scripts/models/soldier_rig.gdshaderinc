// Scheletro procedurale dei soldati (Agente F): incluso da soldier.gdshader e dalla sagoma "raggi X" della battaglia,
// così ogni passata disegna la stessa posa. Vedi soldier.gdshader per il significato dei parametri per istanza.
instance uniform vec4 anim : instance_index(2) = vec4(0.0, 0.0, 0.0, 1.0);
instance uniform float seed : instance_index(3) = 0.0;


const vec3 HIP_L = vec3(-0.1, 0.95, 0.0);
const vec3 HIP_R = vec3(0.1, 0.95, 0.0);
const vec3 KNEE_L = vec3(-0.11, 0.52, -0.03);
const vec3 KNEE_R = vec3(0.11, 0.52, -0.03);
const vec3 PELVIS = vec3(0.0, 0.98, 0.0);
const vec3 NECK = vec3(0.0, 1.5, -0.02);
const vec3 SHOULDER = vec3(0.0, 1.4, 0.0);
// gamba: coscia, stinco, anca-caviglia
const float L1 = 0.43;
const float L2 = 0.45;
const float LL = 0.88;

mat3 rx(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c, s), vec3(0.0, -s, c)); }
mat3 ry(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, 0.0, -s), vec3(0.0, 1.0, 0.0), vec3(s, 0.0, c)); }
float h1(float n) { return fract(sin(n * 127.1 + 31.7) * 43758.5453); }

// ---- andatura (la CPU usa le stesse formule in UnitModels.inf_step_rate: niente piedi che scivolano)
// rk: 0 cammina, 1 corre; D: frazione del ciclo con il piede a terra (< 0.5 in corsa: fase di volo);
// X: mezzo passo (m) del piede a terra rispetto all'anca. Il piede d'appoggio scorre all'indietro in modo lineare nella fase,
// quindi alla velocità v la fase avanza di D·π/X radianti per metro.
float run_k(float v) { return smoothstep(2.2, 4.2, v); }
float duty(float v) { return mix(0.5, 0.34, run_k(v)); }
float stride_x(float v) {
	float mv = clamp(v * 1.5, 0.0, 1.0);
	return mix(clamp(0.2 + 0.08 * v, 0.2, 0.36), clamp(0.3 + 0.04 * v, 0.42, 0.5), run_k(v)) * mv;
}

// angolo della coscia (x) e avanzamento dell'oscillazione (y, < 0 se il piede è a terra) alla frazione di ciclo u
vec2 leg_gait(float u, float D, float X, float rk) {
	if (u < D) {
		float x = X * (1.0 - 2.0 * u / D);
		return vec2(asin(x / LL), -1.0);
	}
	float s = (u - D) / (1.0 - D);
	float e = s * s * (3.0 - 2.0 * s);
	float x = -X + 2.0 * X * e;
	return vec2(asin(clamp(x / LL, -0.9, 0.9)) + rk * 0.42 * sin(PI * s) * (X / 0.5), s);
}

// piega del ginocchio della gamba in volo: il piede resta sopra il suolo (distanza verticale anca-piede `d` - sollevamento)
float swing_shin(float th, float s, float d, float rk, float X) {
	float lift = mix(0.035, 0.16, rk) * sin(PI * s) * clamp(X * 6.0, 0.0, 1.0) + 0.006;
	float phi = -acos(clamp((d - lift - L1 * cos(th)) / L2, -1.0, 1.0));
	float sh = phi - th;
	sh = min(sh, -mix(0.12, 1.55, rk) * sin(PI * pow(s, 0.7)) * clamp(X * 6.0, 0.0, 1.0));
	return clamp(sh, -2.4, 0.0);
}

void soldier_pose(inout vec3 vtx, inout vec3 nrm, vec2 uva, vec2 uvb, float tm) {
	float code = uvb.y;
	float idx = floor(code / 16.0 + 0.001);
	int bone = int(round(code - idx * 16.0));
	vec3 off = vec3(uva.x, 0.0, uva.y);
	mat3 Rs = ry(uvb.x);
	vec3 p = transpose(Rs) * (vtx - off);
	vec3 n = transpose(Rs) * nrm;

	float r1 = h1(idx * 1.37 + seed * 7.13);
	float r2 = h1(idx * 3.11 + seed * 1.71 + 5.0);
	float r3 = h1(idx * 5.77 + seed * 2.93 + 9.0);
	float r4 = h1(idx * 2.21 + seed * 4.37 + 13.0);
	bool dead = anim.y < -0.5;
	float dt = dead ? -anim.y - 1.0 : -1.0;
	float spd = max(anim.y, 0.0);
	float mv = clamp(spd * 1.5, 0.0, 1.0);
	float still = 1.0 - mv;
	float tt = tm + r1 * 40.0;
	bool at = bone == 8;

	// ---- pose: in ginocchio (K) e a terra (P, solo il quinto soldato della squadra)
	float fd = dead ? clamp((dt - r1 * 0.7) / 0.9, 0.0, 1.0) : 0.0;
	float K = clamp(max(anim.z, (idx > 0.5 && idx < 1.5) ? still : 0.0), 0.0, 1.0) * (1.0 - fd);
	float P = (idx > 3.5 && idx < 4.5) ? smoothstep(0.5, 1.0, anim.z) : 0.0;
	bool firing = anim.w > 1.0;
	float aim = (firing ? anim.w - 1.0 : anim.w) * still;

	// ---- gambe: appoggio lineare, oscillazione con ginocchio piegato, volo in corsa (fase per soldato)
	float rk = run_k(spd);
	float D = duty(spd);
	float X = stride_x(spd);
	float ph = anim.x + idx * 2.3 + r1 * 1.4;
	float uL = fract(ph / TAU);
	float uR = fract(ph / TAU + 0.5);
	vec2 gl = leg_gait(uL, D, X, rk);
	vec2 gr = leg_gait(uR, D, X, rk);
	float d;
	if (gl.y < 0.0) {
		d = LL * cos(gl.x);
	} else if (gr.y < 0.0) {
		d = LL * cos(gr.x);
	} else {
		float fl = clamp((mod(uL, 0.5) - D) / max(0.5 - D, 0.01), 0.0, 1.0);
		d = LL * cos(asin(X / LL)) - rk * 0.06 * sin(PI * fl);
	}
	float thL = gl.x;
	float thR = gr.x;
	float shL = gl.y < 0.0 ? -0.05 * mv : swing_shin(gl.x, gl.y, d, rk, X);
	float shR = gr.y < 0.0 ? -0.05 * mv : swing_shin(gr.x, gr.y, d, rk, X);
	float rootw = (d - LL) * mv;
	// fermo: peso su una gamba (piccolo spostamento), in ginocchio: sinistra avanti, destra a terra
	float shift = sin(tt * 0.35) * 0.04 * still;
	thL = mix(thL * mv + shift, 1.57, K);
	shL = mix(shL * mv - abs(shift), -1.57, K);
	thR = mix(thR * mv - shift * 0.5, -0.12, K);
	shR = mix(shR * mv, -1.5, K);
	thL = mix(thL, 0.0, P); shL = mix(shL, -0.05, P);
	thR = mix(thR, 0.0, P); shR = mix(shR, -0.08, P);

	// ---- busto: inclinazione in corsa, respiro, torsione che controbilancia le gambe, ondeggiamento sul piede d'appoggio
	float breath = sin(tt * 1.7) * 0.016 * still;
	float sL = sin(ph);
	float lean = -(0.06 + 0.2 * rk) * mv - 0.08 * K + breath;
	float twist = -(0.22 + 0.2 * rk) * (X / 0.5) * sL;
	float sway = 0.035 * (1.0 - rk) * mv * sin(ph - 0.6) * (1.0 - K);
	lean = mix(lean, 0.38, P);
	// ---- braccia: in mira (0), fucile basso in movimento/a riposo (presa diversa per soldato), lanciarazzi in spalla
	float carry = at ? 0.5 : (-0.5 + (r2 - 0.5) * 0.22 - 0.12 * rk * mv);
	float rec = 0.0;
	if (firing && aim > 0.5) {
		float rate = at ? 0.22 : 2.3;
		float cyc = fract(tm * rate + r2);
		float burst = at ? 1.0 : step(0.4, fract(tm * 0.31 + r3));
		rec = exp(-cyc * (at ? 6.0 : 16.0)) * burst * aim;
	}
	float ap = mix(carry + sin(ph * 2.0) * (0.06 + 0.06 * rk) * mv, 0.0, aim) + rec * (at ? 0.12 : 0.07);
	ap = mix(ap, at ? 1.0 : 1.12, P);
	float ay = (0.3 + 0.15 * rk) * (X / 0.5) * sL * (1.0 - aim) * (at ? 0.4 : 1.0);
	// ---- testa: uno sguardo ogni tanto quando è fermo, in avanti quando mira
	float g = sin(tt * 0.27 + r3 * 6.0);
	float hy = sign(g) * smoothstep(0.55, 0.9, abs(g)) * 0.65 * still * (1.0 - aim) - twist * 0.7;
	float hp = mix(sin(tt * 0.19) * 0.06 * still + 0.12 * rk * mv, 1.0, P);

	// ---- caduta: le ginocchia cedono, poi il corpo ruota a terra (avanti o indietro), dopo 4 s sprofonda
	float fall = 0.0;
	float dir = r2 > 0.45 ? 1.0 : -1.0;
	if (dead) {
		float f = fd;
		fall = f * f;
		float buck = sin(PI * clamp(f * 1.2, 0.0, 1.0)) * (1.0 - P);
		thL += 0.55 * buck; thR += 0.4 * buck;
		shL -= 0.9 * buck; shR -= 0.8 * buck;
		ap = mix(ap, dir > 0.0 ? 1.6 : -1.5, f);
		hp += dir * 0.5 * f;
		rec = 0.0;
	}

	// ---- cinematica diretta nella posa locale del soldato
	vec3 q;
	mat3 R;
	mat3 Rsp = ry(twist) * rx(lean);
	if (bone == 3 || bone == 4 || bone == 5 || bone == 6) {
		bool left = bone <= 4;
		vec3 hip = left ? HIP_L : HIP_R;
		vec3 knee = left ? KNEE_L : KNEE_R;
		mat3 Rt = rx(left ? thL : thR);
		if (bone == 3 || bone == 5) {
			q = hip + Rt * (p - hip);
			R = Rt;
		} else {
			mat3 Rk = rx(left ? shL : shR);
			q = hip + Rt * (knee - hip + Rk * (p - knee));
			R = Rt * Rk;
		}
	} else if (bone == 2) {
		mat3 Rh = ry(hy) * rx(hp);
		q = PELVIS + Rsp * (NECK - PELVIS + Rh * (p - NECK));
		R = Rsp * Rh;
	} else if (bone == 7 || bone == 8) {
		mat3 Ra = ry(ay) * rx(ap);
		q = PELVIS + Rsp * (SHOULDER - PELVIS + Ra * (p - SHOULDER) + vec3(0.0, 0.0, rec * 0.05));
		R = Rsp * Ra;
	} else {
		q = PELVIS + Rsp * (p - PELVIS);
		R = Rsp;
	}
	// radice: il piede d'appoggio resta a terra (altezza dell'anca dalla gamba tesa), ondeggiamento laterale,
	// abbassamento in ginocchio, corpo disteso a terra
	vec3 root = vec3(sway, mix(rootw, 0.0, K) - 0.42 * K * (1.0 - P), 0.0);
	if (P > 0.0) {
		vec3 pv = vec3(0.0, 0.21, 0.0);
		mat3 Rp = rx(-1.45 * P);
		q = pv + Rp * (q - pv) + vec3(0.0, 0.0, 0.7 * P);
		R = Rp * R;
	}
	q += root;
	if (dead) {
		vec3 pd = vec3(0.0, 0.07, 0.0);
		mat3 Rd = ry((r3 - 0.5) * 1.2 * fall) * rx(dir * 1.48 * fall * (1.0 - P));
		q = pd + Rd * (q - pd);
		q.y += (dir > 0.0 ? 0.26 : 0.16) * fall * (1.0 - P) - max(dt - 4.0, 0.0) * 0.32;
		R = Rd * R;
	}
	// corporatura per soldato: statura ±6%, spalle/fianchi ±5% (i piedi restano a terra)
	q *= vec3(0.95 + 0.1 * r4, 0.94 + 0.12 * r3, 0.95 + 0.1 * r4);
	vtx = Rs * q + off;
	nrm = Rs * (R * n);
}
