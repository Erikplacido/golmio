// Uniforme do clube no retrato (docs/RETRATOS.md 4.1.1): porta por pixel de Montagem.vestir() e
// Montagem.colorirGola() de visuais/montagem.js. Aplicado pelo PortraitRenderer:
//   mode 0  camisa (torso): máscara abaixo da linha da gola, estampa corPadrao, escudo,
//           volume por retícula de nanquim a 45 graus, linha da gola e contorno original a nanquim
//   mode 1  manga (braço): lado do ombro da linha sleeve a -> b, cor da manga, punho e friso
//   mode 2  gola PNG: recolore pelas faixas de luminância (nanquim, friso, gola)
// Fora da área da roupa o pixel original passa intacto. `modulate` do nó é respeitado.
//
// Coordenadas dos modos 0 e 1 em "pixels de análise" de montagem.js: UV x tamanho ORIGINAL x
// render_scale (padrão 1 = resolução original). render_scale <= 0 = automático, como a `escala`
// que uniforme.html passa a vestir(): 1.1 x pixels de tela por pixel original (dividido por
// density_ratio, a escala do braço relativa ao torso, para os dois usarem a mesma escala, como
// em compor()), limitado a [0.05, 1]. O PortraitRenderer usa o automático. O mapa `maps` vem de UniformMaps
// (R = luminância suavizada, G = distância à borda em pixels do mapa / 255, B = máscara).
shader_type canvas_item;

uniform int mode = 0;

// ---- comuns a camisa e manga
uniform sampler2D maps : filter_linear, repeat_disable;
uniform vec2 size_px = vec2(100.0, 100.0);
uniform float map_to_source = 1.0;
uniform float render_scale = 1.0;
uniform float density_ratio = 1.0;
uniform float median = 0.8;
uniform vec4 bbox = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 color0 = vec4(0.784, 0.063, 0.180, 1.0);
uniform vec4 color1 = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 color2 = vec4(0.114, 0.114, 0.106, 1.0);

// ---- camisa (mode 0)
// pattern: 0 lisa, 1 listras_verticais, 2 listras_horizontais, 3 faixa_diagonal,
//          4 faixa_horizontal, 5 faixa_vertical, 6 metades, 7 xadrez,
//          8 listras_diagonais, 9 chevron, 10 duas_faixas, 11 losangos (desbloqueáveis, Cosmetics)
uniform int pattern = 1;
uniform float pattern_count = 3.0;
uniform float pattern_width = 0.16;
uniform vec2 collar_left = vec2(0.38, 0.0);
uniform vec2 collar_right = vec2(0.62, 0.0);
uniform float collar_depth = 0.055;
uniform bool crest_enabled = false;
uniform vec2 crest_center = vec2(0.7, 0.3);
uniform float crest_size = 0.0;

// ---- manga (mode 1); cores são índices em color0..2
uniform vec2 sleeve_a = vec2(0.0, 0.2);
uniform vec2 sleeve_b = vec2(1.0, 0.2);
uniform int sleeve_color = 0;
uniform bool cuff_enabled = true;
uniform int cuff_color = 1;
uniform float cuff_width = 0.032;
uniform bool cuff_trim = false;
uniform int cuff_trim_color = 2;

// ---- gola PNG (mode 2)
uniform vec4 collar_main = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 collar_trim = vec4(0.114, 0.114, 0.106, 1.0);
uniform float band_softness : hint_range(0.0, 0.2) = 0.03;
// 0 = faixas (L < 0.35 nanquim preservado, < 0.65 friso, resto gola); 1 = pesos contínuos de colorirGola
uniform int collar_blend_mode = 0;

const vec3 INK = vec3(29.0, 26.0, 23.0) / 255.0;
const float COS45 = 0.70710678;

float luma(vec3 c) {
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
}

vec3 kit_color(int i) {
	if (i == 1) {
		return color1.rgb;
	}
	if (i == 2) {
		return color2.rgb;
	}
	return color0.rgb;
}

// `k % 2` do JS seguido de `cores[k] || cores[0]`: negativo vira a cor principal.
int mod2(float k) {
	if (k < 0.0) {
		return 0;
	}
	return int(mod(k, 2.0));
}

// Montagem.corPadrao()
int pattern_index(float u, float v, float aspect) {
	float n = max(1.0, floor(pattern_count + 0.5));
	float w = pattern_width;
	if (pattern == 1) {
		return mod2(floor(u * (2.0 * n + 1.0)));
	} else if (pattern == 2) {
		return mod2(floor(v * (2.0 * n + 1.0)));
	} else if (pattern == 3) {
		return abs(u - v * 0.95 - 0.02) / 1.38 < w / 2.0 ? 1 : 0;
	} else if (pattern == 4) {
		return abs(v - 0.3) < w / 2.0 ? 1 : 0;
	} else if (pattern == 5) {
		return abs(u - 0.5) < w / 2.0 ? 1 : 0;
	} else if (pattern == 6) {
		return u < 0.5 ? 0 : 1;
	} else if (pattern == 7) {
		float cells = 2.0 * n;
		return mod2(floor(u * cells) + floor(v * aspect * cells));
	} else if (pattern == 8) {
		return mod2(floor((u - v * 0.8 + 1.0) * (n + 0.5)));
	} else if (pattern == 9) {
		return abs(v - 0.16 - abs(u - 0.5) * 0.7) < w / 2.0 ? 1 : 0;
	} else if (pattern == 10) {
		return (abs(u - 0.32) < w / 2.0 || abs(u - 0.68) < w / 2.0) ? 1 : 0;
	} else if (pattern == 11) {
		float va = v * aspect;
		return mod2(floor((u + va) * n) + floor((u - va + 8.0) * n));
	}
	return 0;
}

// Montagem.linhaGola(): Bézier quadrática left -> right com fundo em depth.
float collar_line(float x, float W, float H) {
	float xl = collar_left.x * W;
	float yl = collar_left.y * H;
	float xr = collar_right.x * W;
	float yr = collar_right.y * H;
	float cy = 2.0 * collar_depth * H - (yl + yr) / 2.0;
	if (x <= xl) {
		return yl;
	}
	if (x >= xr) {
		return yr;
	}
	float t = (x - xl) / (xr - xl);
	return (1.0 - t) * (1.0 - t) * yl + 2.0 * t * (1.0 - t) * cy + t * t * yr;
}

float dot2(vec2 v) {
	return dot(v, v);
}

// Distância (sem sinal) de pos à quadrática de Bézier A-B-C (solução exata da cúbica).
float bezier_distance(vec2 pos, vec2 A, vec2 B, vec2 C) {
	vec2 a = B - A;
	vec2 b = A - 2.0 * B + C;
	vec2 c = a * 2.0;
	vec2 d = A - pos;
	float kk = 1.0 / dot(b, b);
	float kx = kk * dot(a, b);
	float ky = kk * (2.0 * dot(a, a) + dot(d, b)) / 3.0;
	float kz = kk * dot(d, a);
	float p = ky - kx * kx;
	float q = kx * (2.0 * kx * kx - 3.0 * ky) + kz;
	float h = q * q + 4.0 * p * p * p;
	float res;
	if (h >= 0.0) {
		h = sqrt(h);
		vec2 x = (vec2(h, -h) - q) / 2.0;
		vec2 uv = sign(x) * pow(abs(x), vec2(1.0 / 3.0));
		float t = clamp(uv.x + uv.y - kx, 0.0, 1.0);
		res = dot2(d + (c + b * t) * t);
	} else {
		float z = sqrt(-p);
		float v = acos(clamp(q / (p * z * 2.0), -1.0, 1.0)) / 3.0;
		float m = cos(v);
		float n = sin(v) * 1.732050808;
		vec3 t = clamp(vec3(m + m, -n - m, n - m) * z - kx, 0.0, 1.0);
		res = min(dot2(d + (c + b * t.x) * t.x), dot2(d + (c + b * t.y) * t.y));
	}
	return sqrt(res);
}

// Distância com sinal (negativa dentro), em pixels, à forma de desenharEscudo() de lado S:
// topo reto em -S/2, laterais até 0.08 S e duas quadráticas (controle em (+-S/2, 0.45 S)) até a
// ponta em (0, 0.64 S). Simétrica: basta a metade direita.
float shield_sd(vec2 q, float S) {
	vec2 p = vec2(abs(q.x), q.y) / S;
	float d_top = length(p - vec2(clamp(p.x, 0.0, 0.5), -0.5));
	float d_side = length(p - vec2(0.5, clamp(p.y, -0.5, 0.08)));
	float d_curve = bezier_distance(p, vec2(0.5, 0.08), vec2(0.5, 0.45), vec2(0.0, 0.64));
	float dist = min(min(d_top, d_side), d_curve);
	// Dentro: abaixo do topo, dentro das laterais e acima da curva (x(t) = 0.5 (1 - t^2)).
	float t = sqrt(clamp(1.0 - 2.0 * p.x, 0.0, 1.0));
	float y_curve = 0.08 * (1.0 - t) * (1.0 - t) + 0.9 * t * (1.0 - t) + 0.64 * t * t;
	bool inside = p.x <= 0.5 && p.y >= -0.5 && p.y <= y_curve;
	return (inside ? -dist : dist) * S;
}

// Volume por retícula de nanquim a 45 graus (vestir: nivelSombra, passo, raio, suavidade).
vec3 halftone(vec3 c, float x, float y, float W, float Lb, float d) {
	float level = 0.0;
	float light = Lb / median;
	if (light < 0.97) {
		level += (0.97 - light) * 1.6;
	}
	float shadow_edge = W * 0.06;
	if (d < shadow_edge) {
		level += (1.0 - d / shadow_edge) * 0.7;
	}
	level = clamp(level, 0.0, 1.0);
	if (level > 0.04) {
		float step_px = max(4.0, W * 0.008);
		float rx = (x * COS45 - y * COS45) / step_px;
		float ry = (x * COS45 + y * COS45) / step_px;
		float fx = rx - floor(rx) - 0.5;
		float fy = ry - floor(ry) - 0.5;
		float dc = sqrt(fx * fx + fy * fy);
		float radius = sqrt(level) * 0.46;
		float soft = 0.08;
		if (dc < radius + soft) {
			float a = clamp((radius + soft - dc) / soft, 0.0, 1.0) * min(1.0, level * 1.35);
			vec3 ink = INK * 0.65 + c * 0.35;
			c = c * (1.0 - a * 0.72) + ink * (a * 0.72);
		}
	}
	return c;
}

// Linha a nanquim (gola/barra/costura) e contorno original perto da borda.
vec3 finish(vec3 c, vec3 original, float line_amount, float W, float d) {
	c += (INK - c) * line_amount;
	float L = luma(original);
	float ink_edge = max(3.0, W * 0.014);
	if (d <= ink_edge && L < 0.5) {
		float a = min(1.0, (0.5 - L) / 0.28);
		c += (original - c) * a;
	}
	return c;
}

vec3 collar_png(vec3 rgb) {
	float L = luma(rgb);
	float shade = clamp(L / 0.88, 0.2, 1.3);
	vec3 main_c = collar_main.rgb;
	vec3 trim_c = collar_trim.rgb;
	if (collar_blend_mode == 1) {
		float ink_f = clamp((L - 0.15) / 0.25, 0.0, 1.0);
		float w_trim = clamp(1.0 - abs(L - 0.48) / 0.25, 0.0, 1.0);
		float w_main = clamp((L - 0.55) / 0.35, 0.0, 1.0);
		float sum_w = w_trim + w_main + 0.0001;
		vec3 target = (w_main * main_c + w_trim * trim_c) / sum_w;
		return clamp(INK * (1.0 - ink_f) + target * shade * ink_f, 0.0, 1.0);
	}
	float s = max(band_softness, 0.0001);
	float w_ink = 1.0 - smoothstep(0.35 - s, 0.35 + s, L);
	float w_main2 = smoothstep(0.65 - s, 0.65 + s, L);
	float w_trim2 = max(0.0, 1.0 - w_ink - w_main2);
	return clamp(rgb * w_ink + trim_c * shade * w_trim2 + main_c * shade * w_main2, 0.0, 1.0);
}

// Cor do vértice x modulate do nó. No fragment(), COLOR já vem multiplicado pela textura; por
// isso o modulate é levado por um varying e a textura é amostrada à parte.
varying vec4 modulate_color;

void vertex() {
	modulate_color = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// Densidade de pixels na tela (calculada antes de qualquer desvio de fluxo).
	vec2 src = UV * size_px;
	float per_x = length(vec2(dFdx(src.x), dFdy(src.x)));
	float per_y = length(vec2(dFdx(src.y), dFdy(src.y)));
	float density = 1.0 / max(max(per_x, per_y), 0.0001);
	vec4 mp = texture(maps, UV);
	vec4 result = tex;

	if (mode == 2) {
		if (tex.a >= 5.0 / 255.0) {
			result = vec4(collar_png(tex.rgb), tex.a);
		}
	} else if (tex.a > 0.0) {
		float rs = render_scale > 0.0 ? render_scale : clamp(1.1 * density / max(density_ratio, 0.0001), 0.05, 1.0);
		float W = size_px.x * rs;
		float H = size_px.y * rs;
		float x = UV.x * W;
		float y = UV.y * H;
		float Lb = mp.r;
		float d = mp.g * 255.0 * map_to_source * rs;
		float ink_w = max(1.2, W * 0.0042);

		if (mode == 0) {
			float t = y - collar_line(x, W, H);
			if (t >= 0.0) {
				float top = min(collar_left.y, collar_right.y) * H;
				float bx0 = bbox.x * W;
				float larg = max(1.0, bbox.z * W - bx0);
				float alt = max(1.0, bbox.w * H - top);
				vec3 c = kit_color(pattern_index((x - bx0) / larg, (y - top) / alt, alt / larg));
				if (crest_enabled && crest_size > 0.0) {
					float s = crest_size * W;
					vec2 q = vec2(x, y) - crest_center * vec2(W, H);
					float sd_outer = shield_sd(q, s);
					float sd_inner = shield_sd(q, s * 0.8);
					float a_outer = clamp(0.5 - sd_outer, 0.0, 1.0);
					float a_inner = clamp(0.5 - sd_inner, 0.0, 1.0);
					float line_w = max(1.0, s * 0.05);
					float a_stroke = clamp(line_w * 0.5 + 0.5 - abs(sd_inner), 0.0, 1.0);
					vec3 e = mix(color2.rgb, color0.rgb, a_inner);
					e = mix(e, color1.rgb, a_stroke);
					c = mix(c, e, max(a_outer, a_stroke));
				}
				c = halftone(c, x, y, W, Lb, d);
				float line_amount = clamp(ink_w - abs(t) + 0.5, 0.0, 1.0);
				result = vec4(finish(c, tex.rgb, line_amount, W, d), tex.a);
			}
		} else {
			vec2 A = sleeve_a * vec2(W, H);
			vec2 B = sleeve_b * vec2(W, H);
			vec2 nrm = vec2(-(B.y - A.y), B.x - A.x);
			float nl = length(nrm);
			if (nl == 0.0) {
				nl = 1.0;
			}
			float side_sign = dot(vec2(W * 0.5, 0.0) - A, nrm) / nl >= 0.0 ? 1.0 : -1.0;
			float t = dot(vec2(x, y) - A, nrm) / nl * side_sign;
			if (t >= 0.0) {
				int ci = sleeve_color;
				float seam = 0.0;
				float cuff_px = max(3.0, W * cuff_width);
				if (cuff_enabled && t < cuff_px) {
					ci = (cuff_trim && t < cuff_px * 0.30) ? cuff_trim_color : cuff_color;
					seam = abs(t - cuff_px) < ink_w * 0.6 ? 0.65 : 0.0;
				}
				vec3 c = halftone(kit_color(ci), x, y, W, Lb, d);
				float line_amount = max(clamp(ink_w - abs(t) + 0.5, 0.0, 1.0), seam);
				result = vec4(finish(c, tex.rgb, line_amount, W, d), tex.a);
			}
		}
	}
	COLOR = result * modulate_color;
}
