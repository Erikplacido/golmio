// Camada da tela de abertura (TitleScreen). Um TextureRect é um único retângulo (4 vértices), então
// o movimento é feito no fragmento: cada pixel amostra a textura deslocada.
//   mode 0: parada (só o esmaecimento das laterais)
//   mode 1: torcida pulando: deslocamento vertical que varia suavemente ao longo de x (ondas
//           descompassadas que se somam, como gente pulando fora de sincronia) mais uma "ola" lenta
//   mode 2: bandeiras tremulando: deslocamento horizontal ondulado, maior longe do mastro (topo)
// Coordenadas "da arte" (canvas): a camada ocupa layer_rect (x, y, w, h) dentro de canvas_size.
shader_type canvas_item;

uniform int mode = 0;
uniform vec2 canvas_size = vec2(941.0, 1672.0);
uniform vec4 layer_rect = vec4(0.0, 0.0, 941.0, 1672.0);
uniform float amplitude = 3.0;        // px da arte
uniform float speed = 7.0;
uniform float frequency = 0.045;      // ondas por px da arte (ao longo de x)
uniform float seed = 0.0;
uniform float edge_fade = 0.0;        // fração da largura que esmaece em cada lateral (0 = nada)

// No fragmento, COLOR já vem multiplicado pela textura sem deslocamento; guardamos só a cor do
// vértice (modulate) para multiplicar pela amostra deslocada.
varying vec4 vertex_color;

void vertex() {
	vertex_color = COLOR;
}

float bounce(float x, float t) {
	// Soma de ondas com velocidades e comprimentos diferentes: picos que andam e se cruzam.
	float a = sin(t * speed + x * frequency + seed);
	float b = sin(t * speed * 0.73 - x * frequency * 1.37 + seed * 2.1);
	float c = sin(t * speed * 1.41 + x * frequency * 0.61 + seed * 3.7);
	float w = (a + b * 0.7 + c * 0.5) / 2.2;          // -1..1
	float jump = max(w, 0.0);                          // só para cima: ninguém afunda no chão
	jump = jump * jump * (3.0 - 2.0 * jump);           // pulo com subida e queda suaves
	float ola = 0.5 + 0.5 * sin(t * 0.9 - x * 0.012 + seed); // onda lenta atravessando o estádio
	return jump * (0.55 + 0.45 * ola);
}

void fragment() {
	vec2 px = UV * layer_rect.zw;                     // px dentro da camada
	vec2 art = layer_rect.xy + px;                    // px na arte inteira
	vec2 uv = UV;
	if (mode == 1) {
		float d = bounce(art.x, TIME) * amplitude;
		uv.y += d / layer_rect.w;                     // amostra mais abaixo = conteúdo sobe
	} else if (mode == 2) {
		// O pano mexe mais na ponta (longe do mastro, que fica em cima) e quase nada na base.
		float reach = clamp(UV.y * 1.4, 0.0, 1.0);
		float d = sin(TIME * speed + art.y * frequency + seed) * 0.7
			+ sin(TIME * speed * 1.7 + art.y * frequency * 2.3 + art.x * 0.01) * 0.3;
		uv.x += d * amplitude * reach / layer_rect.z;
		uv.y += sin(TIME * speed * 0.8 + art.x * frequency) * amplitude * 0.35 * reach / layer_rect.w;
	}
	vec4 c = texture(TEXTURE, uv);
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		c.a = 0.0;
	}
	if (edge_fade > 0.0) {
		float u = art.x / canvas_size.x;
		c.a *= smoothstep(0.0, edge_fade, u) * smoothstep(0.0, edge_fade, 1.0 - u);
	}
	COLOR = c * vertex_color;
}
