class_name PortraitRenderer
extends Node2D
## Retrato do atleta na figurinha (docs/RETRATOS.md 4.5): monta as camadas da receita visual
## (dna.face, só IDs) com PortraitLayout, na ordem oficial de Montagem.compor(), e veste o
## uniforme do clube atual (kit, estado do clube, não DNA) com o shader uniform_collar.gdshader.
##
## Uso:
##   var r := PortraitRenderer.new()
##   r.fit_size = Vector2(240, 320)          # opcional: cabe e centraliza em Rect2(0, 0, 240, 320)
##   r.setup(athlete.dna.face, PortraitRenderer.kit_for_club(club))
##   add_child(r)
##   ...
##   r.set_kit(novo_kit)                       # transferência: só o uniforme muda
##
## Estrutura: Content (Node2D, transformação de enquadramento) com um LayerNode por camada, cada
## um com transform = camada.transform e desenhando a textura esticada em Rect2(0, 0, w, h)
## (dimensões ORIGINAIS). Tronco e braços usam ShaderMaterial (modo 0 e 1); a gola PNG é filha do
## tronco (modo 2) no retângulo de PortraitLayout.collar_rect(); a sigla do escudo é um CrestLabel
## filho do tronco. Peça "" não desenha; ID desconhecido gera aviso e é ignorado.

const SHADER_PATH := "res://presentation/portrait/uniform_collar.gdshader"
const MODE_SHIRT := 0
const MODE_SLEEVE := 1
const MODE_COLLAR := 2
## Largura do contorno de sigla relativa ao corpo da letra (engrossa a fonte padrão).
const CREST_TEXT_OUTLINE := 0.08

static var _shader: Shader = null

## Se > 0, escala e centraliza o retrato para caber em Rect2(Vector2.ZERO, fit_size).
var fit_size: Vector2 = Vector2.ZERO:
	set(value):
		fit_size = value
		_apply_fit()
## > 0 fixa a escala de análise do uniforme (render_scale do shader); 0 = automática pela tela
## (como a `escala` que uniforme.html passa a Montagem.vestir).
var uniform_render_scale: float = 0.0:
	set(value):
		uniform_render_scale = value
		_apply_kit()
## Recolorir a gola PNG: 0 = faixas do contrato (L < 0.35 nanquim preservado, < 0.65 friso,
## resto gola); 1 = pesos contínuos de Montagem.colorirGola (paridade exata com a web).
var collar_blend_mode: int = 0:
	set(value):
		collar_blend_mode = value
		_apply_kit()
## Suavização das bordas das faixas da gola (modo 0).
var collar_band_softness: float = 0.03:
	set(value):
		collar_band_softness = value
		_apply_kit()
## Receita e kit atuais (o kit já normalizado por UniformMaps.normalize_kit).
var face: Dictionary = {}
var kit: Dictionary = {}
var catalog: PortraitCatalog = null
## Saída de PortraitLayout.build() para a receita atual.
var layers: Array = []

var _content: Node2D = null
var _bounds: Rect2 = Rect2()
var _layer_nodes: Array = []


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## Monta o retrato. kit vazio = KIT_PADRAO; catalog nulo = PortraitCatalog.shared().
func setup(p_face: Dictionary, p_kit: Dictionary = {}, p_catalog: PortraitCatalog = null) -> void:
	catalog = p_catalog if p_catalog != null else PortraitCatalog.shared()
	face = p_face.duplicate(true)
	kit = UniformMaps.normalize_kit(p_kit)
	_rebuild()


## Troca só o uniforme (cores, estampa, gola, escudo), sem remontar o rosto.
func set_kit(p_kit: Dictionary) -> void:
	kit = UniformMaps.normalize_kit(p_kit)
	_apply_kit()


## Caixa do conteúdo desenhado no espaço local deste nó (já com o enquadramento de fit_size).
func content_rect() -> Rect2:
	if _content == null:
		return Rect2()
	return _content.transform * _bounds


## Caixa do conteúdo no espaço da cabeça (antes do enquadramento).
func content_bounds() -> Rect2:
	return _bounds


## Nós das camadas na ordem de desenho (um por camada de `layers`).
func layer_nodes() -> Array:
	return _layer_nodes.duplicate()


## Primeiro nó da camada com esse slot (e lado, se dado); null se não existe.
func find_layer(slot: String, side: String = "") -> Node2D:
	for n in _layer_nodes:
		var layer: Dictionary = n.layer
		if layer.slot == slot and (side == "" or layer.side == side):
			return n
	return null


## Kit do clube: club.ext["club_identity"].kit, ou KIT_PADRAO com as cores do clube
## [primary, secondary, "#1d1d1b"] quando a identidade do clube não definiu um.
static func kit_for_club(club: Club) -> Dictionary:
	if club == null:
		return UniformMaps.normalize_kit({})
	var identity: Variant = club.ext.get("club_identity", {})
	if identity is Dictionary and identity.get("kit") is Dictionary and not (identity["kit"] as Dictionary).is_empty():
		return UniformMaps.normalize_kit(identity["kit"])
	var base := UniformMaps.KIT_DEFAULT.duplicate(true)
	base["colors"] = [
		str(club.colors.get("primary", UniformMaps.KIT_DEFAULT.colors[0])),
		str(club.colors.get("secondary", UniformMaps.KIT_DEFAULT.colors[1])),
		"#1d1d1b",
	]
	if club.short_name != "":
		base["sigla"] = club.short_name.to_upper().substr(0, 5)
	return UniformMaps.normalize_kit(base)


static func uniform_shader() -> Shader:
	if _shader == null:
		_shader = load(SHADER_PATH) as Shader
	return _shader


# --- montagem ------------------------------------------------------------------------------------

func _rebuild() -> void:
	if _content != null:
		remove_child(_content)
		_content.free()
	_content = Node2D.new()
	_content.name = "Content"
	add_child(_content)
	_layer_nodes.clear()
	layers = PortraitLayout.build(catalog, face)
	_bounds = PortraitLayout.bounds(layers)
	for layer in layers:
		var node := LayerNode.new()
		node.layer = layer
		node.name = layer.slot if layer.side == "" else "%s_%s" % [layer.slot, layer.side]
		node.transform = layer.transform
		node.size = Vector2(layer.w, layer.h)
		node.texture = catalog.texture(layer.slot, layer.id)
		_content.add_child(node)
		_layer_nodes.append(node)
	_apply_kit()
	_apply_fit()


func _apply_fit() -> void:
	if _content == null:
		return
	if fit_size.x > 0.0 and fit_size.y > 0.0 and _bounds.size.x > 0.0 and _bounds.size.y > 0.0:
		var s := minf(fit_size.x / _bounds.size.x, fit_size.y / _bounds.size.y)
		var offset := (fit_size - _bounds.size * s) / 2.0 - _bounds.position * s
		_content.transform = Transform2D(Vector2(s, 0.0), Vector2(0.0, s), offset)
	else:
		_content.transform = Transform2D.IDENTITY


## Aplica o kit: materiais do tronco e dos braços, gola PNG e sigla do escudo.
func _apply_kit() -> void:
	if _content == null or catalog == null:
		return
	var body_node := find_layer("body")
	var body_id := str(face.get("body", ""))
	var body_scale := 1.0
	if body_node != null:
		body_scale = _scale_of(body_node.transform)
		var cal := catalog.body_calibration(body_id)
		var maps := UniformMaps.for_part(catalog, "body", body_id)
		if maps != null and not maps.is_empty():
			var params := maps.shirt_params(kit, cal)
			params["density_ratio"] = 1.0
			params["render_scale"] = uniform_render_scale
			body_node.material = _material_with(body_node.material, params)
		_apply_crest(body_node, cal)
		_apply_collar(body_node, cal)
	for side in ["left", "right"]:
		var arm_node := find_layer("arm", side)
		if arm_node == null:
			continue
		var arm_id := str(face.get("arm", ""))
		var arm_maps := UniformMaps.for_part(catalog, "arm", arm_id)
		if arm_maps == null or arm_maps.is_empty():
			continue
		var arm_params := arm_maps.sleeve_params(kit, catalog.arm_calibration(arm_id))
		arm_params["density_ratio"] = _scale_of(arm_node.transform) / body_scale if body_scale > 0.0 else 1.0
		arm_params["render_scale"] = uniform_render_scale
		arm_node.material = _material_with(arm_node.material, arm_params)


func _apply_collar(body_node: LayerNode, cal: Dictionary) -> void:
	var old := body_node.get_node_or_null("collar")
	var collar_id := catalog.collar_id(str(kit.get("collar", "")))
	var tex: Texture2D = catalog.texture("collar", collar_id) if collar_id != "" else null
	if tex == null:
		if old != null:
			body_node.remove_child(old)
			old.free()
		return
	var node: LayerNode = old if old != null else LayerNode.new()
	if old == null:
		node.name = "collar"
		body_node.add_child(node)
	var collar_size := catalog.size_of("collar", collar_id)
	var collar_calib := catalog.collar_calibration(collar_id)
	var rect := PortraitLayout.collar_rect(cal.get("collar", {}), body_node.size, collar_size, collar_calib)
	node.layer = {"slot": "collar", "id": collar_id, "side": "", "w": collar_size.x, "h": collar_size.y}
	node.texture = tex
	node.size = collar_size
	var s := rect.size.x / collar_size.x
	node.transform = Transform2D(Vector2(s, 0.0), Vector2(0.0, s), rect.position)
	var params := UniformMaps.collar_params(kit)
	params["collar_blend_mode"] = collar_blend_mode
	params["band_softness"] = collar_band_softness
	node.material = _material_with(node.material, params)
	node.queue_redraw()


func _apply_crest(body_node: LayerNode, cal: Dictionary) -> void:
	var old := body_node.get_node_or_null("crest_label") as CrestLabel
	var crest: Dictionary = cal.get("crest", {})
	var sigla := str(kit.get("sigla", "") if kit.get("sigla") != null else "").to_upper().substr(0, 5)
	var show := UniformMaps.truthy(kit.get("crest")) and crest.get("center") is Array and sigla != ""
	if not show:
		if old != null:
			body_node.remove_child(old)
			old.free()
		return
	var label: CrestLabel = old if old != null else CrestLabel.new()
	if old == null:
		label.name = "crest_label"
		body_node.add_child(label)
		body_node.move_child(label, 0)   # sob a gola PNG, como no canvas de vestir()
	var w := body_node.size.x
	var h := body_node.size.y
	var s := float(crest.get("size", 0.0)) * w
	var center: Array = crest.center
	label.text = sigla
	label.color = UniformMaps.kit_color(kit, 1)
	label.font_px = s * (0.2 if sigla.length() > 3 else 0.27)
	label.position = Vector2(float(center[0]) * w, float(center[1]) * h + s * 0.05)
	# A sigla só aparece se o escudo cair dentro da camisa (abaixo da linha da gola).
	label.visible = label.position.y >= UniformMaps.collar_line_y(cal.get("collar", {}), w, h, label.position.x)
	label.queue_redraw()


static func _material_with(current: Material, params: Dictionary) -> ShaderMaterial:
	var mat := current as ShaderMaterial
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = uniform_shader()
	for key in params:
		mat.set_shader_parameter(key, params[key])
	return mat


static func _scale_of(t: Transform2D) -> float:
	return sqrt(absf(t.determinant()))


## Uma camada do retrato: desenha a textura esticada em Rect2(0, 0, w, h) (dimensões originais).
class LayerNode:
	extends Node2D
	## {slot, id, side, transform, w, h} de PortraitLayout (a gola não tem transform).
	var layer: Dictionary = {}
	var texture: Texture2D = null
	var size: Vector2 = Vector2.ZERO

	func _draw() -> void:
		if texture != null and size.x > 0.0 and size.y > 0.0:
			draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)


## Sigla do escudo (desenharEscudo: fonte grossa, cor secundária, centrada em crest + 5% de s).
class CrestLabel:
	extends Node2D
	var text: String = ""
	var color: Color = Color.WHITE
	var font_px: float = 16.0

	func _draw() -> void:
		if text == "" or font_px < 1.0:
			return
		var font := DesignTokens.font(true)
		var fs := maxi(1, roundi(font_px))
		var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var baseline := Vector2(-size.x / 2.0, (font.get_ascent(fs) - font.get_descent(fs)) / 2.0)
		var outline := maxi(1, roundi(fs * PortraitRenderer.CREST_TEXT_OUTLINE))
		draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, color)
		draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
