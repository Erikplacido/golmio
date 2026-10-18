shader_type canvas_item;

// ==============================================================================
// FOTEBA · Shader de Efeito Foil & Pulso para Cartas Digitais (Godot 4)
// Compatível com Renderer GL Compatibility e Mobile.
//
// Porta fiel do motor de foil de visuais/card_studio.html (desenharCamadaFoil e renderFoil*),
// para que os números de card_config.json deem no jogo o mesmo resultado que no Card Studio:
// mesmos gradientes e paradas de cor, mesma varredura no tempo, mesmos raios, flare, ranhuras e
// micro estrelas, em coordenadas do card (card_px, 1122 x 1452). A camada é composta como no
// canvas: primeiro o foil inteiro (source-over entre as próprias formas), depois a máscara
// (destination-in) e, por fim, a mesclagem com a base (globalCompositeOperation) com
// globalAlpha = clamp(opacidade x pulso, 0.05, 1).
// O shader original (aproximado) continua em visuais/foil_card_pulse.gdshader.
//
// Hierarquia de Renderização no Godot (StickerCard):
// 1. TextureRect "Base"        -> card_<nível>.png
// 2. ColorRect "Foil"          -> este shader (lê a própria base para mesclar)
// 3. "PortraitWindow"          -> retrato procedural montado (ou "PlayerGlow" no divino)
// 4. TextureRect "Finish"      -> card_<nível>_acabamento.png (borda e placa preta)
// 5. Control "Overlay"         -> nome, posição, OVR e estrelas
// ==============================================================================

// Tipos de Foil oficiais do FOTEBA (card_config.foil.tipo):
// 0 = Nenhum (Normal)
// 1 = Raro (raro_sutil: safira / prata metálico sutil)
// 2 = Lendário (dourado_metalico: dourado metálico leve com reflexo amplo)
// 3 = Mítico (holografico_violeta_magenta_azul)
// 4 = Divino (perolado_dourado_intenso: ouro velho, raios sacros e flare)
// 5 = Estrela Convidada (prismatico_estrelas: prismático com pequenas estrelas)
uniform int foil_type : hint_range(0, 5) = 2;

// Controles de Animação e Pulso (os mesmos campos do Card Studio)
uniform bool animated = true;                                       // pulso_ativo
uniform float pulse_speed : hint_range(0.1, 10.0) = 2.0;           // pulso_velocidade
uniform float pulse_intensity : hint_range(0.0, 1.0) = 0.32;       // pulso_intensidade
uniform float sheen_speed : hint_range(0.0, 3.0) = 0.28;           // varredura_velocidade
uniform float sheen_angle : hint_range(0.0, 360.0) = 55.0;         // angulo (graus)
uniform float sheen_width : hint_range(0.05, 1.0) = 0.32;          // não usado (compatibilidade)
uniform float sheen_width_px = 240.0;                               // largura_brilho (px do card)
uniform float foil_opacity : hint_range(0.0, 2.0) = 0.85;          // opacidade
uniform float foil_hue_shift : hint_range(0.0, 360.0) = 0.0;       // hue (graus)
// Tamanho do card no Card Studio (card_config.card_dimensoes): todas as medidas abaixo estão nele.
uniform vec2 card_px = vec2(1122.0, 1452.0);

// Modos de Máscara do Efeito Foil (area_mascara do Card Studio):
// 0 = Janela de Arte (x 88..1034, y 90..1225)
// 1 = Moldura & Bordas (fora da janela)
// 2 = Placa Inferior (x 88..1034, y 1225..1375)
// 3 = Card Todo exceto Placa
// 4 = Cobertura Total (100% da superfície do card)
// 5 = Textura de Máscara / Acabamento PNG (usa canal alfa de mask_texture)
uniform int mask_mode : hint_range(0, 5) = 0;
uniform bool invert_mask = false;
uniform vec4 window_uv = vec4(0.0784, 0.0620, 0.9216, 0.8437);   // não usado (compatibilidade)
uniform sampler2D mask_texture : hint_default_white, filter_linear_mipmap;
uniform bool use_mask_texture = false;

// Mesclagem com a base do card (foil.blend). O Godot não tem color-dodge, hard-light nem screen
// no canvas, então o shader lê a própria base (base_texture, a mesma card_*.png desenhada embaixo)
// e devolve a cor já mesclada. 0 = source-over, 1 = screen, 2 = color-dodge, 3 = hard-light,
// 4 = lighter (soma), 5 = overlay, 6 = soft-light, 7 = multiply.
// Sem base_texture (use_base_texture = false) vale sempre a mistura por alfa.
uniform int blend_mode : hint_range(0, 7) = 0;
uniform sampler2D base_texture : hint_default_black, filter_linear_mipmap;
uniform bool use_base_texture = false;

// ------------------------------------------------------------------ mesclagens (W3C)
vec3 blend_screen(vec3 b, vec3 s) {
    return b + s - b * s;
}

vec3 blend_color_dodge(vec3 b, vec3 s) {
    vec3 r;
    for (int i = 0; i < 3; i++) {
        if (b[i] <= 0.0) {
            r[i] = 0.0;
        } else if (s[i] >= 1.0) {
            r[i] = 1.0;
        } else {
            r[i] = min(1.0, b[i] / (1.0 - s[i]));
        }
    }
    return r;
}

vec3 blend_hard_light(vec3 b, vec3 s) {
    vec3 r;
    for (int i = 0; i < 3; i++) {
        r[i] = s[i] <= 0.5 ? b[i] * 2.0 * s[i] : b[i] + (2.0 * s[i] - 1.0) - b[i] * (2.0 * s[i] - 1.0);
    }
    return r;
}

vec3 blend_soft_light(vec3 b, vec3 s) {
    vec3 r;
    for (int i = 0; i < 3; i++) {
        float d = b[i] <= 0.25 ? ((16.0 * b[i] - 12.0) * b[i] + 4.0) * b[i] : sqrt(b[i]);
        r[i] = s[i] <= 0.5 ? b[i] - (1.0 - 2.0 * s[i]) * b[i] * (1.0 - b[i]) : b[i] + (2.0 * s[i] - 1.0) * (d - b[i]);
    }
    return r;
}

vec3 apply_blend(vec3 b, vec3 s) {
    if (blend_mode == 1) return blend_screen(b, s);
    if (blend_mode == 2) return blend_color_dodge(b, s);
    if (blend_mode == 3) return blend_hard_light(b, s);
    if (blend_mode == 4) return min(vec3(1.0), b + s);
    if (blend_mode == 5) return blend_hard_light(s, b);
    if (blend_mode == 6) return blend_soft_light(b, s);
    if (blend_mode == 7) return b * s;
    return s;
}

// Rotação de matiz (hue-rotate do CSS, aproximada pela rotação em torno do eixo de luminância)
vec3 hue_shift(vec3 color, float hue_deg) {
    float angle = radians(hue_deg);
    const vec3 k = vec3(0.57735, 0.57735, 0.57735);
    float c = cos(angle);
    return color * c + cross(k, color) * sin(angle) + k * dot(k, color) * (1.0 - c);
}

// ------------------------------------------------------------------ canvas 2D
// Cor do canvas: rgb 0..255, alfa 0..1 (alfa acima de 1 é cortado, como no rgba() do CSS).
vec4 rgba(float r, float g, float b, float a) {
    return vec4(r / 255.0, g / 255.0, b / 255.0, clamp(a, 0.0, 1.0));
}

// source-over de uma cor (alfa reto) sobre a camada pré-multiplicada.
vec4 over(vec4 layer, vec4 c) {
    return vec4(c.rgb * c.a + layer.rgb * (1.0 - c.a), c.a + layer.a * (1.0 - c.a));
}

// screen de uma cor (alfa reto) sobre a camada pré-multiplicada (fórmula geral de composição).
vec4 over_screen(vec4 layer, vec4 c) {
    float ab = layer.a;
    vec3 cb = ab > 0.0001 ? layer.rgb / ab : vec3(0.0);
    vec3 mixed = c.rgb * c.a * (1.0 - ab) + layer.rgb * (1.0 - c.a) + c.a * ab * blend_screen(cb, c.rgb);
    return vec4(mixed, c.a + ab - c.a * ab);
}

// lighter (soma) de uma cor (alfa reto) sobre a camada pré-multiplicada.
vec4 over_lighter(vec4 layer, vec4 c) {
    return min(vec4(1.0), layer + vec4(c.rgb * c.a, c.a));
}

// Posição (0..1) de p no gradiente linear de p0 a p1, cortada nas pontas (createLinearGradient).
float lin_t(vec2 p, vec2 p0, vec2 p1) {
    vec2 d = p1 - p0;
    return clamp(dot(p - p0, d) / max(dot(d, d), 0.0001), 0.0, 1.0);
}

// Interpolação entre duas paradas de cor do canvas (cor e alfa não pré-multiplicados).
vec4 stop2(float t, float t0, vec4 c0, float t1, vec4 c1) {
    return mix(c0, c1, clamp((t - t0) / max(t1 - t0, 0.00001), 0.0, 1.0));
}

// Cobertura de uma família de retas paralelas (as ranhuras de ctx.stroke): retas que passam por
// (x0 + k * step, 0) com inclinação dx/dy = slope, espessura width, antisserrilhadas.
float stripes(vec2 p, float x0, float step_px, float slope, float width) {
    float u = p.x - p.y * slope - x0;
    float dx = abs(mod(u + step_px * 0.5, step_px) - step_px * 0.5);
    float d = dx / sqrt(1.0 + slope * slope);
    float aa = max(fwidth(d), 0.0001);
    float cov = clamp((width * 0.5 - d) / aa + 0.5, 0.0, 1.0);
    // Em telas pequenas as ranhuras ficam mais finas que um pixel: vira a média, sem moiré.
    return cov * min(1.0, width / aa);
}

// ------------------------------------------------------------------ foils do Card Studio
// Cada função devolve a camada pré-multiplicada (o canvas de rascunho do Card Studio).

// 1. DOURADO METÁLICO LEVE COM REFLEXO AMPLO (LENDÁRIO) · renderFoilDouradoMetalico
vec4 foil_dourado(vec2 p, float t, float pulse, float ang) {
    vec2 dir = vec2(cos(ang), sin(ang));
    float sweep = mod(t * sheen_speed * 420.0, 2000.0) - 1000.0;
    vec2 c = card_px * 0.5 + dir * sweep;
    float dist = 950.0 * (1.0 + 0.10 * sin(t * 2.2));
    float g = lin_t(p, c - dir * dist, c + dir * dist);
    float spec = min(1.0, 0.88 + 0.12 * pulse);
    float a92 = min(1.0, 0.92 * pulse);
    vec4 col;
    if (g < 0.18) col = stop2(g, 0.0, rgba(100.0, 70.0, 5.0, 0.3), 0.18, rgba(218.0, 165.0, 32.0, 0.65));
    else if (g < 0.35) col = stop2(g, 0.18, rgba(218.0, 165.0, 32.0, 0.65), 0.35, rgba(255.0, 215.0, 0.0, 0.85));
    else if (g < 0.44) col = stop2(g, 0.35, rgba(255.0, 215.0, 0.0, 0.85), 0.44, rgba(255.0, 248.0, 200.0, a92));
    else if (g < 0.50) col = stop2(g, 0.44, rgba(255.0, 248.0, 200.0, a92), 0.50, rgba(255.0, 255.0, 255.0, spec));
    else if (g < 0.56) col = stop2(g, 0.50, rgba(255.0, 255.0, 255.0, spec), 0.56, rgba(255.0, 248.0, 200.0, a92));
    else if (g < 0.65) col = stop2(g, 0.56, rgba(255.0, 248.0, 200.0, a92), 0.65, rgba(255.0, 215.0, 0.0, 0.85));
    else if (g < 0.82) col = stop2(g, 0.65, rgba(255.0, 215.0, 0.0, 0.85), 0.82, rgba(218.0, 165.0, 32.0, 0.65));
    else col = stop2(g, 0.82, rgba(218.0, 165.0, 32.0, 0.65), 1.0, rgba(100.0, 70.0, 5.0, 0.3));
    vec4 layer = over(vec4(0.0), col);
    // Linhas finas metálicas diagonais que cintilam com o pulso.
    float lines = stripes(p, -card_px.y, 28.0, tan(ang * 0.5), 1.5);
    return over(layer, vec4(1.0, 1.0, 1.0, clamp(0.07 * pulse, 0.0, 1.0) * lines));
}

// 2. FOIL HOLOGRÁFICO VIOLETA, MAGENTA E AZUL (MÍTICO) · renderFoilHoloVioletaMagentaAzul
vec4 foil_holo(vec2 p, float t, float pulse, float ang) {
    vec2 dir = vec2(cos(ang), sin(ang));
    float sweep = mod(t * sheen_speed * 460.0, 2200.0) - 1100.0;
    vec2 c = card_px * 0.5 + dir * sweep;
    float g = lin_t(p, c - dir * 1000.0, c + dir * 1000.0);
    vec4 white = rgba(255.0, 255.0, 255.0, 0.95 * pulse);
    vec4 col;
    if (g < 0.16) col = stop2(g, 0.0, rgba(74.0, 20.0, 140.0, 0.8), 0.16, rgba(156.0, 39.0, 176.0, 0.85));
    else if (g < 0.32) col = stop2(g, 0.16, rgba(156.0, 39.0, 176.0, 0.85), 0.32, rgba(233.0, 30.0, 99.0, 0.9));
    else if (g < 0.44) col = stop2(g, 0.32, rgba(233.0, 30.0, 99.0, 0.9), 0.44, rgba(0.0, 229.0, 255.0, 0.95));
    else if (g < 0.50) col = stop2(g, 0.44, rgba(0.0, 229.0, 255.0, 0.95), 0.50, white);
    else if (g < 0.56) col = stop2(g, 0.50, white, 0.56, rgba(233.0, 30.0, 99.0, 0.95));
    else if (g < 0.70) col = stop2(g, 0.56, rgba(233.0, 30.0, 99.0, 0.95), 0.70, rgba(33.0, 150.0, 243.0, 0.9));
    else if (g < 0.85) col = stop2(g, 0.70, rgba(33.0, 150.0, 243.0, 0.9), 0.85, rgba(123.0, 31.0, 162.0, 0.85));
    else col = stop2(g, 0.85, rgba(123.0, 31.0, 162.0, 0.85), 1.0, rgba(0.0, 229.0, 255.0, 0.8));
    vec4 layer = over(vec4(0.0), col);
    // Difração holográfica cruzada oscilante (screen).
    vec2 cdir = vec2(cos(ang + PI * 0.5), sin(ang + PI * 0.5));
    float cdist = 600.0 * (0.9 + 0.18 * sin(t * 1.6));
    float h = lin_t(p, c - cdir * cdist, c + cdir * cdist);
    vec4 m35 = rgba(233.0, 30.0, 99.0, 0.35 * pulse);
    vec4 cross_col;
    if (h < 0.48) cross_col = stop2(h, 0.0, rgba(233.0, 30.0, 99.0, 0.0), 0.48, m35);
    else if (h < 0.50) cross_col = stop2(h, 0.48, m35, 0.50, rgba(0.0, 229.0, 255.0, 0.55 * pulse));
    else if (h < 0.52) cross_col = stop2(h, 0.50, rgba(0.0, 229.0, 255.0, 0.55 * pulse), 0.52, m35);
    else cross_col = stop2(h, 0.52, m35, 1.0, rgba(0.0, 229.0, 255.0, 0.0));
    return over_screen(layer, cross_col);
}

// Gradiente radial concêntrico do canvas (r0 -> r1), cortado nas pontas.
float rad_t(vec2 p, vec2 o, float r0, float r1) {
    return clamp((length(p - o) - r0) / max(r1 - r0, 0.0001), 0.0, 1.0);
}

// 3. DOURADO ESCURO E VELHO (DIVINO) · renderFoilPeroladoDivino
vec4 foil_divino(vec2 p, float t, float pulse, float ang) {
    vec2 dir = vec2(cos(ang), sin(ang));
    float sweep = sin(t * sheen_speed * 1.5) * 380.0;
    vec2 c = card_px * 0.5 + dir * sweep;
    vec4 layer = vec4(0.0);

    // 1. Raios celestiais em ouro velho saindo da auréola no topo (561, 140): 18 fatias.
    vec2 o = vec2(561.0, 140.0);
    vec2 v = p - o;
    float r = length(v);
    float off = t * 0.35;
    float slice = TAU / 18.0;
    float wedge = (PI / 18.0) * 0.58;
    float rel = mod(atan(v.y, v.x) - off, TAU);
    float i = floor(rel / slice);
    float inside = rel - i * slice;
    float edge = min(inside, wedge - inside) * r;
    float aa = max(fwidth(edge), 0.0001);
    float ray_cov = clamp(edge / aa + 0.5, 0.0, 1.0) * step(r, 1400.0);
    if (ray_cov > 0.0) {
        float rp = 0.55 + 0.45 * sin(t * 2.8 + i * 1.2);
        float g = rad_t(p, o, 30.0, 1400.0);
        vec4 col;
        if (g < 0.25) col = stop2(g, 0.0, rgba(245.0, 205.0, 115.0, 0.80 * pulse), 0.25, rgba(195.0, 135.0, 30.0, 0.70 * rp * pulse));
        else if (g < 0.55) col = stop2(g, 0.25, rgba(195.0, 135.0, 30.0, 0.70 * rp * pulse), 0.55, rgba(135.0, 78.0, 14.0, 0.50 * rp * pulse));
        else if (g < 0.85) col = stop2(g, 0.55, rgba(135.0, 78.0, 14.0, 0.50 * rp * pulse), 0.85, rgba(75.0, 40.0, 8.0, 0.25 * rp * pulse));
        else col = stop2(g, 0.85, rgba(75.0, 40.0, 8.0, 0.25 * rp * pulse), 1.0, rgba(40.0, 20.0, 4.0, 0.0));
        col.a *= ray_cov;
        layer = over(layer, col);
    }

    // 2. Fundo metálico de ouro escuro e velho.
    float g2 = lin_t(p, c - dir * 850.0, c + dir * 850.0);
    vec4 b;
    if (g2 < 0.15) b = stop2(g2, 0.0, rgba(55.0, 30.0, 8.0, 0.75), 0.15, rgba(110.0, 65.0, 14.0, 0.88));
    else if (g2 < 0.32) b = stop2(g2, 0.15, rgba(110.0, 65.0, 14.0, 0.88), 0.32, rgba(175.0, 115.0, 28.0, 0.94));
    else if (g2 < 0.46) b = stop2(g2, 0.32, rgba(175.0, 115.0, 28.0, 0.94), 0.46, rgba(225.0, 168.0, 65.0, 0.98));
    else if (g2 < 0.50) b = stop2(g2, 0.46, rgba(225.0, 168.0, 65.0, 0.98), 0.50, rgba(250.0, 215.0, 130.0, 1.0));
    else if (g2 < 0.54) b = stop2(g2, 0.50, rgba(250.0, 215.0, 130.0, 1.0), 0.54, rgba(225.0, 168.0, 65.0, 0.98));
    else if (g2 < 0.70) b = stop2(g2, 0.54, rgba(225.0, 168.0, 65.0, 0.98), 0.70, rgba(155.0, 98.0, 22.0, 0.90));
    else if (g2 < 0.85) b = stop2(g2, 0.70, rgba(155.0, 98.0, 22.0, 0.90), 0.85, rgba(100.0, 56.0, 12.0, 0.82));
    else b = stop2(g2, 0.85, rgba(100.0, 56.0, 12.0, 0.82), 1.0, rgba(45.0, 24.0, 6.0, 0.75));
    layer = over(layer, b);

    // 3. Feixe de varredura metálica em ouro antigo (largura_brilho).
    float g3 = lin_t(p, c - dir * sheen_width_px, c + dir * sheen_width_px);
    vec4 f;
    if (g3 < 0.20) f = stop2(g3, 0.0, rgba(65.0, 35.0, 8.0, 0.0), 0.20, rgba(145.0, 88.0, 20.0, 0.75 * pulse));
    else if (g3 < 0.45) f = stop2(g3, 0.20, rgba(145.0, 88.0, 20.0, 0.75 * pulse), 0.45, rgba(220.0, 162.0, 60.0, 0.95 * pulse));
    else if (g3 < 0.50) f = stop2(g3, 0.45, rgba(220.0, 162.0, 60.0, 0.95 * pulse), 0.50, rgba(250.0, 215.0, 130.0, pulse));
    else if (g3 < 0.55) f = stop2(g3, 0.50, rgba(250.0, 215.0, 130.0, pulse), 0.55, rgba(220.0, 162.0, 60.0, 0.95 * pulse));
    else if (g3 < 0.80) f = stop2(g3, 0.55, rgba(220.0, 162.0, 60.0, 0.95 * pulse), 0.80, rgba(145.0, 88.0, 20.0, 0.75 * pulse));
    else f = stop2(g3, 0.80, rgba(145.0, 88.0, 20.0, 0.75 * pulse), 1.0, rgba(65.0, 35.0, 8.0, 0.0));
    layer = over(layer, f);

    // 4. Flare central de ouro sacro quente, pulsando.
    float fr = (sheen_width_px * 2.8) * (0.92 + 0.30 * sin(t * pulse_speed));
    float g4 = rad_t(p, vec2(561.0, 380.0), 25.0, fr);
    vec4 fl;
    if (g4 < 0.25) fl = stop2(g4, 0.0, rgba(255.0, 225.0, 140.0, 0.95 * pulse), 0.25, rgba(215.0, 155.0, 45.0, 0.85 * pulse));
    else if (g4 < 0.55) fl = stop2(g4, 0.25, rgba(215.0, 155.0, 45.0, 0.85 * pulse), 0.55, rgba(145.0, 85.0, 18.0, 0.65 * pulse));
    else if (g4 < 0.80) fl = stop2(g4, 0.55, rgba(145.0, 85.0, 18.0, 0.65 * pulse), 0.80, rgba(80.0, 42.0, 8.0, 0.35 * pulse));
    else fl = stop2(g4, 0.80, rgba(80.0, 42.0, 8.0, 0.35 * pulse), 1.0, rgba(45.0, 20.0, 4.0, 0.0));
    layer = over(layer, fl);

    // 5. Micro-ranhuras de pátina envelhecida.
    float lines = stripes(p, -card_px.y, 22.0, tan(ang * 0.6), 1.2);
    return over(layer, vec4(1.0, 220.0 / 255.0, 130.0 / 255.0, clamp(0.05 * pulse, 0.0, 1.0) * lines));
}

// Micro estrela prismática de 4 pontas (desenharMicroEstrelaPrismatica): espinho vertical fino
// (braço 1.5 r, cintura 0.22 r) com gradiente radial e um ponto branco no centro.
vec4 micro_star(vec2 q, float r, float alpha) {
    if (r <= 2.0) {
        return vec4(0.0);
    }
    float arm = r * 1.5;
    float inner = r * 0.22;
    float u = 1.0 - abs(q.y) / arm;
    float half_w = u > 0.0 ? inner * u * u : -1.0;
    float d = abs(q.x) - half_w;
    float aa = max(fwidth(q.x), 0.0001);
    float shape = clamp(-d / aa + 0.5, 0.0, 1.0) * step(0.0, u);
    float g = clamp((length(q) - 1.0) / max(r - 1.0, 0.0001), 0.0, 1.0);
    vec4 col;
    if (g < 0.4) col = stop2(g, 0.0, rgba(255.0, 255.0, 255.0, alpha), 0.4, rgba(254.0, 240.0, 138.0, alpha * 0.85));
    else if (g < 0.8) col = stop2(g, 0.4, rgba(254.0, 240.0, 138.0, alpha * 0.85), 0.8, rgba(56.0, 189.0, 248.0, alpha * 0.5));
    else col = stop2(g, 0.8, rgba(56.0, 189.0, 248.0, alpha * 0.5), 1.0, rgba(255.0, 255.0, 255.0, 0.0));
    col.a *= shape;
    vec4 layer = over(vec4(0.0), col);
    float dot_r = max(1.5, r * 0.25);
    float dot_cov = clamp((dot_r - length(q)) / aa + 0.5, 0.0, 1.0);
    return over(layer, vec4(1.0, 1.0, 1.0, clamp(alpha * 1.2, 0.0, 1.0) * dot_cov));
}

// 4. FOIL PRISMÁTICO COM PADRÃO DE PEQUENAS ESTRELAS (ESTRELA CONVIDADA) · renderFoilPrismaticoEstrelas
vec4 foil_estrelas(vec2 p, float t, float pulse, float ang) {
    vec2 dir = vec2(cos(ang), sin(ang));
    float sweep = mod(t * sheen_speed * 400.0, 2000.0) - 1000.0;
    vec2 c = card_px * 0.5 + dir * sweep;
    float g = lin_t(p, c - dir * 950.0, c + dir * 950.0);
    vec4 col;
    if (g < 0.16) col = stop2(g, 0.0, rgba(255.0, 82.0, 82.0, 0.7), 0.16, rgba(255.0, 177.0, 66.0, 0.75));
    else if (g < 0.33) col = stop2(g, 0.16, rgba(255.0, 177.0, 66.0, 0.75), 0.33, rgba(255.0, 238.0, 88.0, 0.8));
    else if (g < 0.50) col = stop2(g, 0.33, rgba(255.0, 238.0, 88.0, 0.8), 0.50, rgba(0.0, 230.0, 118.0, 0.8));
    else if (g < 0.66) col = stop2(g, 0.50, rgba(0.0, 230.0, 118.0, 0.8), 0.66, rgba(0.0, 229.0, 255.0, 0.8));
    else if (g < 0.83) col = stop2(g, 0.66, rgba(0.0, 229.0, 255.0, 0.8), 0.83, rgba(179.0, 136.0, 255.0, 0.75));
    else col = stop2(g, 0.83, rgba(179.0, 136.0, 255.0, 0.75), 1.0, rgba(255.0, 64.0, 129.0, 0.7));
    vec4 layer = over(vec4(0.0), col);
    // Grade de micro estrelas (64 px, linhas ímpares deslocadas meia célula), somadas (lighter).
    // Cada estrela ocupa no máximo ~30 px: basta a estrela mais próxima.
    float row = clamp(floor((p.y - 100.0) / 64.0 + 0.5), 0.0, 17.0);
    float y = 100.0 + row * 64.0;
    float shift = mod(floor(y / 64.0), 2.0) < 0.5 ? 0.0 : 32.0;
    float last = floor((1019.0 - 100.0 - shift) / 64.0);
    float col_i = clamp(floor((p.x - 100.0 - shift) / 64.0 + 0.5), 0.0, last);
    float x = 100.0 + shift + col_i * 64.0;
    float seed = sin(x * 12.9898 + y * 78.233);
    float phase = sin(seed * 6.28 + t * 3.8);
    float sz = 14.0 * (0.60 + 0.55 * phase) * (0.85 + 0.25 * pulse);
    float alpha = (0.50 + 0.50 * phase) * pulse;
    vec4 star = micro_star(p - vec2(x, y), sz, alpha);
    return min(vec4(1.0), layer + star);
}

// 5. RARO SUTIL (SAFIRA / PRATA METÁLICO) · renderFoilRaroSutil
vec4 foil_raro(vec2 p, float t, float pulse, float ang) {
    vec2 dir = vec2(cos(ang), sin(ang));
    float sweep = mod(t * sheen_speed * 350.0, 1800.0) - 900.0;
    vec2 c = card_px * 0.5 + dir * sweep;
    float g = lin_t(p, c - dir * 900.0, c + dir * 900.0);
    vec4 hi = rgba(224.0, 242.0, 254.0, 0.85 * pulse);
    vec4 white = rgba(255.0, 255.0, 255.0, 0.95 * pulse);
    vec4 col;
    if (g < 0.25) col = stop2(g, 0.0, rgba(14.0, 116.0, 144.0, 0.35), 0.25, rgba(56.0, 189.0, 248.0, 0.6));
    else if (g < 0.45) col = stop2(g, 0.25, rgba(56.0, 189.0, 248.0, 0.6), 0.45, hi);
    else if (g < 0.50) col = stop2(g, 0.45, hi, 0.50, white);
    else if (g < 0.55) col = stop2(g, 0.50, white, 0.55, hi);
    else if (g < 0.75) col = stop2(g, 0.55, hi, 0.75, rgba(56.0, 189.0, 248.0, 0.6));
    else col = stop2(g, 0.75, rgba(56.0, 189.0, 248.0, 0.6), 1.0, rgba(14.0, 116.0, 144.0, 0.35));
    return over(vec4(0.0), col);
}

// ------------------------------------------------------------------ máscara e composição
float area_mask(vec2 p) {
    float m = 1.0;
    if (mask_mode == 5 || use_mask_texture) {
        m = texture(mask_texture, p / card_px).a;
    } else {
        bool win = p.x >= 88.0 && p.x <= 1034.0 && p.y >= 90.0 && p.y <= 1225.0;
        bool plate = p.x >= 88.0 && p.x <= 1034.0 && p.y >= 1225.0 && p.y <= 1375.0;
        if (mask_mode == 0) m = win ? 1.0 : 0.0;
        else if (mask_mode == 1) m = win ? 0.0 : 1.0;
        else if (mask_mode == 2) m = plate ? 1.0 : 0.0;
        else if (mask_mode == 3) m = (p.y <= 1225.0 || p.y >= 1375.0) ? 1.0 : 0.0;
    }
    return invert_mask ? 1.0 - m : m;
}

// O Godot não aceita `return` dentro de fragment(): a cor do foil sai desta função.
vec4 foil_color(vec2 uv) {
    vec2 p = uv * card_px;
    float mask = area_mask(p);
    if (foil_type == 0 || mask <= 0.001) {
        return vec4(0.0);
    }
    float t = TIME;
    float pulse = animated ? (1.0 + pulse_intensity * sin(t * pulse_speed)) : 1.0;
    float ang = radians(sheen_angle);
    vec4 layer;
    if (foil_type == 1) layer = foil_raro(p, t, pulse, ang);
    else if (foil_type == 2) layer = foil_dourado(p, t, pulse, ang);
    else if (foil_type == 3) layer = foil_holo(p, t, pulse, ang);
    else if (foil_type == 4) layer = foil_divino(p, t, pulse, ang);
    else layer = foil_estrelas(p, t, pulse, ang);
    layer *= mask;
    if (layer.a <= 0.0001) {
        return vec4(0.0);
    }
    vec3 src = clamp(layer.rgb / layer.a, 0.0, 1.0);
    if (abs(foil_hue_shift) > 0.01) {
        src = clamp(hue_shift(src, foil_hue_shift), 0.0, 1.0);
    }
    float a = layer.a * clamp(foil_opacity * pulse, 0.05, 1.0);
    if (use_base_texture && blend_mode != 0) {
        // Resultado = (1 - a) * base + a * B(base, foil): o nó desenha B com alfa a sobre a base.
        vec4 base = texture(base_texture, uv);
        return vec4(apply_blend(base.rgb, src), a * base.a);
    }
    return vec4(src, a);
}

void fragment() {
    COLOR = foil_color(UV);
}
