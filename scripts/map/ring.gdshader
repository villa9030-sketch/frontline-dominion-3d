// Anelli piatti per il tabellone (selezione, bersagli, avanzamento costruzione/coda, rifornimenti...).
// Un unico materiale condiviso: i parametri sono "instance uniform" (set_instance_shader_parameter).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;

instance uniform vec4 ring_color : source_color = vec4(1.0);
instance uniform float progress = 1.0;
instance uniform float dashes = 0.0;
instance uniform float inner = 0.82;
instance uniform float spin = 0.0;
instance uniform float pulse = 0.0;
instance uniform float fill = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.x, -p.y) / 6.2831853 + 0.5;
	float aa = fwidth(r) * 1.2;
	float m = smoothstep(inner - aa, inner, r) * (1.0 - smoothstep(1.0 - aa, 1.0, r));
	if (a > progress) m = 0.0;
	if (dashes > 0.0 && fract(a * dashes + TIME * spin) > 0.55) m = 0.0;
	float f = fill * (1.0 - smoothstep(inner - aa, inner, r)) * (0.5 + 0.5 * r);
	float pl = 1.0 - pulse * (0.5 + 0.5 * sin(TIME * 5.0));
	float alpha = max(m, f) * ring_color.a * mix(1.0, pl, 0.6);
	if (alpha < 0.01) discard;
	ALBEDO = ring_color.rgb;
	ALPHA = alpha;
}
