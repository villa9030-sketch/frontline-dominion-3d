// Numeri tattici e stemmi di fazione (Agente F): quad appoggiati ai fianchi dei mezzi. A sinistra lo stemma (riga bassa
// dell'atlante, tinto con il colore di vertice = colore della fazione), a destra tre cifre del numero per istanza `num`.
// Vernice a stencil: opaca con ritaglio alfa, leggermente ruvida; nessun costo oltre a due letture di texture.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform float emblem = 4.0;
instance uniform float num : instance_index(4) = 0.0;

void fragment() {
	vec2 uv = UV;
	vec4 c;
	if (uv.x < 0.28) {
		vec2 cuv = vec2(clamp(uv.x / 0.28, 0.02, 0.98) * 0.1 + emblem * 0.1, 0.5 + uv.y * 0.5);
		c = texture(atlas, cuv);
		c.rgb *= mix(vec3(1.0), COLOR.rgb * 1.25, 0.85);
	} else {
		float u = (uv.x - 0.3) / 0.7 * 3.0;
		if (u < 0.0 || u >= 3.0) {
			discard;
		}
		float i = floor(u);
		float n = floor(num + 0.5);
		float d = mod(floor(n / pow(10.0, 2.0 - i)), 10.0);
		c = texture(atlas, vec2((fract(u) + d) * 0.1, uv.y * 0.5));
	}
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ROUGHNESS = 0.78;
	METALLIC = 0.0;
	SPECULAR = 0.3;
}
