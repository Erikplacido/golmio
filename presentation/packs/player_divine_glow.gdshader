shader_type canvas_item;

// ==============================================================================
// FOTEBA · Shader de Brilho Divino do Jogador (Aura Externa + Contorno Interno)
// Aplicado no Sprite2D / SubViewport do Atleta / Jogador
// Compatível com Godot 4 (GL Compatibility, Mobile e Forward+)
// ==============================================================================

uniform bool glow_active = true;

// 1. Controles de Intensidade e Raio (Idênticos ao Card Studio)
uniform float outer_intensity : hint_range(0.0, 1.0) = 0.75;
uniform float outer_radius : hint_range(0.0, 80.0) = 28.0;

uniform float inner_intensity : hint_range(0.0, 1.0) = 0.85;
uniform float inner_radius : hint_range(0.0, 40.0) = 12.0;

// 2. Cor Celestial Divina (Dourado por padrão: #fef08a)
uniform vec4 glow_color : source_color = vec4(0.996, 0.941, 0.541, 1.0);

// 3. Dinâmica de Pulso Celestial
uniform bool pulse_active = true;
uniform float pulse_speed : hint_range(0.1, 8.0) = 2.2;

// [Jogo] A textura de um SubViewport transparente sai com a cor pré-multiplicada pelo alfa;
// true desfaz isso antes de compor (sem halo escuro nas bordas do jogador).
uniform bool premultiplied_input = false;

void fragment() {
    vec4 base = texture(TEXTURE, UV);
    if (premultiplied_input && base.a > 0.0001) {
        base.rgb = min(base.rgb / base.a, vec3(1.0));
    }

    // O Godot não aceita `return` dentro de fragment(): sem brilho, só repassa a cor.
    if (!glow_active) {
        COLOR = base;
    } else {

        float t = pulse_active ? TIME : 0.0;
        float pulse = pulse_active ? (0.88 + 0.12 * sin(t * pulse_speed)) : 1.0;
        vec2 ps = TEXTURE_PIXEL_SIZE;

        const int SAMPLES = 16;

        float outer_accum = 0.0;
        float inner_accum = 0.0;

        // 1. Amostragem da Aura Externa (amostra pixels ao redor para criar difusão fora da silhueta)
        if (outer_intensity > 0.01 && outer_radius > 0.5) {
            for (int i = 0; i < SAMPLES; i++) {
                float angle = (float(i) / float(SAMPLES)) * TAU;
                vec2 dir = vec2(cos(angle), sin(angle));
                for (float r = 0.25; r <= 1.0; r += 0.25) {
                    vec2 offset = dir * (outer_radius * r) * ps;
                    float a = texture(TEXTURE, UV + offset).a;
                    outer_accum += a * (1.0 - r * 0.7);
                }
            }
            outer_accum /= (float(SAMPLES) * 2.2);
        }

        // 2. Amostragem do Contorno Interno (detecta transição de borda por dentro da silhueta)
        if (inner_intensity > 0.01 && inner_radius > 0.5 && base.a > 0.02) {
            for (int i = 0; i < SAMPLES; i++) {
                float angle = (float(i) / float(SAMPLES)) * TAU;
                vec2 dir = vec2(cos(angle), sin(angle));
                for (float r = 0.33; r <= 1.0; r += 0.33) {
                    vec2 offset = dir * (inner_radius * r) * ps;
                    float a = texture(TEXTURE, UV + offset).a;
                    // Sangramento interno: detecta pixels vizinhos vazios / transparentes
                    inner_accum += (1.0 - a);
                }
            }
            inner_accum /= (float(SAMPLES) * 1.5);
        }

        // Composição das camadas de luz:
        // A) Aura Externa: irradia onde a silhueta do jogador é transparente (base.a == 0)
        float outer_glow = (1.0 - base.a) * smoothstep(0.01, 0.8, outer_accum) * outer_intensity * pulse;

        // B) Rim Light Interno: ilumina a borda por dentro do corpo do atleta (base.a > 0)
        float inner_glow = base.a * smoothstep(0.04, 0.75, inner_accum) * inner_intensity;

        vec4 final_col = base;

        // Aplica contorno interno dourado sobre a textura do jogador
        if (inner_glow > 0.001) {
            vec3 rim = mix(final_col.rgb, glow_color.rgb, inner_glow * 0.75);
            final_col.rgb = mix(rim, glow_color.rgb, inner_glow * 0.35); // realce especular de borda
        }

        // Aplica aura externa radiante ao redor do jogador
        if (outer_glow > 0.001) {
            final_col.rgb = mix(final_col.rgb, glow_color.rgb, outer_glow);
            final_col.a = max(final_col.a, outer_glow * glow_color.a);
        }

        COLOR = final_col;
    }
}
