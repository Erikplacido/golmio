class_name GameIcons
extends RefCounted
## Pacote de ícones do jogo (assets/icons). Use os nomes semânticos daqui, nunca o arquivo:
## os PNGs vêm do Photoshop como "Sem-Título-1_NNNN_nome.png" e são renomeados para "ps1_NNNN_nome.png":
## nome de arquivo com acento não é encontrado no Android (o macOS grava o acento decomposto).
## Os ícones têm tamanhos e proporções diferentes (recorte justo): `apply()` e `rect()` os
## encaixam mantendo a proporção. Substituem emoji na interface (no navegador a fonte não tem emoji).

const DIR := "res://assets/icons/"
const PATHS := {
	"gol": DIR + "ps1_0000_gol.png",
	"defesa": DIR + "ps1_0001_defesa.png",
	"falta": DIR + "ps1_0002_falta.png",
	"substituicao": DIR + "ps1_0003_substituicao.png",
	"amarelo": DIR + "ps1_0004_amarelo.png",
	"vermelho": DIR + "ps1_0005_vermelho.png",
	"escanteio": DIR + "ps1_0006_escanteio.png",
	"lateral": DIR + "ps1_0007_lateral.png",
	"velocidade": DIR + "ps1_0008_velocidade.png",
	"forca": DIR + "ps1_0009_forca.png",
	"passe": DIR + "ps1_0010_passe.png",
	"finalizacao": DIR + "ps1_0011_finalizacao.png",
	"desarme": DIR + "ps1_0012_desarme.png",
	"posicionamento": DIR + "ps1_0013_posicionamento.png",
	"reflexos": DIR + "ps1_0014_reflexos.png",
	"folego": DIR + "ps1_0015_folego.png",
	"treino": DIR + "ps1_0016_treino.png",
	"evolucao": DIR + "ps1_0017_evolucao.png",
	"historico": DIR + "ps1_0018_historico.png",
	"aposentadoria": DIR + "ps1_0019_aposentadoria.png",
	"comissao": DIR + "ps1_0020_comissao.png",
	"contrato": DIR + "ps1_0021_contrato.png",
	"bilheteria": DIR + "ps1_0022_bilheteria.png",
	"patrocinio": DIR + "ps1_0023_patrocinio.png",
	"reputacao": DIR + "ps1_0024_reputacao.png",
	"pressao": DIR + "ps1_0025_pressao.png",
	"coletiva": DIR + "ps1_0026_coletiva.png",
	"convocacao": DIR + "ps1_0027_convocacao.png",
	"normal": DIR + "raridade_normal.png", # gerado no ComfyUI (visuais/arte_ia), não vem do Photoshop
	"raro": DIR + "ps1_0028_raro.png",
	"lendario": DIR + "ps1_0029_lendario.png",
	"mitico": DIR + "ps1_0030_mitico.png",
	"divino": DIR + "ps1_0031_divino.png",
	"clube": DIR + "ps1_0032_clube.png",
	"elenco": DIR + "ps1_0033_elenco.png",
	"tatica": DIR + "ps1_0034_tatica.png",
	"colecao": DIR + "ps1_0035_colecao.png",
	"pacotes": DIR + "ps1_0036_pacotes.png",
	"album": DIR + "ps1_0037_album.png",
	"mercado": DIR + "ps1_0038_mercado.png",
	"moedas": DIR + "ps1_0039_moedas.png",
	"estadio": DIR + "ps1_0040_estadio.png",
	"uniforme": DIR + "ps1_0041_uniforme.png",
	"torcida": DIR + "ps1_0042_torcida.png",
	"calendario": DIR + "ps1_0043_calendario.png",
	"competicoes": DIR + "ps1_0044_competicoes.png",
	"estatisticas": DIR + "ps1_0045_estatisticas.png",
	"objetivos": DIR + "ps1_0046_objetivos.png",
	"olheiros": DIR + "ps1_0047_olheiros.png",
	"estrela_convidada": DIR + "ps1_0048_estrela-convidada.png",
	"penalti": DIR + "ps1_0049_penalti.png",
	"tiro_de_meta": DIR + "ps1_0050_tiro-de-meta.png",
	"elasticidade": DIR + "ps1_0051_elasticidade.png",
	"pular": DIR + "ps1_0052_pular.png",
	"acelerar": DIR + "ps1_0053_acelerar.png",
	"pausar": DIR + "ps1_0054_pausar.png",
	"jogar": DIR + "ps1_0055_jogar.png",
	"replay": DIR + "ps1_0056_replay.png",
	"ajustes": DIR + "ps1_0057_ajustes.png",
	"buscar": DIR + "ps1_0058_buscar.png",
	"filtrar": DIR + "ps1_0059_filtrar.png",
	"bloqueado": DIR + "ps1_0062_bloqueado.png",
	"confirmar": DIR + "ps1_0061_confirmar.png",
	"voltar": DIR + "ps1_0060_voltar.png",
	"fechar": DIR + "ps1_0063_fechar.png",
	# Gerados no ComfyUI (visuais/arte_ia, estilo emblema), não vêm do Photoshop.
	"amistoso": DIR + "icone_amistoso.png",
	"auge": DIR + "icone_auge.png",
	"copa": DIR + "icone_copa.png",
	"declinio": DIR + "icone_declinio.png",
	"defensivo": DIR + "icone_defensivo.png",
	"dica": DIR + "icone_dica.png",
	"editar": DIR + "icone_editar.png",
	"equilibrado": DIR + "icone_equilibrado.png",
	"erro": DIR + "icone_erro.png",
	"idade": DIR + "icone_idade.png",
	"inicio": DIR + "icone_inicio.png",
	"loja": DIR + "icone_loja.png",
	"ofensivo": DIR + "icone_ofensivo.png",
	"oficial": DIR + "icone_oficial.png",
	"ordenar": DIR + "icone_ordenar.png",
	"pendencia": DIR + "icone_pendencia.png",
	"promessa": DIR + "icone_promessa.png",
	"reserva": DIR + "icone_reserva.png",
	"titular": DIR + "icone_titular.png",
	"vazio": DIR + "icone_vazio.png",
}

## Ícone de cada tipo de partida (MatchSetup.KINDS), fase da carreira (GameStore.PHASES) e
## mentalidade (GameTerms.MENTALITIES): use estes mapas, não o nome do arquivo.
const KIND := {"official": "oficial", "friendly": "amistoso", "cup": "copa", "varzea": "estadio", "national": "convocacao"}
const PHASE := {"promessa": "promessa", "auge": "auge", "veterano": "historico", "declinio": "declinio"}
const MENTALITY := {
	"retranca": "defensivo", "defensivo": "defensivo", "cauteloso": "defensivo", "equilibrado": "equilibrado",
	"positivo": "ofensivo", "ofensivo": "ofensivo", "pressao_total": "pressao",
}

static var _cache := {}


## Ícones derivados de outro, espelhado na horizontal (não precisam de arquivo próprio).
const MIRRORED := {"avancar": "voltar"}


static func has(id: String) -> bool:
	if MIRRORED.has(id):
		return has(MIRRORED[id])
	return PATHS.has(id) and ResourceLoader.exists(PATHS[id])


static func texture(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var tex: Texture2D
	if MIRRORED.has(id):
		var base := texture(MIRRORED[id])
		if base:
			var img := base.get_image()
			img.flip_x()
			tex = ImageTexture.create_from_image(img)
	else:
		tex = load(PATHS[id]) if has(id) else null
	_cache[id] = tex
	return tex


## Põe o ícone num botão, com no máximo `size` px de largura (a altura segue a proporção).
static func apply(button: Button, id: String, size: int = 22) -> void:
	var tex := texture(id)
	if tex == null:
		return
	button.icon = tex
	button.expand_icon = false
	button.add_theme_constant_override("icon_max_width", size)


## TextureRect pronto para containers (títulos, rótulos).
static func rect(id: String, size: float = 22.0) -> TextureRect:
	var r := TextureRect.new()
	r.texture = texture(id)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Desenha o ícone centrado em `c`, cabendo num quadrado de lado `size`.
static func draw(ci: CanvasItem, id: String, c: Vector2, size: float, modulate := Color.WHITE) -> void:
	var tex := texture(id)
	if tex == null:
		return
	var ts := tex.get_size()
	var k := size / maxf(ts.x, ts.y)
	ci.draw_texture_rect(tex, Rect2(c - ts * k / 2.0, ts * k), false, modulate)
