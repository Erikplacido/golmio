class_name UiFrames
extends RefCounted
## Peças de interface pintadas (visuais/ui/ui_template.psd -> "Exportar UI.command" ->
## assets/ui/<nome>@2x.png + ui_frames.json). Medidas e regras: visuais/ui/ui_manifest.jsxinc.
##
## - frame(): moldura 9-slice como StyleBox. A arte é @2x: os cantos são desenhados na metade do
##   tamanho, para ficarem com a espessura certa e nítidos em telas densas. `tint` multiplica o
##   preenchimento branco (o contorno e a sombra pretos continuam pretos).
## - piece(): peça inteira (interruptor, check...) já reduzida ao tamanho lógico.
## - has(): a peça existe? Sem ela, DesignTokens usa os estilos desenhados por código.

const DIR := "res://assets/ui/"
const MANIFEST := "res://assets/ui/ui_frames.json"

static var _manifest: Dictionary = {}
static var _loaded := false
static var _textures := {}
static var _pieces := {}


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(MANIFEST):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if parsed is Dictionary:
		_manifest = parsed


static func info(name: String) -> Dictionary:
	_load()
	return _manifest.get("items", {}).get(name, {})


static func has(name: String) -> bool:
	return not info(name).is_empty() and ResourceLoader.exists(_path(name))


static func art_scale() -> float:
	_load()
	return float(_manifest.get("scale", 2))


static func texture(name: String) -> Texture2D:
	if not _textures.has(name):
		_textures[name] = load(_path(name)) if has(name) else null
	return _textures[name]


## Moldura 9-slice; null se a peça não existe.
static func frame(name: String, tint := Color.WHITE) -> StyleBox:
	var i := info(name)
	var tex := texture(name)
	if tex == null or str(i.get("kind", "")) != "frame":
		return null
	var sb := NineSliceStyle.new()
	sb.texture = tex
	var s: Array = i.get("slice", [0, 0, 0, 0])
	sb.slice = Vector4(s[0], s[1], s[2], s[3])
	sb.scale = 1.0 / art_scale()
	sb.modulate = tint if bool(i.get("tint", false)) else Color.WHITE
	if bool(i.get("tint", false)):
		sb.fallback = _flat_like(tint)
	var c: Array = i.get("content", [0, 0, 0, 0])
	sb.content_margin_left = c[0]
	sb.content_margin_top = c[1]
	sb.content_margin_right = c[2]
	sb.content_margin_bottom = c[3]
	return sb


## Versão desenhada por código, para componentes menores que a moldura (ver NineSliceStyle).
static func _flat_like(tint: Color) -> StyleBoxFlat:
	var f := StyleBoxFlat.new()
	f.bg_color = tint
	f.border_color = DesignTokens.COLOR_INK
	f.set_border_width_all(DesignTokens.BORDER_WIDTH)
	f.set_corner_radius_all(int(DesignTokens.RADIUS_MD))
	f.shadow_color = DesignTokens.COLOR_INK
	f.shadow_size = 1
	f.shadow_offset = Vector2(1, 2)
	return f


## Peça inteira no tamanho lógico (metade da arte @2x); null se não existe.
static func piece(name: String) -> Texture2D:
	if _pieces.has(name):
		return _pieces[name]
	var tex := texture(name)
	var out: Texture2D = null
	if tex:
		var img := tex.get_image()
		if img:
			if img.is_compressed():
				img.decompress()
			var k := 1.0 / art_scale()
			img.resize(maxi(1, roundi(img.get_width() * k)), maxi(1, roundi(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
			out = ImageTexture.create_from_image(img)
	_pieces[name] = out
	return out


## Fundo de papel para telas: textura ui_papel repetida (no tamanho lógico) ou, sem ela, a cor do
## papel. Ocupa o pai inteiro e não pega cliques.
static func paper_background() -> Control:
	var tex := piece("ui_papel")
	var c: Control
	if tex:
		var r := TextureRect.new()
		r.texture = tex
		r.stretch_mode = TextureRect.STRETCH_TILE
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		c = r
	else:
		var cr := ColorRect.new()
		cr.color = DesignTokens.COLOR_BG_APP
		c = cr
	c.name = "PaperBackground"
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func _path(name: String) -> String:
	return "%s%s@%dx.png" % [DIR, name, int(art_scale())]


## StyleBox 9-slice com escala: o Godot desenha os cantos de um StyleBoxTexture no tamanho da
## textura; aqui o desenho é feito numa área `1/scale` maior com transformação de `scale`.
class NineSliceStyle:
	extends StyleBox
	var texture: Texture2D
	var slice := Vector4.ZERO      # esq, topo, dir, base (px da textura)
	var scale := 0.5
	var modulate := Color.WHITE
	## Desenhado quando a área não comporta os cantos (botão compacto): encolher a arte comprime o
	## miolo a menos de 1 px e a média dos pixels vira um fio cinza.
	var fallback: StyleBox

	func _draw(to_canvas_item: RID, rect: Rect2) -> void:
		if texture == null:
			return
		var need := Vector2(slice.x + slice.z, slice.y + slice.w) * scale
		if fallback and (rect.size.x < need.x + 1.0 or rect.size.y < need.y + 1.0):
			fallback.draw(to_canvas_item, rect)
			return
		# Sem versão por código (peças sem cor): os cantos encolhem junto, em vez de se sobreporem.
		var k := scale
		if slice.x + slice.z > 0.0:
			k = minf(k, rect.size.x / (slice.x + slice.z + 2.0))   # +2: miolo nunca chega a zero
		if slice.y + slice.w > 0.0:
			k = minf(k, rect.size.y / (slice.y + slice.w + 2.0))
		k = maxf(k, 0.01)
		var big := rect.size / k
		RenderingServer.canvas_item_add_set_transform(to_canvas_item, Transform2D(0.0, Vector2(k, k), 0.0, rect.position))
		_nine(to_canvas_item, big)
		RenderingServer.canvas_item_add_set_transform(to_canvas_item, Transform2D.IDENTITY)


	## Os 9 pedaços, em px da textura. O miolo (e as bordas) nunca é espremido: se o espaço é
	## menor que o miolo da arte, usa só a parte central dele em 1:1 (espremer gera fios cinza
	## com os mipmaps); se é maior, estica.
	func _nine(item: RID, size: Vector2) -> void:
		var ts := texture.get_size()
		var rid := texture.get_rid()
		var dx := [0.0, slice.x, size.x - slice.z, size.x]
		var dy := [0.0, slice.y, size.y - slice.w, size.y]
		var sx := _src_axis(ts.x, slice.x, slice.z, dx[2] - dx[1])
		var sy := _src_axis(ts.y, slice.y, slice.w, dy[2] - dy[1])
		for j in 3:
			for i in 3:
				var dst := Rect2(dx[i], dy[j], dx[i + 1] - dx[i], dy[j + 1] - dy[j])
				var src := Rect2(sx[i], sy[j], sx[i + 1] - sx[i], sy[j + 1] - sy[j])
				if dst.size.x <= 0.0 or dst.size.y <= 0.0 or src.size.x <= 0.0 or src.size.y <= 0.0:
					continue
				RenderingServer.canvas_item_add_texture_rect_region(item, dst, rid, src, modulate)

	## Limites de origem [0, a, b, total] num eixo, dado o tamanho de destino do miolo.
	func _src_axis(total: float, lo: float, hi: float, dest_center: float) -> Array:
		var center := total - lo - hi
		if dest_center >= center or center <= 0.0:
			return [0.0, lo, total - hi, total]
		var cut := (center - maxf(dest_center, 0.0)) / 2.0
		return [0.0, lo + cut, total - hi - cut, total]
