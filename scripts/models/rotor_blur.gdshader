// Disco di sfocatura dei rotori (Agente F): anello semitrasparente con bande concentriche e punte più marcate,
// sovrapposto alle pale perché il rotore in rotazione non sembri un'elica ferma. Quad in XZ (UV 0..1).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, unshaded;

uniform vec4 tint : source_color = vec4(0.12, 0.12, 0.12, 1.0);
uniform vec4 tip : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float strength = 1.0;

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r = length(d);
	if (r > 1.0) discard;
	float hub = smoothstep(0.08, 0.2, r);
	float edge = 1.0 - smoothstep(0.93, 1.0, r);
	float bands = 0.75 + 0.25 * sin(r * 46.0);
	float ang = atan(d.y, d.x);
	float sweep = 0.8 + 0.2 * sin(ang * 2.0 + TIME * 7.0);
	float a = hub * edge * bands * sweep * 0.2 * strength;
	float t = smoothstep(0.86, 0.95, r) * edge;
	vec3 c = mix(tint.rgb, tip.rgb, t);
	a += t * 0.18 * strength;
	ALBEDO = c;
	ALPHA = clamp(a, 0.0, 0.6);
}
