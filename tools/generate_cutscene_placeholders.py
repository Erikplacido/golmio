#!/usr/bin/env python3
"""
Gera imagens placebo/placeholders responsivas para cutscenes e vinhetas de lances no FOTEBA.
Resolução base: 1920x1920 (quadrada com Safe Zones para 16:9 paisagem e 9:16 retrato).
"""

import os
from PIL import Image, ImageDraw, ImageFont

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "cutscenes")
os.makedirs(OUT_DIR, exist_ok=True)

SIZE = 1920
SAFE_BOX = 1080  # 1920 * 9/16 = 1080

LANCES = [
    {
        "id": "placeholder_cutscene",
        "title": "LANCE EM ANDAMENTO",
        "sub": "VINHETA PADRÃO DE JOGO",
        "color": (0, 229, 255), # Cyan
        "icon": "⚽"
    },
    {
        "id": "foul_yellow",
        "title": "CARTÃO AMARELO",
        "sub": "ADVERTÊNCIA DISCIPLINAR",
        "color": (245, 158, 11), # Amarelo ouro
        "icon": "🟨"
    },
    {
        "id": "foul_red",
        "title": "CARTÃO VERMELHO",
        "sub": "EXPULSÃO DIRETA / 2º AMARELO",
        "color": (234, 60, 54), # Vermelho Caju
        "icon": "🟥"
    },
    {
        "id": "foul_simple",
        "title": "FALTA MARCADA",
        "sub": "PARALISAÇÃO / TIRO LIVRE",
        "color": (245, 158, 11),
        "icon": "⚠️"
    },
    {
        "id": "penalty",
        "title": "PÊNALTI!",
        "sub": "FALTA DENTRO DA GRANDE ÁREA",
        "color": (234, 60, 54),
        "icon": "🎯"
    },
    {
        "id": "penalty_kick",
        "title": "COBRANÇA DE PÊNALTI",
        "sub": "DECISÃO CARA A CARA",
        "color": (245, 158, 11),
        "icon": "🥅"
    },
    {
        "id": "throw_in",
        "title": "ARREMESSO LATERAL",
        "sub": "REPOSIÇÃO PELA LINHA LATERAL",
        "color": (59, 130, 246), # Azul
        "icon": "👐"
    },
    {
        "id": "corner",
        "title": "ESCANTEIO",
        "sub": "BOLA PARADA NA BANDEIRINHA",
        "color": (59, 130, 246),
        "icon": "🚩"
    },
    {
        "id": "goal_kick",
        "title": "TIRO DE META",
        "sub": "REPOSIÇÃO PELO GOLEIRO",
        "color": (16, 185, 129), # Verde
        "icon": "🧤"
    },
    {
        "id": "goal",
        "title": "G O O O L ! ! !",
        "sub": "BOLA NA REDE!",
        "color": (16, 185, 129),
        "icon": "⚽⚡"
    },
    {
        "id": "save",
        "title": "DEFESA ESPETACULAR!",
        "sub": "O GOLEIRO SALVA O GOL",
        "color": (245, 158, 11),
        "icon": "🛡️"
    },
    {
        "id": "offside",
        "title": "IMPEDIMENTO!",
        "sub": "POSIÇÃO IRREGULAR ASSINALADA",
        "color": (234, 60, 54),
        "icon": "🛑"
    },
    {
        "id": "substitution",
        "title": "SUBSTITUIÇÃO",
        "sub": "ALTERAÇÃO TÁTICA EM CAMPO",
        "color": (139, 92, 246), # Roxo
        "icon": "🔄"
    },
    {
        "id": "kickoff",
        "title": "SAÍDA DE BOLA",
        "sub": "INÍCIO / REINÍCIO DE PARTIDA",
        "color": (0, 229, 255),
        "icon": "⏱️"
    },
    {
        "id": "period_end",
        "title": "FIM DE TEMPO",
        "sub": "APITO FINAL DO ÁRBITRO",
        "color": (203, 213, 225),
        "icon": "🏁"
    }
]

def make_cutscene(info):
    img = Image.new("RGBA", (SIZE, SIZE), (10, 15, 26, 255))
    draw = ImageDraw.Draw(img)

    # 1. Fundo Gradiente e Vinheta Esportiva
    for y in range(SIZE):
        factor = abs(y - SIZE/2) / (SIZE/2)
        r = int(12 + (info["color"][0] * 0.08) * (1 - factor))
        g = int(16 + (info["color"][1] * 0.08) * (1 - factor))
        b = int(28 + (info["color"][2] * 0.08) * (1 - factor))
        draw.line([(0, y), (SIZE, y)], fill=(r, g, b, 255))

    # Círculo central do campo no fundo
    draw.ellipse([(SIZE/2 - 400, SIZE/2 - 400), (SIZE/2 + 400, SIZE/2 + 400)], outline=(255, 255, 255, 15), width=4)
    draw.line([(0, SIZE/2), (SIZE, SIZE/2)], fill=(255, 255, 255, 15), width=4)

    # 2. Guias de Proporção (Safe Zones)
    # Faixa 16:9 Landscape (Y: 420 a 1500)
    y0_16_9 = int((SIZE - SAFE_BOX) / 2)
    y1_16_9 = y0_16_9 + SAFE_BOX
    draw.rectangle([(20, y0_16_9), (SIZE - 20, y1_16_9)], outline=(59, 130, 246, 70), width=3)
    draw.text((30, y0_16_9 + 10), "ÁREA VISÍVEL EM 16:9 (LANDSCAPE / TV / DESKTOP)", fill=(59, 130, 246, 140))

    # Faixa 9:16 Portrait (X: 420 a 1500)
    x0_9_16 = int((SIZE - SAFE_BOX) / 2)
    x1_9_16 = x0_9_16 + SAFE_BOX
    draw.rectangle([(x0_9_16, 20), (x1_9_16, SIZE - 20)], outline=(245, 158, 11, 70), width=3)
    draw.text((x0_9_16 + 10, 30), "ÁREA 9:16 (PORTRAIT / MOBILE)", fill=(245, 158, 11, 140))

    # Safe Zone Universal de Ação (1080 x 1080 no centro)
    draw.rectangle([(x0_9_16, y0_16_9), (x1_9_16, y1_16_9)], outline=info["color"] + (180,), width=4)

    # 3. Card Central de Destaque
    cx, cy = SIZE // 2, SIZE // 2
    cw, ch = 840, 520
    card_box = [cx - cw//2, cy - ch//2, cx + cw//2, cy + ch//2]

    # Fundo do card
    draw.rounded_rectangle(card_box, radius=24, fill=(15, 23, 42, 235), outline=info["color"] + (255,), width=4)

    # Brilho de topo
    draw.rounded_rectangle([card_box[0] + 4, card_box[1] + 4, card_box[2] - 4, card_box[1] + 16], radius=8, fill=info["color"] + (100,))

    # Textos do Card
    try:
        font_large = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 54)
        font_title = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 64)
        font_sub = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 26)
        font_meta = ImageFont.truetype("/System/Library/Fonts/Supplemental/Courier New Bold.ttf", 22)
    except Exception:
        font_large = ImageFont.load_default()
        font_title = font_large
        font_sub = font_large
        font_meta = font_large

    # Badge do Tipo de Lance
    badge_w, badge_h = 420, 50
    bx0, by0 = cx - badge_w//2, card_box[1] + 45
    draw.rounded_rectangle([bx0, by0, bx0 + badge_w, by0 + badge_h], radius=12, fill=info["color"] + (255,))
    draw.text((cx, by0 + 25), "FOTEBA MATCH EVENT", fill=(0, 0, 0, 255), anchor="mm", font=font_sub)

    # Título do Lance
    draw.text((cx, cy - 20), info["title"], fill=(255, 255, 255, 255), anchor="mm", font=font_title)

    # Subtítulo descritivo
    draw.text((cx, cy + 50), info["sub"], fill=info["color"] + (255,), anchor="mm", font=font_sub)

    # Linha divisória
    draw.line([(cx - 300, cy + 95), (cx + 300, cy + 95)], fill=(255, 255, 255, 40), width=2)

    # Informações de Gabarito para o Artista
    draw.text((cx, cy + 140), "GABARITO PLACEBO · SUBSTITUIR POR GIF/ARTE FINAL", fill=(203, 213, 225, 200), anchor="mm", font=font_meta)
    draw.text((cx, cy + 180), "RESPONSIVO: 16:9 (HORIZONTAL) & 9:16 (VERTICAL)", fill=(148, 163, 184, 180), anchor="mm", font=font_meta)
    draw.text((cx, cy + 215), f"ARQUIVO: res://assets/cutscenes/{info['id']}.png", fill=info["color"] + (200,), anchor="mm", font=font_meta)

    # Rodapé externo da tela
    draw.text((cx, SIZE - 80), "FOTEBA ENGINE · SISTEMA DE CUTSCENES E VINHETAS DE LANCES", fill=(100, 116, 139, 150), anchor="mm", font=font_meta)

    out_path = os.path.join(OUT_DIR, f"{info['id']}.png")
    img.save(out_path, "PNG")
    print(f"✓ Gerado: {out_path}")

def main():
    print(f"Gerando {len(LANCES)} placeholders de cutscene em {OUT_DIR}...")
    for lance in LANCES:
        make_cutscene(lance)
    print("Concluído com sucesso!")

if __name__ == "__main__":
    main()
