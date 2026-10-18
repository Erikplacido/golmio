// Reflexo que atravessa o logo e o botão JOGAR na diagonal, de tempos em tempos.
// Funciona em qualquer desenho do nó (textura ou _draw): usa a posição local do vértice dividida por
// `rect_size`. Só acende as partes claras (amarelo, creme): contorno e letras pretas ficam como estão.
shader_type canvas_item;

uniform float progress = -1.0;                // -0.2 → 1.2 cruza o nó da esquerda para a direita
uniform vec2 rect_size = vec2(100.0);
uniform float width = 0.09;
uniform float strength = 0.75;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec2 p = local / rect_size;
	float d = p.x + p.y * 0.45 - progress * 1.45;
	float band = 1.0 - smoothstep(0.0, width, abs(d));
	band += (1.0 - smoothstep(0.0, width * 0.35, abs(d + width * 2.2))) * 0.6;   // filete fino atrás
	float lum = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	COLOR.rgb += vec3(band * strength * smoothstep(0.2, 0.6, lum) * COLOR.a);
}
