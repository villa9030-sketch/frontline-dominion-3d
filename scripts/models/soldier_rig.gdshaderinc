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

mat3 rx(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c, s), vec3(0.0, -s, c)); }
mat3 ry(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, 0.0, -s), vec3(0.0, 1.0, 0.0), vec3(s, 0.0, c)); }
float h1(float n) { return fract(sin(n * 127.1 + 31.7) * 43758.5453); }

// ampiezza dell'oscillazione della coscia (rad) alla velocità v: la CPU usa la stessa formula per la fase (UnitModels.inf_step_rate)
float amp(float v) { return clamp(0.16 + 0.085 * v, 0.2, 0.62); }

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
	bool dead = anim.y < -0.5;
	float dt = dead ? -anim.y - 1.0 : -1.0;
	float spd = max(anim.y, 0.0);
	float mv = clamp(spd * 1.2, 0.0, 1.0);
	float still = 1.0 - mv;
	float tt = tm + r1 * 40.0;
	bool at = bone == 8;

	// ---- pose: in ginocchio (K) e a terra (P, solo il quinto soldato della squadra)
	float fd = dead ? clamp((dt - r1 * 0.7) / 0.9, 0.0, 1.0) : 0.0;
	float K = clamp(max(anim.z, (idx > 0.5 && idx < 1.5) ? still : 0.0), 0.0, 1.0) * (1.0 - fd);
	float P = (idx > 3.5 && idx < 4.5) ? smoothstep(0.5, 1.0, anim.z) : 0.0;
	bool firing = anim.w > 1.0;
	float aim = (firing ? anim.w - 1.0 : anim.w) * still;

	// ---- gambe (falcata dalla velocità, fase per soldato)
	float A = amp(spd) * mv;
	float ph = anim.x + idx * 2.3 + r1 * 1.4;
	float sL = sin(ph);
	float thL = A * sL;
	float thR = -thL;
	float shL = -A * (0.2 + 1.7 * pow(max(cos(ph - 0.5), 0.0), 2.0));
	float shR = -A * (0.2 + 1.7 * pow(max(cos(ph + PI - 0.5), 0.0), 2.0));
	// fermo: peso su una gamba (piccolo spostamento), in ginocchio: sinistra avanti, destra a terra
	float shift = sin(tt * 0.35) * 0.04 * still;
	thL = mix(thL + shift, 1.57, K);
	shL = mix(shL - abs(shift), -1.57, K);
	thR = mix(thR - shift * 0.5, -0.12, K);
	shR = mix(shR, -1.5, K);
	thL = mix(thL, 0.0, P); shL = mix(shL, -0.05, P);
	thR = mix(thR, 0.0, P); shR = mix(shR, -0.08, P);

	// ---- busto: inclinazione in corsa, respiro, torsione che controbilancia le gambe
	float breath = sin(tt * 1.7) * 0.016 * still;
	float lean = -(0.05 + min(spd * 0.035, 0.2)) * mv - 0.08 * K + breath;
	float twist = -0.55 * A * sL;
	lean = mix(lean, 0.38, P);
	// ---- braccia: in mira (0), fucile basso in movimento/a riposo, lanciarazzi in spalla inclinato
	float carry = at ? 0.5 : -0.5;
	float rec = 0.0;
	if (firing && aim > 0.5) {
		float rate = at ? 0.22 : 2.3;
		float cyc = fract(tm * rate + r2);
		float burst = at ? 1.0 : step(0.4, fract(tm * 0.31 + r3));
		rec = exp(-cyc * (at ? 6.0 : 16.0)) * burst * aim;
	}
	float ap = mix(carry + sin(ph * 2.0) * 0.05 * mv, 0.0, aim) + rec * (at ? 0.12 : 0.07);
	ap = mix(ap, at ? 1.0 : 1.12, P);
	float ay = 0.45 * A * sL * (1.0 - aim);
	// ---- testa: uno sguardo ogni tanto quando è fermo, in avanti quando mira
	float g = sin(tt * 0.27 + r3 * 6.0);
	float hy = sign(g) * smoothstep(0.55, 0.9, abs(g)) * 0.65 * still * (1.0 - aim) - twist * 0.6;
	float hp = mix(sin(tt * 0.19) * 0.06 * still, 1.0, P);

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
	// radice: molleggio del passo, abbassamento in ginocchio, corpo disteso a terra
	float bob = -0.88 * (1.0 - cos(thL * (1.0 - K))) + 0.05 * A * abs(cos(ph));
	vec3 root = vec3(0.0, bob - 0.42 * K * (1.0 - P), 0.0);
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
	vtx = Rs * q + off;
	nrm = Rs * (R * n);
}

