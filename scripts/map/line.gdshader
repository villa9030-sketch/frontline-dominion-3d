// Nastri (rotte marittime tratteggiate, percorsi, frecce). UV.x = distanza lungo il nastro, UV.y = 0..1 traverso.
// COLOR = colore per vertice (alpha compreso). UV2.x = densita' del tratteggio (0 = pieno), UV2.y = velocita'.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

varying vec2 dash;

void vertex() {
	dash = UV2;
}

void fragment() {
	float d = dash.x;
	float m = 1.0;
	if (d > 0.0) {
		m = step(fract(UV.x * d - TIME * dash.y), 0.55);
	}
	float edge = 1.0 - smoothstep(0.6, 1.0, abs(UV.y * 2.0 - 1.0));
	float a = COLOR.a * m * edge;
	if (a < 0.01) discard;
	ALBEDO = COLOR.rgb;
	ALPHA = a;
}
