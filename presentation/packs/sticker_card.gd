class_name StickerCard
extends Control
## Figurinha (docs/RETRATOS.md 4.5 e 9). Desenha uma carta de packs.open ({kind: "athlete",
## athlete_id, tier, name, position, nationality, face} ou um slot colecionável {kind: "reserved",
## slot}) em três faces:
##   - VERSO (carta fechada): gramado com as linhas do campo e o selo FOTEBA;
##   - FRENTE de atleta: a moldura do nível, montada como no visuais/card_studio.html, na mesma
##     ordem de camadas:
##       1 base (card_*.png) · 2 foil animado (foil_card_pulse.gdshader, recortado pela área ou pela
##       máscara do nível) · 3 jogador (PortraitRenderer vestido com o kit do clube, cortado acima da
##       placa; no divino com aura e contorno de luz, player_divine_glow.gdshader) · 4 acabamento
##       (card_*_acabamento.png, borda e placa por cima do jogador) · 5 posição, OVR, estrelas e nome;
##   - "Em breve": slot colecionável ainda reservado (ou colecionável de tipo futuro).
##
## Os níveis vêm de data/cards/card_config.json (cópia fiel do card_studio.html, exportada com as
## imagens por visuais/exportar_cards.py) e todas as medidas estão nas coordenadas do Card Studio
## (card_dimensoes, 1122 x 1452), escaladas para o tamanho real. O nível sai do tier do atleta
## (TIER_FRAMES); card.frame escolhe outro, por exemplo "estrela_convidada".
##
## Uso:
##   var c := StickerCard.new()
##   c.size = Vector2(200, 200 * StickerCard.ASPECT)   # tudo escala junto
##   c.set_card(card, PortraitRenderer.kit_for_club(club), null, athlete.attributes)
##   c.flip_to_front()                                  # anima o verso -> frente (precisa estar na árvore)
##
## A imagem do card tem folga transparente em volta para os ornamentos (troféu, chama, auréola);
## o corpo da carta é BODY_RECT, onde ficam o verso, a face "Em breve", a sombra e o brilho.
## É apresentação: pode usar matemática comum (fora do lint de determinismo).

## Clique na carta (a tela usa para revelar a próxima).
signal pressed

const CONFIG_PATH := "res://data/cards/card_config.json"
const ASSETS_DIR := "res://assets/cards"
const FOIL_SHADER_PATH := "res://presentation/packs/foil_card_pulse.gdshader"
const GLOW_SHADER_PATH := "res://presentation/packs/player_divine_glow.gdshader"
## Tamanho do card no Card Studio (card_config.card_dimensoes), em que todas as medidas estão.
const CARD_PX := Vector2(1122.0, 1452.0)
const ASPECT := 1452.0 / 1122.0
## Tamanho de referência ao criar (o layout real vem de `size`).
const BASE_SIZE := Vector2(200.0, 200.0 * ASPECT)
## Corpo da carta (sem os ornamentos que saem da borda), em px do Card Studio.
const BODY_RECT := Rect2(87.0, 91.0, 949.0, 1311.0)
## Canto arredondado do verso e da face "Em breve", em px do Card Studio.
const RADIUS_PX := 34.0
const KIND_ATHLETE := "athlete"
const KIND_RESERVED := "reserved"

## Tier do atleta (athlete_generator) -> nível da moldura. "estrela_convidada" não sai de tier:
## vem de card.frame.
const TIER_FRAMES := {
	"bronze": "normal", "prata": "raro", "ouro": "lendario", "diamante": "mitico", "deus": "divino",
}
const FRAME_DEFAULT := "normal"
const FRAME_GUEST_STAR := "estrela_convidada"
## card_config -> uniforms de foil_card_pulse.gdshader.
const FOIL_TYPES := {
	"nenhum": 0, "raro_sutil": 1, "dourado_metalico": 2, "holografico_violeta_magenta_azul": 3,
	"perolado_dourado_intenso": 4, "prismatico_estrelas": 5,
}
const MASK_MODES := {
	"janela_arte": 0, "moldura": 1, "placa_nome": 2, "total": 3, "cobertura_total": 4, "sobre_tudo": 4,
	"mascara_custom": 5, "usar_acabamento": 5,
}
const BLEND_MODES := {
	"source-over": 0, "normal": 0, "screen": 1, "color-dodge": 2, "hard-light": 3, "lighter": 4,
	"overlay": 5, "soft-light": 6, "multiply": 7,
}
## Cor do selo da posição por setor (Montagem.SETORES).
const SECTOR_COLORS := {"GK": "#f59e0b", "DEF": "#3b82f6", "MID": "#10b981", "FWD": "#ea3c36"}
## Nome: largura útil da placa, tamanho mínimo e redução do nome em duas linhas (Card Studio).
const NAME_MAX_W := 760.0
const NAME_MIN_PX := 20.0
const NAME_TWO_LINES_SCALE := 0.74

const POSITION_SHORT := {"GK": "GOL", "DEF": "DEF", "MID": "MEI", "FWD": "ATA"}
const POSITION_LONG := {"GK": "Goleiro", "DEF": "Defensor", "MID": "Meio-campista", "FWD": "Atacante"}
## Siglas dos atributos de data/attributes.json (a ordem desempata os melhores atributos).
const ATTRIBUTE_SHORT := {
	"pace": "VEL", "physical": "FIS", "passing": "PAS", "finishing": "FIN", "tackling": "DES",
	"positioning": "POS", "reflexes": "REF", "elasticity": "ELA", "stamina": "EST",
}
## Tier ausente ou desconhecido.
const NEUTRAL_STYLE := {"label": "", "rank": 0, "frame": "", "mid": "#8c9096", "light": "#e7e9ec"}

const FRAME_SHADER := """
shader_type canvas_item;
// Verso e face "Em breve" da figurinha (StickerCard). mode: 1 verso, 2 slot reservado.

uniform vec2 size_px = vec2(200.0, 290.0);
uniform float radius_px = 14.0;
uniform int mode = 1;
uniform vec4 metal_dark : source_color = vec4(0.27, 0.31, 0.36, 1.0);
uniform vec4 metal_mid : source_color = vec4(0.66, 0.70, 0.74, 1.0);
uniform vec4 metal_light : source_color = vec4(0.97, 0.98, 0.98, 1.0);
uniform vec4 ink : source_color = vec4(0.12, 0.15, 0.17, 1.0);
uniform float phase = 0.0;
uniform vec4 back_a : source_color = vec4(0.05, 0.36, 0.22, 1.0);
uniform vec4 back_b : source_color = vec4(0.07, 0.44, 0.26, 1.0);

float sd_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float cover(float d, float aa) {
	return clamp(0.5 - d / aa, 0.0, 1.0);
}

float stroke(float d, float w, float aa) {
	return clamp(0.5 - (abs(d) - w * 0.5) / aa, 0.0, 1.0);
}

vec3 brushed_metal(vec2 uv, vec2 p, float k) {
	float g = uv.y * 0.9 + uv.x * 0.45;
	float w1 = 0.5 + 0.5 * sin(g * 10.0 + 0.6);
	float w2 = 0.5 + 0.5 * sin(g * 27.0 + 2.1);
	vec3 c = mix(metal_dark.rgb, metal_mid.rgb, smoothstep(0.02, 0.8, w1));
	c = mix(c, metal_light.rgb, pow(w2, 8.0) * 0.4 + pow(w1, 14.0) * 0.4);
	float brush = hash21(vec2(floor(p.y / k * 0.9), floor(p.x / k * 0.04)));
	return c * (0.95 + 0.08 * brush);
}

void fragment() {
	vec2 p = UV * size_px;
	float k = size_px.x / 200.0;
	vec2 half_size = size_px * 0.5;
	float d = sd_box(p - half_size, half_size, radius_px);
	float aa = max(fwidth(d), 0.0001);
	float t = TIME + phase * 10.0;
	vec3 col;

	if (mode == 2) {
		// Slot reservado: papel com hachura e borda tracejada.
		vec3 paper = vec3(0.92, 0.9, 0.85);
		float hatch = step(0.5, fract((p.x + p.y) / (9.0 * k)));
		col = mix(paper, paper * 0.955, hatch);
		col *= 1.0 - 0.12 * smoothstep(0.3, 0.9, length(UV - vec2(0.5)) * 1.3);
		float dash = step(0.5, fract((p.x + p.y) / (13.0 * k)));
		col = mix(col, vec3(0.56, 0.53, 0.47), stroke(d + 9.0 * k, 2.0 * k, aa) * dash);
	} else {
		// Verso: gramado listrado, linhas do campo, borda metálica fina.
		float stripes = step(0.5, fract(p.y / (size_px.y / 12.0)));
		col = mix(back_a.rgb, back_b.rgb, stripes);
		col *= 1.0 - 0.3 * smoothstep(0.25, 0.85, length(UV - vec2(0.5)) * 1.3);
		float m = 17.0 * k;
		float lw = 1.8 * k;
		vec2 c = half_size;
		float lines = stroke(sd_box(p - c, c - vec2(m), 2.0 * k), lw, aa);
		lines = max(lines, stroke(p.y - c.y, lw, aa) * step(m, p.x) * step(p.x, size_px.x - m));
		float rc = size_px.x * 0.2;
		lines = max(lines, stroke(length(p - c) - rc, lw, aa));
		vec2 box = vec2(size_px.x * 0.27, size_px.y * 0.07);
		lines = max(lines, stroke(sd_box(p - vec2(c.x, m + box.y), box, 0.0), lw, aa));
		lines = max(lines, stroke(sd_box(p - vec2(c.x, size_px.y - m - box.y), box, 0.0), lw, aa));
		vec2 small_box = vec2(size_px.x * 0.12, size_px.y * 0.03);
		lines = max(lines, stroke(sd_box(p - vec2(c.x, m + small_box.y), small_box, 0.0), lw, aa));
		lines = max(lines, stroke(sd_box(p - vec2(c.x, size_px.y - m - small_box.y), small_box, 0.0), lw, aa));
		col = mix(col, vec3(1.0), lines * 0.5);
		// Selo central (o texto vem por cima, do nó Overlay).
		float seal = length(p - c) - rc * 0.78;
		col = mix(col, back_a.rgb * 0.55, cover(seal, aa) * 0.85);
		col = mix(col, vec3(1.0, 0.93, 0.7), stroke(seal, 2.2 * k, aa));
		// Borda metálica.
		float edge = 1.0 - smoothstep(5.0 * k, 6.5 * k, -d);
		col = mix(col, brushed_metal(UV, p, k), edge);
		float s = fract((UV.x * 0.7 + UV.y) * 0.5 - t * 0.12);
		col += vec3(1.0) * edge * smoothstep(0.0, 0.03, s) * (1.0 - smoothstep(0.03, 0.09, s)) * 0.5;
	}
	col = mix(col, ink.rgb, stroke(d + 0.9 * k, 1.6 * k, aa));
	COLOR = vec4(col, cover(d, aa)) * COLOR;
}
"""

static var _frame_shader: Shader = null
static var _fonts: Dictionary = {}
static var _config: Dictionary = {}

## Carta de packs.open ({} = só verso).
var card: Dictionary = {}
## Kit do clube (PortraitRenderer.kit_for_club); {} = KIT_PADRAO.
var kit: Dictionary = {}
## Atributos do atleta (id -> valor): dão o OVR do selo; {} = sem selo de OVR.
var stats: Dictionary = {}
var catalog: PortraitCatalog = null
## true = frente (atleta ou "Em breve"); false = verso.
var face_up: bool = false
## Cores do gramado do verso (a tela pode usar as do tipo de pacote).
var back_colors: Array = [Color("#0b5a36"), Color("#0f6b40")]
## Brilho em volta da carta (0..1), na cor do nível. Usado na revelação dos níveis altos.
var glow: float = 0.0:
	set(value):
		glow = value
		queue_redraw()

var _frame: ColorRect = null
var _material: ShaderMaterial = null
var _front: Control = null
var _base: TextureRect = null
var _foil: ColorRect = null
var _foil_material: ShaderMaterial = null
var _window: Control = null
var _glow_rect: TextureRect = null
var _glow_material: ShaderMaterial = null
var _viewport: SubViewport = null
var _finish: TextureRect = null
var _portrait: PortraitRenderer = null
var _overlay: Overlay = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_frame = ColorRect.new()
	_frame.name = "Frame"
	_frame.color = Color.WHITE
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = frame_shader()
	_frame.material = _material
	add_child(_frame)

	_front = _plain_control("Front")
	add_child(_front)
	_base = _texture_rect("Base")
	_front.add_child(_base)
	_foil = ColorRect.new()
	_foil.name = "Foil"
	_foil.color = Color.WHITE
	_foil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_foil_material = ShaderMaterial.new()
	_foil_material.shader = load(FOIL_SHADER_PATH) as Shader
	_foil.material = _foil_material
	_front.add_child(_foil)
	_window = _plain_control("PortraitWindow")
	_window.clip_contents = true
	_front.add_child(_window)
	_finish = _texture_rect("Finish")
	_front.add_child(_finish)

	_overlay = Overlay.new()
	_overlay.name = "Overlay"
	_overlay.card_ref = self
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	size = BASE_SIZE
	_layout()


func _notification(what: int) -> void:
	# Fora da árvore o Control não avisa RESIZED: refaz o layout ao entrar (tamanho dado antes).
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_ENTER_TREE:
		_layout()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()


# --- API -------------------------------------------------------------------------------------------

## Define a carta. Atleta com face monta o retrato (PortraitRenderer.setup com o kit); reservado ou
## outro tipo não tem retrato. Mantém o lado atual (face_up).
func set_card(p_card: Dictionary, p_kit: Dictionary = {}, p_catalog: PortraitCatalog = null,
		p_stats: Dictionary = {}) -> void:
	card = p_card.duplicate(true)
	kit = p_kit.duplicate(true)
	stats = p_stats.duplicate()
	catalog = p_catalog
	if _portrait != null:
		_portrait.get_parent().remove_child(_portrait)
		_portrait.free()
		_portrait = null
	var face: Variant = card.get("face")
	if is_athlete() and face is Dictionary and not (face as Dictionary).is_empty():
		_portrait = PortraitRenderer.new()
		_portrait.name = "Portrait"
		_portrait.setup(face, kit, catalog)
		_window.add_child(_portrait)
	_material.set_shader_parameter("phase", float(absi(str(card.get("athlete_id", card.get("slot", ""))).hash()) % 1000) / 1000.0)
	_layout()


## Troca só o uniforme do retrato (ex.: transferência).
func set_kit(p_kit: Dictionary) -> void:
	kit = p_kit.duplicate(true)
	if _portrait != null:
		_portrait.set_kit(kit)
		_refresh_viewport()


## Mostra a frente (true) ou o verso (false), sem animação.
func set_face_up(up: bool) -> void:
	face_up = up
	_layout()


## Vira a carta para a frente com animação (encolhe no eixo x, troca a face, volta). Níveis de
## lendário para cima (3+ estrelas) ganham um "pulo" e o brilho em volta. Fora da árvore só troca a
## face e devolve null.
func flip_to_front(duration: float = 0.45, delay: float = 0.0) -> Tween:
	if face_up:
		return null
	if not is_inside_tree():
		set_face_up(true)
		return null
	pivot_offset = size / 2.0
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(self, "scale:x", 0.0, duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(set_face_up.bind(true))
	tw.tween_property(self, "scale:x", 1.0, duration * 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var rank := int(style().rank)
	if is_athlete() and rank >= 3:
		tw.tween_property(self, "scale", Vector2(1.07, 1.07), 0.12).set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_property(self, "glow", 1.0, 0.12)
		tw.tween_property(self, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_property(self, "glow", 0.35 + 0.15 * (mini(rank, 5) - 3), 0.5)
	return tw


func is_athlete() -> bool:
	return str(card.get("kind", "")) == KIND_ATHLETE


func is_reserved() -> bool:
	return not card.is_empty() and not is_athlete()


func tier() -> String:
	return str(card.get("tier", ""))


## Nível da moldura desta carta (card.frame, se válido; senão o do tier; senão FRAME_DEFAULT).
func frame() -> String:
	var f := frame_for(card)
	return f if f != "" else FRAME_DEFAULT


func style() -> Dictionary:
	var f := frame_for(card)
	return frame_style(f) if f != "" else tier_style(tier())


## Retrato montado (null em reservado, verso sem carta ou atleta sem face).
func portrait() -> PortraitRenderer:
	return _portrait


## OVR do selo: card.ovr, se vier; senão a média dos atributos (a mesma conta do tier no
## athlete_generator e da força na tela de táticas); -1 sem atributos.
func overall_rating() -> int:
	if card.get("ovr") != null:
		return int(card.ovr)
	return overall(stats)


# --- níveis (card_config.json) -------------------------------------------------------------------

## card_config.json inteiro, lido uma vez.
static func config() -> Dictionary:
	if _config.is_empty():
		if FileAccess.file_exists(CONFIG_PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
			if parsed is Dictionary:
				_config = parsed
		if _config.is_empty():
			push_warning("StickerCard: %s ausente ou ilegível (rode python3 visuais/exportar_cards.py)" % CONFIG_PATH)
	return _config


## Esquece o card_config.json lido (ex.: depois de reexportar as molduras).
static func reload_config() -> void:
	_config = {}


## IDs dos níveis na ordem do card_config.json.
static func frames() -> Array:
	var levels: Variant = config().get("niveis", {})
	return (levels as Dictionary).keys() if levels is Dictionary else []


## Configuração de um nível ({} se não existe).
static func frame_config(frame_id: String) -> Dictionary:
	var levels: Variant = config().get("niveis", {})
	if levels is Dictionary and levels.get(frame_id) is Dictionary:
		return levels[frame_id]
	return {}


## Nível de um tier: TIER_FRAMES, ou o próprio ID se já for um nível; "" se desconhecido.
static func frame_for_tier(p_tier: String) -> String:
	if TIER_FRAMES.has(p_tier):
		return str(TIER_FRAMES[p_tier])
	return p_tier if not frame_config(p_tier).is_empty() else ""


## Nível de uma carta: card.frame (se for um nível) ou o do tier.
static func frame_for(p_card: Dictionary) -> String:
	var f := str(p_card.get("frame", ""))
	if f != "" and not frame_config(f).is_empty():
		return f
	return frame_for_tier(str(p_card.get("tier", "")))


## Aparência de um tier para a interface: {label, rank (estrelas), frame, mid (cor do nível),
## light}. Tier desconhecido: neutro, com o próprio ID capitalizado.
static func tier_style(p_tier: String) -> Dictionary:
	var f := frame_for_tier(p_tier)
	if f != "":
		return frame_style(f)
	var s := NEUTRAL_STYLE.duplicate()
	s["label"] = p_tier.capitalize()
	return s


## Aparência de um nível (ver tier_style).
static func frame_style(frame_id: String) -> Dictionary:
	var cfg := frame_config(frame_id)
	if cfg.is_empty():
		var s := NEUTRAL_STYLE.duplicate()
		s["label"] = frame_id.capitalize()
		return s
	var stars: Dictionary = cfg.get("estrelas", {})
	var accent := Color(str(stars.get("cor", NEUTRAL_STYLE.mid)))
	return {
		"label": str(cfg.get("label", frame_id.capitalize())),
		"rank": int(stars.get("qtd", 0)) if stars.get("ativo", true) != false else 0,
		"frame": frame_id,
		"mid": accent.to_html(false),
		"light": accent.lightened(0.5).to_html(false),
	}


static func position_label(position: String, long: bool = false) -> String:
	var table: Dictionary = POSITION_LONG if long else POSITION_SHORT
	return str(table.get(position, position))


## Média dos atributos, arredondada; -1 sem atributos.
static func overall(attrs: Dictionary) -> int:
	if attrs.is_empty():
		return -1
	var total := 0.0
	for key in attrs:
		total += float(attrs[key])
	return roundi(total / attrs.size())


## Os n maiores atributos como [[sigla, valor inteiro], ...] (empate: ordem de ATTRIBUTE_SHORT).
static func top_stats(attrs: Dictionary, n: int = 3) -> Array:
	var rows: Array = []
	var order: Array = ATTRIBUTE_SHORT.keys()
	for key in attrs:
		var idx := order.find(str(key))
		if idx >= 0:
			rows.append([roundi(float(attrs[key])), idx, str(ATTRIBUTE_SHORT[str(key)])])
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out: Array = []
	for r in rows.slice(0, n):
		out.append([r[2], r[0]])
	return out


static func frame_shader() -> Shader:
	if _frame_shader == null:
		_frame_shader = Shader.new()
		_frame_shader.code = FRAME_SHADER
	return _frame_shader


## Fonte das figurinhas: display (Golmio) se bold = true; senão a de texto (Lexend).
static func font(bold: bool = true) -> Font:
	return DesignTokens.font(bold)


## Textura de assets/cards a partir do nome de arquivo do card_config (null se não existe).
static func card_texture(file_name: String) -> Texture2D:
	if file_name == "" or file_name == "custom":
		return null
	var path := ASSETS_DIR.path_join(file_name.get_basename() + ".png")
	if not ResourceLoader.exists(path):
		push_warning("StickerCard: textura ausente %s (rode python3 visuais/exportar_cards.py)" % path)
		return null
	return load(path) as Texture2D


# --- layout ----------------------------------------------------------------------------------------

## Px do Card Studio -> px desta carta, por eixo.
func _k() -> Vector2:
	return Vector2(size.x / CARD_PX.x, size.y / CARD_PX.y)


func _scaled(r: Rect2) -> Rect2:
	var k := _k()
	return Rect2(r.position * k, r.size * k)


func _body() -> Rect2:
	return _scaled(BODY_RECT)


func _level() -> Dictionary:
	return frame_config(frame())


func _layout() -> void:
	if _frame == null:
		return
	var k := _k()
	var kk := minf(k.x, k.y)
	var body := _body()
	_frame.position = body.position
	_frame.size = body.size
	_overlay.position = Vector2.ZERO
	_overlay.size = size
	_front.position = Vector2.ZERO
	_front.size = size
	var front := face_up and is_athlete()
	_front.visible = front
	_frame.visible = not front

	var m := _material
	m.set_shader_parameter("size_px", body.size)
	m.set_shader_parameter("radius_px", RADIUS_PX * kk)
	if not face_up or card.is_empty():
		m.set_shader_parameter("mode", 1)
		m.set_shader_parameter("back_a", back_colors[0])
		m.set_shader_parameter("back_b", back_colors[1])
		m.set_shader_parameter("ink", Color("#1f252b"))
	elif not is_athlete():
		m.set_shader_parameter("mode", 2)
		m.set_shader_parameter("ink", Color("#6f6a60"))
	if front:
		_layout_front()
	queue_redraw()
	_overlay.queue_redraw()


## Camadas da frente (base, foil, jogador, acabamento) para o nível da carta.
func _layout_front() -> void:
	var cfg := _level()
	for rect in [_base, _foil, _finish]:
		(rect as Control).position = Vector2.ZERO
		(rect as Control).size = size
	_base.texture = card_texture(str(cfg.get("card_imagem", "")))
	_base.modulate = Color.WHITE
	var overlay_on: bool = cfg.get("overlay_ativo", true) != false
	_finish.texture = card_texture(str(cfg.get("overlay_imagem", ""))) if overlay_on else null
	_finish.modulate = Color(1, 1, 1, clampf(float(cfg.get("overlay_opacidade", 1.0)), 0.0, 1.0))
	_finish.visible = _finish.texture != null
	_layout_foil(cfg)
	_layout_player(cfg)
	# Ordem: base, foil sobre a base (padrão) ou sobre o jogador, jogador, acabamento.
	var foil_on_top: bool = str((cfg.get("foil", {}) as Dictionary).get("camada_posicao", "")) == "sobre_jogador"
	var player: Control = _glow_rect if _glow_rect != null and _glow_rect.visible else _window
	_front.move_child(_base, 0)
	_front.move_child(_foil, 1)
	_front.move_child(player, 2)
	if foil_on_top:
		_front.move_child(_foil, 2)
	_front.move_child(_finish, _front.get_child_count() - 1)


func _layout_foil(cfg: Dictionary) -> void:
	var foil: Dictionary = cfg.get("foil", {})
	var kind := int(FOIL_TYPES.get(str(foil.get("tipo", "nenhum")), 0))
	_foil.visible = foil.get("ativo", false) == true and kind > 0
	if not _foil.visible:
		return
	var m := _foil_material
	m.set_shader_parameter("foil_type", kind)
	m.set_shader_parameter("animated", foil.get("pulso_ativo", true) != false)
	m.set_shader_parameter("pulse_speed", float(foil.get("pulso_velocidade", 2.0)))
	m.set_shader_parameter("pulse_intensity", float(foil.get("pulso_intensidade", 0.35)))
	m.set_shader_parameter("sheen_speed", float(foil.get("varredura_velocidade", 0.28)))
	m.set_shader_parameter("sheen_angle", float(foil.get("angulo", 55.0)))
	m.set_shader_parameter("sheen_width_px", float(foil.get("largura_brilho", 240.0)))
	m.set_shader_parameter("card_px", CARD_PX)
	m.set_shader_parameter("foil_opacity", float(foil.get("opacidade", 0.7)))
	m.set_shader_parameter("foil_hue_shift", fposmod(float(foil.get("hue", 0.0)), 360.0))
	var area := str(foil.get("area_mascara", "janela_arte"))
	m.set_shader_parameter("mask_mode", int(MASK_MODES.get(area, 0)))
	m.set_shader_parameter("invert_mask", foil.get("mascara_inverter", false) == true)
	var mask: Texture2D = null
	if area == "mascara_custom":
		mask = card_texture(str(foil.get("mascara_arquivo", "")))
	elif area == "usar_acabamento":
		mask = _finish.texture
	m.set_shader_parameter("mask_texture", mask)
	m.set_shader_parameter("use_mask_texture", mask != null)
	if mask == null and int(MASK_MODES.get(area, 0)) == 5:
		m.set_shader_parameter("mask_mode", 0)
	m.set_shader_parameter("base_texture", _base.texture)
	m.set_shader_parameter("use_base_texture", _base.texture != null and str(foil.get("camada_posicao", "")) != "sobre_jogador")
	m.set_shader_parameter("blend_mode", int(BLEND_MODES.get(str(foil.get("blend", "source-over")), 0)))


## Jogador (Card Studio, CAMADA 3): a caixa que une a cabeça e o tronco fica centrada em
## (jogador.x, jogador.y), na escala jogador.escala x 1.5, cortada em jogador.corte_inferior. Nas
## laterais o corte é o corpo da carta (BODY_RECT): o Card Studio deixa o ombro vazar uns 15 px
## para a margem transparente. Com brilho_divino ativo, o jogador é desenhado num SubViewport e
## composto com o shader de brilho.
func _layout_player(cfg: Dictionary) -> void:
	var j: Dictionary = cfg.get("jogador", {})
	var k := _k()
	var glow_cfg: Dictionary = j.get("brilho_divino", {}) if j.get("brilho_divino") is Dictionary else {}
	var use_glow: bool = _portrait != null and glow_cfg.get("ativo", false) == true \
		and ((float(glow_cfg.get("externo_intensidade", 0)) > 0.0 and float(glow_cfg.get("externo_raio", 0)) > 0.0)
			or (float(glow_cfg.get("interno_intensidade", 0)) > 0.0 and float(glow_cfg.get("interno_raio", 0)) > 0.0))
	_set_glow_host(use_glow)
	var cut := float(j.get("corte_inferior", 1225.0)) if j.get("corte_ativo", true) != false else CARD_PX.y
	_window.position = Vector2(BODY_RECT.position.x * k.x, 0.0)
	_window.size = Vector2(BODY_RECT.size.x * k.x, cut * k.y)
	if _portrait != null:
		var box := _player_box()
		var s := (float(j.get("escala")) if j.get("escala") != null else 0.48) * 1.5 * minf(k.x, k.y)
		_portrait.fit_size = Vector2.ZERO
		_portrait.scale = Vector2(s, s)
		_portrait.position = Vector2(float(j.get("x", 561.0)) * k.x, float(j.get("y", 760.0)) * k.y) \
			- box.get_center() * s - _window.position
	if use_glow:
		_glow_rect.position = Vector2.ZERO
		_glow_rect.size = size
		var g := _glow_material
		g.set_shader_parameter("glow_active", true)
		g.set_shader_parameter("outer_intensity", clampf(float(glow_cfg.get("externo_intensidade", 75)) / 100.0, 0.0, 1.0))
		g.set_shader_parameter("outer_radius", float(glow_cfg.get("externo_raio", 28)) * k.x)
		g.set_shader_parameter("inner_intensity", clampf(float(glow_cfg.get("interno_intensidade", 85)) / 100.0, 0.0, 1.0))
		g.set_shader_parameter("inner_radius", float(glow_cfg.get("interno_raio", 12)) * k.x)
		g.set_shader_parameter("glow_color", Color(str(glow_cfg.get("cor", "#fef08a"))))
		g.set_shader_parameter("pulse_active", glow_cfg.get("pulso", true) != false)
		g.set_shader_parameter("premultiplied_input", true)
		_refresh_viewport()


## Caixa da cabeça unida à do tronco, no espaço da cabeça (o cabelo não entra, como no Card Studio).
func _player_box() -> Rect2:
	var box := Rect2()
	var first := true
	for layer in _portrait.layers:
		if layer.slot != "head" and layer.slot != "body":
			continue
		var r := PortraitLayout.layer_rect(layer)
		box = r if first else box.merge(r)
		first = false
	return _portrait.content_bounds() if first else box


## Liga ou desliga o desenho do jogador num SubViewport (para o shader de brilho divino).
func _set_glow_host(on: bool) -> void:
	if on and _viewport == null:
		_viewport = SubViewport.new()
		_viewport.name = "PlayerViewport"
		_viewport.transparent_bg = true
		_viewport.disable_3d = true
		_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(_viewport)
		_glow_rect = _texture_rect("PlayerGlow")
		_glow_material = ShaderMaterial.new()
		_glow_material.shader = load(GLOW_SHADER_PATH) as Shader
		_glow_rect.material = _glow_material
		_glow_rect.texture = _viewport.get_texture()
		_front.add_child(_glow_rect)
	var host: Node = _viewport if on else _front
	if _window.get_parent() != host:
		_window.get_parent().remove_child(_window)
		host.add_child(_window)
	if _glow_rect != null:
		_glow_rect.visible = on


func _refresh_viewport() -> void:
	if _viewport == null or _window.get_parent() != _viewport:
		return
	_viewport.size = Vector2i(maxi(1, ceili(size.x)), maxi(1, ceili(size.y)))
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


static func _plain_control(node_name: String) -> Control:
	var c := Control.new()
	c.name = node_name
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func _texture_rect(node_name: String) -> TextureRect:
	var t := TextureRect.new()
	t.name = node_name
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	return t


# --- desenho ---------------------------------------------------------------------------------------

## Sombra e brilho atrás do corpo da carta.
func _draw() -> void:
	var kk := minf(_k().x, _k().y)
	var body := _body()
	var radius := int(RADIUS_PX * kk)
	if glow > 0.01 and face_up and is_athlete():
		var g := StyleBoxFlat.new()
		var light := Color(style().light)
		g.bg_color = Color(light, 0.55 * glow)
		g.set_corner_radius_all(radius + int(6.0 * kk))
		g.shadow_color = Color(light, 0.75 * glow)
		g.shadow_size = int(120.0 * kk)
		draw_style_box(g, body.grow(28.0 * kk))
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0, 0, 0, 0.35)
	sh.set_corner_radius_all(radius)
	sh.shadow_color = Color(0, 0, 0, 0.28)
	sh.shadow_size = int(55.0 * kk)
	draw_style_box(sh, Rect2(body.position + Vector2(0.0, 22.0 * kk), body.size))


## Desenho por cima de tudo (chamado pelo nó Overlay).
func _draw_overlay(ci: Control) -> void:
	if not face_up or card.is_empty():
		_draw_back(ci)
	elif is_athlete():
		_draw_front(ci)
	else:
		_draw_reserved(ci)


func _draw_back(ci: Control) -> void:
	var c := _body().get_center()
	var k := _body().size.x / 200.0   # medidas do verso em px de um corpo de 200 px
	var bold := font(true)
	draw_text_centered(ci, bold, "FOTEBA", c + Vector2(0, -2.0 * k), 19.0 * k, Color("#fff1c1"), Color(0, 0, 0, 0.55), 3.0 * k)
	draw_text_centered(ci, font(false), "FIGURINHA", c + Vector2(0, 15.0 * k), 8.5 * k, Color(1, 1, 1, 0.8))


func _draw_reserved(ci: Control) -> void:
	var body := _body()
	var k := body.size.x / 200.0
	var center := Vector2(body.get_center().x, body.position.y + body.size.y * 0.4)
	var r := 34.0 * k
	ci.draw_circle(center, r, Color("#d9d3c4"))
	ci.draw_arc(center, r, 0.0, TAU, 48, Color("#9a9384"), 2.0 * k, true)
	var bold := font(true)
	draw_text_centered(ci, bold, "?", center + Vector2(0, 1.0 * k), 40.0 * k, Color("#8a8374"))
	draw_text_centered(ci, bold, "Em breve", Vector2(center.x, body.position.y + body.size.y * 0.66), 21.0 * k, Color("#5e584c"))
	var kind := str(card.get("kind", KIND_RESERVED))
	var sub := "Colecionável" if kind == KIND_RESERVED else kind.capitalize()
	draw_text_centered(ci, font(false), "%s · slot %d" % [sub, int(card.get("slot", 0)) + 1],
		Vector2(center.x, body.position.y + body.size.y * 0.745), 12.0 * k, Color("#7a7466"))


## Textos e selos da frente (Card Studio, CAMADA 5): nome na placa, selo da posição, OVR e estrelas.
func _draw_front(ci: Control) -> void:
	var cfg := _level()
	var k := _k()
	var kk := minf(k.x, k.y)
	var bold := font(true)

	# 1. Nome: maiúsculas, tamanho confortável para leitura, quebra em duas linhas se composto.
	var n: Dictionary = cfg.get("nome", {})
	var raw_name := str(card.get("name", "")).strip_edges()
	if n.get("maiusculas", true) != false:
		raw_name = raw_name.to_upper()
	var lines := split_composite_name(raw_name)
	if not lines.is_empty():
		# Base ampliada para garantir legibilidade mesmo em miniaturas (tokens / mobile)
		var base_px := float(n.get("tamanho", 52.0))
		base_px = maxf(base_px, 82.0)
		var two_line_scale := 0.84
		var px := roundf(base_px * two_line_scale) if lines.size() > 1 else base_px
		var font_px := maxf(px * kk, 11.5)
		var max_w_screen := NAME_MAX_W * k.x
		for line in lines:
			var w := bold.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(1, roundi(font_px))).x
			if w > max_w_screen:
				font_px = maxf(9.0, font_px * max_w_screen / w)
		var color := Color(str(n.get("cor", "#ffffff")))
		var shadow := _css_color(str(n.get("sombra", "rgba(0,0,0,0.85)")), Color(0, 0, 0, 0.85))
		var nx := float(n.get("x", 561.0)) * k.x
		var ny := 1292.0 * k.y
		var ys: Array = [ny]
		if lines.size() > 1:
			var spacing := roundf(font_px * 1.1)
			ys = [ny - spacing * 0.45, ny + spacing * 0.55]
		for i in lines.size():
			var center := Vector2(nx, float(ys[i]))
			draw_text_centered(ci, bold, lines[i], center + Vector2(1.5, 1.5) * kk, font_px, shadow,
				Color(shadow, shadow.a * 0.4), 3.0 * kk)
			draw_text_centered(ci, bold, lines[i], center, font_px, color)

	# 2. Selo da posição (canto superior esquerdo), na cor do setor.
	var p: Dictionary = cfg.get("posicao", {})
	if p.get("ativo", true) != false:
		var pos := str(card.get("position", ""))
		var rect := Rect2(float(p.get("x", 140)) * k.x, float(p.get("y", 140)) * k.y,
			float(p.get("largura", 120)) * k.x, float(p.get("altura", 56)) * k.y)
		var fill := Color(str(SECTOR_COLORS.get(pos, "#3b82f6"))) if p.get("usar_cor_setor", true) != false else Color("#3b82f6")
		_draw_badge(ci, rect, fill, Color(1, 1, 1, 0.4), 2.0 * kk, 10.0 * kk)
		draw_text_centered(ci, bold, position_label(pos), rect.get_center(), float(p.get("fonte_tamanho", 28)) * kk, Color.WHITE)

	# 3. OVR (canto superior direito; x é a borda direita do selo).
	var o: Dictionary = cfg.get("ovr", {})
	var ovr := overall_rating()
	if o.get("ativo", true) != false and ovr >= 0:
		var ow := float(o.get("largura", 110))
		var rect := Rect2((float(o.get("x", 982)) - ow) * k.x, float(o.get("y", 140)) * k.y, ow * k.x,
			float(o.get("altura", 56)) * k.y)
		_draw_badge(ci, rect, _css_color(str(o.get("cor_fundo", "rgba(0,0,0,0.8)")), Color(0, 0, 0, 0.8)),
			Color(1, 1, 1, 0.25), 1.5 * kk, 10.0 * kk)
		draw_text_centered(ci, bold, str(ovr), rect.get_center(), float(o.get("fonte_tamanho", 32)) * kk,
			Color(str(o.get("cor_texto", "#f59e0b"))))

	# 4. Estrelas do nível, centradas acima do nome na placa.
	var e: Dictionary = cfg.get("estrelas", {})
	var count := int(e.get("qtd", 0))
	if e.get("ativo", false) == true and count > 0:
		var star_px := float(e.get("tamanho", 22)) * kk
		var step := star_px * 0.95
		var r := star_px * 0.45
		var c := Vector2(float(e.get("x", 561)) * k.x, 1238.0 * k.y)
		var star_color := Color(str(e.get("cor", "#f59e0b")))
		for i in count:
			var cx := c.x + (i - (count - 1) / 2.0) * step
			draw_star(ci, Vector2(cx, c.y), r, star_color, star_color, maxf(0.5, 0.5 * kk))


static func _draw_badge(ci: CanvasItem, rect: Rect2, fill: Color, border: Color, border_px: float, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(maxi(1, roundi(radius)))
	sb.border_color = border
	sb.set_border_width_all(maxi(1, roundi(border_px)))
	sb.anti_aliasing = true
	ci.draw_style_box(sb, rect)


## Cor CSS do card_config: "#rrggbb", "#rrggbbaa" ou "rgba(r, g, b, a)" / "rgb(r, g, b)".
static func _css_color(text: String, fallback: Color) -> Color:
	var t := text.strip_edges()
	if t.begins_with("rgb"):
		var inner := t.substr(t.find("(") + 1).trim_suffix(")")
		var parts := inner.split(",", false)
		if parts.size() >= 3:
			var a := float(parts[3]) if parts.size() >= 4 else 1.0
			return Color(float(parts[0]) / 255.0, float(parts[1]) / 255.0, float(parts[2]) / 255.0, a)
		return fallback
	return Color.from_string(t, fallback)


# --- utilitários de desenho (estáticos, reutilizáveis) -----------------------------------------------

## Texto centrado em `center` (centro visual da caixa de maiúsculas), com contorno opcional.
static func draw_text_centered(ci: CanvasItem, f: Font, text: String, center: Vector2, font_px: float,
		color: Color, outline: Color = Color(0, 0, 0, 0), outline_px: float = 0.0) -> void:
	if text == "":
		return
	var fs := maxi(1, roundi(font_px))
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var baseline := Vector2(center.x - w / 2.0, center.y + (f.get_ascent(fs) - f.get_descent(fs)) / 2.0)
	if outline.a > 0.0 and outline_px > 0.0:
		ci.draw_string_outline(f, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(1, roundi(outline_px)), outline)
	ci.draw_string(f, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


## [texto, tamanho] que cabe em max_w: encolhe de max_px até min_px; se não couber, abrevia os
## primeiros nomes ("Lucas Silva" -> "L. Silva") e, em último caso, corta com reticências.
static func fit_text(f: Font, text: String, max_w: float, max_px: float, min_px: float) -> Array:
	var px := max_px
	while px > min_px and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(1, roundi(px))).x > max_w:
		px -= 0.5
	px = maxf(px, min_px)
	var fs := maxi(1, roundi(px))
	if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= max_w:
		return [text, px]
	var words := text.split(" ", false)
	if words.size() > 1:
		var short := ""
		for i in words.size() - 1:
			short += words[i].substr(0, 1) + ". "
		short += words[words.size() - 1]
		if f.get_string_size(short, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= max_w:
			return [short, px]
		text = short
	while text.length() > 1 and f.get_string_size(text + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		text = text.substr(0, text.length() - 1)
	return [text + "…", px]


## Divide nome composto em 2 linhas (ou devolve 1 linha se for nome simples), como o
## quebrarNomeComposto do Card Studio: quebra manual com \n ou "/", preposição fica na 2ª linha.
static func split_composite_name(text: String) -> Array[String]:
	var cleaned := text.strip_edges()
	if cleaned.contains("\n"):
		var raw_lines := cleaned.split("\n", false)
		if raw_lines.size() > 1:
			var res: Array[String] = [raw_lines[0].strip_edges(), " ".join(raw_lines.slice(1)).strip_edges()]
			return res
		cleaned = raw_lines[0].strip_edges() if raw_lines.size() == 1 else ""
	if cleaned.contains("/"):
		var raw_parts := cleaned.split("/", false)
		if raw_parts.size() > 1:
			var res: Array[String] = [raw_parts[0].strip_edges(), " ".join(raw_parts.slice(1)).strip_edges()]
			return res
		cleaned = raw_parts[0].strip_edges() if raw_parts.size() == 1 else ""
	var words := cleaned.split(" ", false)
	if words.size() <= 1:
		var res: Array[String] = []
		if cleaned != "":
			res.append(cleaned)
		return res
	if words.size() == 2:
		var res: Array[String] = [words[0], words[1]]
		return res
	var prepos := ["DE", "DO", "DA", "DOS", "DAS", "E", "DEL", "DI", "VON", "VAN"]
	if words.size() == 3:
		if prepos.has(words[1].to_upper()):
			var res: Array[String] = [words[0], words[1] + " " + words[2]]
			return res
		var res: Array[String] = [words[0] + " " + words[1], words[2]]
		return res
	var mid := int(ceili(float(words.size()) / 2.0))
	var res: Array[String] = [" ".join(words.slice(0, mid)), " ".join(words.slice(mid))]
	return res


## Estrela de 5 pontas preenchida com contorno.
static func draw_star(ci: CanvasItem, center: Vector2, r: float, fill: Color, line: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(center + Vector2(cos(a), sin(a)) * rr)
	ci.draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, line, width, true)


## Camada de desenho por cima de tudo (textos e selos).
class Overlay:
	extends Control
	var card_ref: StickerCard = null

	func _draw() -> void:
		if card_ref != null:
			card_ref._draw_overlay(self)
