// Vignettatura da sala operativa: bordi scuri e leggermente blu, righe di scansione appena percettibili.
shader_type canvas_item;

uniform float strength = 0.55;
uniform float scan = 0.025;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.x *= 1.25;
	float r = length(p * vec2(0.82, 1.0));
	float v = smoothstep(0.75, 1.65, r) * strength;
	float s = scan * (0.5 + 0.5 * sin(FRAGCOORD.y * 1.6));
	COLOR = vec4(0.0, 0.02, 0.04, clamp(v + s * 0.5, 0.0, 1.0));
}
