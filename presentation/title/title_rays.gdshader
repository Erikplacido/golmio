// Raios de luz girando atrás do logo da abertura (como o "sunburst" das telas de vitória), somados
// por cima da arte (blend_add). Duas coroas de raios em sentidos opostos dão profundidade; o centro
// e a borda esmaecem. `intensity` é animada pela TitleScreen (explode no impacto e assenta).
shader_type canvas_item;
render_mode blend_add;

uniform float intensity = 0.0;
uniform float spin = 0.12;                    // rad/s (0 = parado)
uniform vec4 color : source_color = vec4(1.0, 0.8, 0.32, 1.0);

float rays(float a, float n, float softness) {
	float s = sin(a * n);
	return smoothstep(-softness, 0.6, s);
}

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float a = atan(p.y, p.x);
	float big = rays(a + TIME * spin, 9.0, 0.1);
	float thin = rays(a - TIME * spin * 1.6 + 0.4, 17.0, -0.2) * 0.45;
	float fall = smoothstep(1.0, 0.12, r) * smoothstep(0.0, 0.22, r);
	float pulse = 0.85 + 0.15 * sin(TIME * 1.7);
	COLOR = vec4(color.rgb * max(big, thin) * fall * fall * intensity * pulse, 1.0);
}
