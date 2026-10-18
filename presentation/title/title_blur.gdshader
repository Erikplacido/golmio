// Fundo desfocado das laterais da abertura (telas deitadas), como profundidade de campo:
// média de 16 amostras em dois anéis em volta de cada pixel. Barato: só cobre as laterais.
shader_type canvas_item;

uniform float radius = 0.018;   // em UV (fração da textura)

// No fragmento, COLOR já vem multiplicado pela textura sem desfoque; guardamos só a cor do vértice.
varying vec4 vertex_color;

void vertex() {
	vertex_color = COLOR;
}

void fragment() {
	vec4 sum = texture(TEXTURE, UV) * 2.0;
	float total = 2.0;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398 + 0.3;
		vec2 dir = vec2(cos(a), sin(a) * 0.56);   // arte vertical: compensa a proporção
		sum += texture(TEXTURE, UV + dir * radius * 0.5);
		sum += texture(TEXTURE, UV + dir * radius);
		total += 2.0;
	}
	COLOR = (sum / total) * vertex_color;
}
