class_name UniformMaps
extends RefCounted
## Mapas de análise de um torso ou braço para vestir o uniforme do clube (docs/RETRATOS.md 4.1.1).
## Porta de Montagem.analisar(), detectarCorpo(), calibracaoCorpo(), calibracaoBraco(),
## linhaGola(), normalizarKit() e corPadrao() de visuais/montagem.js. O shader
## uniform_collar.gdshader faz o resto de Montagem.vestir() por pixel.
##
## MAPAS PRÉ-CALCULADOS: o exportador (visuais/exportar_catalogo.py) já grava os mapas de cada
## torso e braço do catálogo (catalog.parts[slot][id].maps: textura RGBA no formato abaixo + w, h,
## median e bbox). for_part() usa esses mapas: só carrega a textura, sem laço por pixel na thread
## principal (a análise em GDScript custava ~200 ms por peça e travava a abertura do pacote). A
## porta Python é a mesma de analyze() e dá o mesmo resultado pixel a pixel na mesma entrada.
## analyze() continua sendo o caminho para peças sem mapas (catálogo antigo, catálogo montado em
## memória, imagens de teste).
##
## A análise roda uma vez por textura numa resolução reduzida (ANALYSIS_WIDTH px de largura, sem
## ampliar) e fica em cache estático. Mapas:
##   mask       alfa > 128 (silhueta)
##   lum        luminância 0.299R + 0.587G + 0.114B (0..1)
##   lum_blur   luminância suavizada SÓ dentro da silhueta (Lb): 4 passes de caixa de raio
##              max(2, round(W * 0.045)) sobre L·máscara e sobre a máscara, dividindo um pelo outro
##   median     percentil 60 de Lb dentro da silhueta, no mínimo 0.2
##   dist       distância (em pixels do mapa, 4-vizinhança, duas passagens) até fora da silhueta
##   bbox       caixa da silhueta [x0, y0, x1, y1) em pixels do mapa
##   row_left/row_right  primeira e última coluna da silhueta em cada linha (-1 = linha vazia)
##
## Textura para o shader (texture(), RGBA8, mesmo tamanho do mapa, amostrada com filtro linear):
##   R = lum_blur (0..1)
##   G = dist em pixels do mapa / 255 (satura em 255 px; o shader só usa distâncias pequenas)
##   B = mask (1 dentro da silhueta)
##   A = 1
## O shader converte pixels do mapa em pixels da imagem original com map_to_source = w / largura
## do mapa, e daí em "pixels de análise" de Montagem.vestir multiplicando por render_scale.

const ANALYSIS_WIDTH := 360
const MASK_ALPHA := 128
const MEDIAN_PERCENTILE := 0.6
const MEDIAN_MIN := 0.2
const BLUR_RADIUS_FACTOR := 0.045
const MAX_CACHE := 48

## Padrões de estampa na ordem do uniforme `pattern` do shader (Montagem.PADROES).
const PATTERNS := [
	"lisa", "listras_verticais", "listras_horizontais", "faixa_diagonal",
	"faixa_horizontal", "faixa_vertical", "metades", "xadrez",
	"listras_diagonais", "chevron", "duas_faixas", "losangos",   # desbloqueáveis (Cosmetics)
]
## Montagem.KIT_PADRAO. As cores de gola, manga e punho são índices em `colors`
## (0 = principal, 1 = secundária, 2 = detalhe).
const KIT_DEFAULT := {
	"pattern": "listras_verticais",
	"colors": ["#c8102e", "#ffffff", "#1d1d1b"],
	"count": 3,
	"width": 0.16,
	"collar": "Caricatura retrô com gola redonda.png",
	"collar_color": 2,
	"collar_trim_color": 1,
	"sleeve_color": 0,
	"cuff": true,
	"cuff_color": 1,
	"cuff_width": 0.032,
	"cuff_trim": false,
	"cuff_trim_color": 2,
	"crest": true,
	"sigla": "FTB",
}
## Campos que normalizarKit() repõe quando vêm nulos.
const KIT_NULL_DEFAULTS := ["collar", "collar_color", "collar_trim_color", "cuff", "cuff_width", "cuff_trim", "cuff_trim_color"]
## Linha de corte da manga quando o braço não foi calibrado (Montagem.calibracaoBraco).
const SLEEVE_DEFAULT := {"a": [0.0, 0.2], "b": [1.0, 0.2]}

static var _cache: Dictionary = {}
static var _cache_order: Array = []

var width: int = 0
var height: int = 0
## Tamanho ORIGINAL da peça (w, h) em pixels.
var source_size: Vector2 = Vector2.ZERO
var mask: PackedByteArray = PackedByteArray()
var lum: PackedFloat32Array = PackedFloat32Array()
var lum_blur: PackedFloat32Array = PackedFloat32Array()
var dist: PackedInt32Array = PackedInt32Array()
var median: float = 0.8
var bbox: Rect2i = Rect2i()
var row_left: PackedInt32Array = PackedInt32Array()
var row_right: PackedInt32Array = PackedInt32Array()
## true: veio pronto do catálogo (from_precomputed). Os arrays por pixel (mask, lum, lum_blur,
## dist, row_left, row_right) só são decodificados da textura se alguém pedir (detect_body,
## to_image); o desenho usa só a textura, median e bbox.
var precomputed: bool = false
var _texture: Texture2D = null


# --- construção ---------------------------------------------------------------------------------

## Analisa uma imagem. analysis_width limita a largura do mapa (nunca amplia); <= 0 usa a largura
## da imagem. source_size é o tamanho ORIGINAL da peça (padrão: o da imagem).
static func analyze(image: Image, p_source_size: Vector2 = Vector2.ZERO, analysis_width: int = ANALYSIS_WIDTH) -> UniformMaps:
	var maps := UniformMaps.new()
	if image == null or image.is_empty():
		return maps
	var img := image.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	if img.has_mipmaps():
		img.clear_mipmaps()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var iw := img.get_width()
	var ih := img.get_height()
	var w := iw if analysis_width <= 0 else mini(analysis_width, iw)
	var h := maxi(1, roundi(float(ih) * float(w) / float(iw)))
	if w != iw or h != ih:
		img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	maps.source_size = p_source_size if p_source_size.x > 0.0 and p_source_size.y > 0.0 else Vector2(iw, ih)
	maps._compute(img.get_data(), w, h)
	return maps


## Mapas já calculados pelo exportador. info = catalog.parts[slot][id].maps ({texture, w, h,
## median, bbox: [x0, y0, x1, y1]}); tex = a textura desses mapas. null se a textura não bate com
## info (quem chama cai em analyze()).
static func from_precomputed(tex: Texture2D, info: Dictionary, p_source_size: Vector2) -> UniformMaps:
	var w := int(info.get("w", 0))
	var h := int(info.get("h", 0))
	var box: Variant = info.get("bbox")
	if tex == null or w <= 0 or h <= 0 or tex.get_width() != w or tex.get_height() != h \
			or not (box is Array) or (box as Array).size() < 4:
		return null
	var maps := UniformMaps.new()
	maps.precomputed = true
	maps.width = w
	maps.height = h
	maps.source_size = p_source_size if p_source_size.x > 0.0 and p_source_size.y > 0.0 else Vector2(w, h)
	maps.median = maxf(MEDIAN_MIN, float(info.get("median", 0.8)))
	var x0 := int(box[0])
	var y0 := int(box[1])
	maps.bbox = Rect2i(x0, y0, int(box[2]) - x0, int(box[3]) - y0)
	maps._texture = tex
	return maps


## Mapas da peça do catálogo (slot "body" ou "arm"), com cache estático. Usa os mapas
## pré-calculados do catálogo quando existem (e analysis_width é o padrão); senão analisa a textura.
static func for_part(catalog: PortraitCatalog, slot: String, id: String, analysis_width: int = ANALYSIS_WIDTH) -> UniformMaps:
	if analysis_width == ANALYSIS_WIDTH:
		var pre := _precomputed_for(catalog, slot, id)
		if pre != null:
			return pre
	var tex := catalog.texture(slot, id)
	if tex == null:
		return null
	return for_texture(tex, catalog.size_of(slot, id), analysis_width)


static func _precomputed_for(catalog: PortraitCatalog, slot: String, id: String) -> UniformMaps:
	var info := catalog.maps_info(slot, id)
	var path := str(info.get("texture", ""))
	if path == "":
		return null
	var source := catalog.size_of(slot, id)
	var key := "pre|%s|%s|%d" % [path, str(info.get("hash", "")), int(source.x)]
	if _cache.has(key):
		return _cache[key]
	if not ResourceLoader.exists(path):
		return null
	var maps := from_precomputed(load(path) as Texture2D, info, source)
	if maps == null:
		push_warning("UniformMaps: mapas de %s/%s não batem com o catálogo; analisando a textura" % [slot, id])
	_remember(key, maps)   # null também fica no cache: avisa e tenta carregar uma vez só
	return maps


## Mapas de uma textura (cache estático por textura + largura de análise).
static func for_texture(tex: Texture2D, p_source_size: Vector2, analysis_width: int = ANALYSIS_WIDTH) -> UniformMaps:
	if tex == null:
		return null
	var key := "%s|%d|%d" % [tex.resource_path if tex.resource_path != "" else str(tex.get_instance_id()), analysis_width, int(p_source_size.x)]
	if _cache.has(key):
		return _cache[key]
	var maps := analyze(tex.get_image(), p_source_size, analysis_width)
	_remember(key, maps)
	return maps


static func _remember(key: String, maps: UniformMaps) -> void:
	_cache[key] = maps
	_cache_order.append(key)
	while _cache_order.size() > MAX_CACHE:
		_cache.erase(_cache_order.pop_front())


static func clear_cache() -> void:
	_cache.clear()
	_cache_order.clear()


func is_empty() -> bool:
	return width == 0 or height == 0


## Mapas pré-calculados: decodifica os arrays por pixel da textura (só quando alguém precisa deles;
## o desenho não precisa). lum fica igual a lum_blur (a textura não guarda a luminância crua).
func _ensure_pixels() -> void:
	if not precomputed or mask.size() == width * height or _texture == null:
		return
	var img := _texture.get_image()
	if img == null or img.is_empty():
		return
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var px := img.get_data()
	var n := width * height
	mask.resize(n)
	lum.resize(n)
	lum_blur.resize(n)
	dist.resize(n)
	for i in n:
		var j := i * 4
		var lb := px[j] / 255.0
		lum_blur[i] = lb
		lum[i] = lb
		dist[i] = px[j + 1]
		mask[i] = 1 if px[j + 2] > 127 else 0
	row_left.resize(height)
	row_right.resize(height)
	for yy in height:
		var left := -1
		var right := -1
		var base := yy * width
		for xx in width:
			if mask[base + xx]:
				if left < 0:
					left = xx
				right = xx
		row_left[yy] = left
		row_right[yy] = right


func _compute(px: PackedByteArray, w: int, h: int) -> void:
	width = w
	height = h
	var n := w * h
	mask.resize(n)
	lum.resize(n)
	var lum_masked := PackedFloat32Array()
	lum_masked.resize(n)
	var alpha_f := PackedFloat32Array()
	alpha_f.resize(n)
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for i in n:
		var j := i * 4
		var l := (0.299 * px[j] + 0.587 * px[j + 1] + 0.114 * px[j + 2]) / 255.0
		lum[i] = l
		if px[j + 3] > MASK_ALPHA:
			mask[i] = 1
			lum_masked[i] = l
			alpha_f[i] = 1.0
			var xx := i % w
			var yy := i / w
			x0 = mini(x0, xx)
			x1 = maxi(x1, xx)
			y0 = mini(y0, yy)
			y1 = maxi(y1, yy)
		else:
			mask[i] = 0
	# Suaviza só dentro da silhueta: o fundo transparente não escurece a borda.
	var r := maxi(2, roundi(w * BLUR_RADIUS_FACTOR))
	var blurred := _blur2(lum_masked, alpha_f, w, h, r)
	var bl: PackedFloat32Array = blurred[0]
	var ba: PackedFloat32Array = blurred[1]
	lum_blur.resize(n)
	var hist := PackedInt32Array()
	hist.resize(256)
	for i in n:
		var lb: float = bl[i] / ba[i] if ba[i] > 0.01 else lum[i]
		lum_blur[i] = lb
		if mask[i]:
			hist[mini(255, roundi(lb * 255.0))] += 1
	var total := 0
	for k in 256:
		total += hist[k]
	var acc := 0
	var med := 0.8
	for k in 256:
		acc += hist[k]
		if acc >= total * MEDIAN_PERCENTILE:
			med = k / 255.0
			break
	median = maxf(MEDIAN_MIN, med)
	row_left.resize(h)
	row_right.resize(h)
	for yy in h:
		var left := -1
		var right := -1
		var base := yy * w
		for xx in w:
			if mask[base + xx]:
				if left < 0:
					left = xx
				right = xx
		row_left[yy] = left
		row_right[yy] = right
	dist = _distance(mask, w, h)
	bbox = Rect2i(0, 0, w, h) if x1 < 0 else Rect2i(x0, y0, x1 + 1 - x0, y1 + 1 - y0)


## Montagem.distancia(): distância até fora da silhueta, duas passagens (4-vizinhança).
static func _distance(m: PackedByteArray, w: int, h: int) -> PackedInt32Array:
	var d := PackedInt32Array()
	d.resize(w * h)
	for y in h:
		for x in w:
			var i := y * w + x
			if not m[i]:
				continue
			var up := d[i - w] if y > 0 else 0
			var lf := d[i - 1] if x > 0 else 0
			d[i] = mini(up, lf) + 1
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := y * w + x
			if not d[i]:
				continue
			var dn := d[i + w] if y < h - 1 else 0
			var rt := d[i + 1] if x < w - 1 else 0
			d[i] = mini(d[i], mini(dn, rt) + 1)
	return d


## Montagem.borrar() aplicado a dois mapas de uma vez: caixa de raio r, horizontal, vertical,
## horizontal, vertical, com a borda da imagem repetida.
static func _blur2(a: PackedFloat32Array, b: PackedFloat32Array, w: int, h: int, r: int) -> Array:
	var ta := _box_pass(a, b, w, h, r, true)
	var tb := _box_pass(ta[0], ta[1], w, h, r, false)
	var tc := _box_pass(tb[0], tb[1], w, h, r, true)
	return _box_pass(tc[0], tc[1], w, h, r, false)


static func _box_pass(a: PackedFloat32Array, b: PackedFloat32Array, w: int, h: int, r: int, horizontal: bool) -> Array:
	var oa := PackedFloat32Array()
	var ob := PackedFloat32Array()
	oa.resize(w * h)
	ob.resize(w * h)
	var n := w if horizontal else h
	var m := h if horizontal else w
	var stride := 1 if horizontal else w
	var div := float(2 * r + 1)
	for j in m:
		var base := j * w if horizontal else j
		var sa := 0.0
		var sb := 0.0
		for k in range(-r, r + 1):
			var idx := base + clampi(k, 0, n - 1) * stride
			sa += a[idx]
			sb += b[idx]
		for k in n:
			var idx := base + k * stride
			oa[idx] = sa / div
			ob[idx] = sb / div
			var add := base + mini(n - 1, k + r + 1) * stride
			var sub := base + maxi(0, k - r) * stride
			sa += a[add] - a[sub]
			sb += b[add] - b[sub]
	return [oa, ob]


# --- textura para o shader ----------------------------------------------------------------------

## Imagem RGBA8 com os mapas (R = lum_blur, G = dist/255, B = mask, A = 1).
func to_image() -> Image:
	if precomputed and _texture != null:
		var img := _texture.get_image()
		if img != null and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			return img
	var n := width * height
	var data := PackedByteArray()
	data.resize(n * 4)
	for i in n:
		var j := i * 4
		data[j] = clampi(roundi(lum_blur[i] * 255.0), 0, 255)
		data[j + 1] = mini(255, dist[i])
		data[j + 2] = 255 if mask[i] else 0
		data[j + 3] = 255
	return Image.create_from_data(maxi(1, width), maxi(1, height), false, Image.FORMAT_RGBA8, data) if n > 0 \
		else Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)


## Textura dos mapas para o shader (a pré-calculada, ou criada a partir dos arrays).
func texture() -> Texture2D:
	if _texture == null:
		_texture = ImageTexture.create_from_image(to_image())
	return _texture


## Pixels da imagem original por pixel do mapa.
func map_to_source() -> float:
	return source_size.x / float(width) if width > 0 else 1.0


## bbox em frações da imagem (x0, y0, x1, y1).
func bbox_fractions() -> Vector4:
	if is_empty():
		return Vector4(0, 0, 1, 1)
	return Vector4(float(bbox.position.x) / width, float(bbox.position.y) / height,
		float(bbox.end.x) / width, float(bbox.end.y) / height)


# --- detecção e calibração ----------------------------------------------------------------------

## Largura da silhueta na linha y (0 se vazia).
func row_width(y: int) -> int:
	_ensure_pixels()
	return 0 if row_left[y] < 0 else row_right[y] - row_left[y]


## Montagem.detectarCorpo(): gola, escudo e ombros achados na silhueta do torso, em frações.
func detect_body() -> Dictionary:
	if is_empty():
		return detect_body_fallback()
	_ensure_pixels()
	if row_left.size() != height:
		return detect_body_fallback()
	var w := float(width)
	var h := float(height)
	var bx0 := bbox.position.x
	var by0 := bbox.position.y
	var bx1 := bbox.end.x
	var by1 := bbox.end.y
	var max_w := 0
	for y in range(by0, by1):
		max_w = maxi(max_w, row_width(y))
	var shoulder := by0
	while shoulder < by1 - 1 and row_width(shoulder) < max_w * 0.55:
		shoulder += 1
	var y_neck := maxi(by0, shoulder - roundi(h * 0.025))
	var pe := float(row_left[y_neck])
	var pd := float(row_right[y_neck])
	if pe < 0.0 or pd - pe > max_w * 0.5:
		pe = w * 0.38
		pd = w * 0.62
	var cx := (pe + pd) / 2.0
	var y_sh := mini(by1 - 1, shoulder + roundi(h * 0.07))
	var oe := float(bx0 if row_left[y_sh] < 0 else row_left[y_sh])
	var od := float(bx1 if row_right[y_sh] < 0 else row_right[y_sh])
	return {
		"collar": {"left": _frac(pe, shoulder, w, h), "right": _frac(pd, shoulder, w, h),
			"depth": _frac(cx, shoulder + h * 0.055, w, h)[1]},
		"crest": {"center": _frac(cx + (od - oe) * 0.2, shoulder + h * 0.17, w, h),
			"size": _round4((od - oe) / w * 0.16)},
		"shoulders": {"left": _frac(oe + w * 0.015, y_sh, w, h), "right": _frac(od - w * 0.015, y_sh, w, h)},
	}


## O que detectarCorpo() devolve sem pixels (imagem vazia ou ausente).
static func detect_body_fallback() -> Dictionary:
	return {
		"collar": {"left": [0.38, 0.0], "right": [0.62, 0.0], "depth": 0.055},
		"crest": {"center": [0.7, 0.17], "size": 0.16},
		"shoulders": {"left": [0.015, 0.07], "right": [0.985, 0.07]},
	}


static func _frac(x: float, y: float, w: float, h: float) -> Array:
	return [_round4(x / w), _round4(y / h)]


static func _round4(v: float) -> float:
	return roundf(v * 10000.0) / 10000.0


## A calibração salva tem todos os campos (a detecção automática seria inútil)?
static func calibration_complete(saved: Dictionary) -> bool:
	var need := {"collar": ["left", "right", "depth"], "crest": ["center", "size"], "shoulders": ["left", "right"]}
	for group in need:
		var g: Variant = saved.get(group)
		if not (g is Dictionary):
			return false
		for key in need[group]:
			if not g.has(key) or g[key] == null:
				return false
	return true


## Montagem.calibracaoCorpo(): a calibração salva sobrepõe a detecção campo a campo.
static func merge_body_calibration(auto: Dictionary, saved: Dictionary) -> Dictionary:
	var out := {"calibrated": not saved.is_empty()}
	for group in ["collar", "crest", "shoulders"]:
		var merged := {}
		var a: Variant = auto.get(group, {})
		var s: Variant = saved.get(group, {})
		if a is Dictionary:
			merged.merge(a, true)
		if s is Dictionary:
			merged.merge(s, true)
		out[group] = merged
	return out


## Montagem.calibracaoBraco(): linha de corte da manga (a -> b, frações da imagem do braço).
static func merge_arm_calibration(saved: Dictionary) -> Dictionary:
	var sleeve := SLEEVE_DEFAULT.duplicate(true)
	var s: Variant = saved.get("sleeve", {})
	if s is Dictionary:
		sleeve.merge(s, true)
	return {"sleeve": sleeve, "calibrated": s is Dictionary and not s.is_empty()}


## Montagem.linhaGola(): altura da linha da gola na coluna x (mesmas unidades de w e h).
static func collar_line_y(collar: Dictionary, w: float, h: float, x: float) -> float:
	var xl := float(collar.left[0]) * w
	var yl := float(collar.left[1]) * h
	var xr := float(collar.right[0]) * w
	var yr := float(collar.right[1]) * h
	var bottom := float(collar.depth) * h
	var cy := 2.0 * bottom - (yl + yr) / 2.0
	if x <= xl:
		return yl
	if x >= xr:
		return yr
	var t := (x - xl) / (xr - xl)
	return (1.0 - t) * (1.0 - t) * yl + 2.0 * t * (1.0 - t) * cy + t * t * yr


# --- kit ------------------------------------------------------------------------------------------

## Montagem.normalizarKit(): completa o kit com KIT_DEFAULT e garante três cores.
static func normalize_kit(kit: Dictionary) -> Dictionary:
	var k := KIT_DEFAULT.duplicate(true)
	for key in kit:
		k[str(key)] = kit[key]
	var colors: Array = []
	if k.get("colors") is Array:
		colors = (k["colors"] as Array).slice(0, 3)
	while colors.size() < 3:
		colors.append(KIT_DEFAULT.colors[colors.size()])
	k["colors"] = colors
	for key in KIT_NULL_DEFAULTS:
		if k.get(key) == null:
			k[key] = KIT_DEFAULT[key]
	return k


## Índice de padrão para o shader (desconhecido = lisa, como o default de corPadrao).
static func pattern_code(pattern: Variant) -> int:
	return maxi(0, PATTERNS.find(str(pattern)))


## Índice de cor válido (0..2) ou -1 (o JS cai em `cores[i] || cores[0]`, ou no padrão da gola).
static func color_index_or_invalid(v: Variant) -> int:
	var f := NAN
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		f = float(v)
	elif v is String and (v as String).is_valid_float():
		f = (v as String).to_float()
	if is_finite(f) and f == floorf(f) and f >= 0.0 and f <= 2.0:
		return int(f)
	return -1


## Índice de cor válido (0..2); fora disso vale a principal (`cores[i] || cores[0]`).
static func color_index(v: Variant) -> int:
	return maxi(0, color_index_or_invalid(v))


## Número como no JavaScript `x || fallback`: nulo, zero, NaN ou não numérico dão o fallback.
static func num(v: Variant, fallback: float) -> float:
	var f := NAN
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		f = float(v)
	elif v is String and (v as String).is_valid_float():
		f = (v as String).to_float()
	return f if is_finite(f) and f != 0.0 else fallback


## Verdade do JavaScript: null, false, 0 e "" são falsos.
static func truthy(v: Variant) -> bool:
	match typeof(v):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return v
		TYPE_INT, TYPE_FLOAT:
			return float(v) != 0.0 and not is_nan(float(v))
		TYPE_STRING, TYPE_STRING_NAME:
			return str(v) != ""
	return true


## Cor do kit (índice 0..2) como Color.
static func kit_color(kit: Dictionary, index: int) -> Color:
	var colors: Array = kit.get("colors") if kit.get("colors") is Array and not kit.get("colors").is_empty() \
		else KIT_DEFAULT.colors
	var i := clampi(index, 0, colors.size() - 1)
	return Color.from_string(str(colors[i]), Color.BLACK)


## Montagem.corPadrao(): índice da cor da estampa no ponto (u, v) da camisa.
## u: 0..1 da esquerda para a direita; v: 0 na gola até 1 na barra; aspect = altura / largura.
static func pattern_index(kit: Dictionary, u: float, v: float, aspect: float) -> int:
	var n := maxi(1, roundi(num(kit.get("count"), 1.0)))
	var wv := num(kit.get("width"), 0.16)
	match str(kit.get("pattern", "")):
		"listras_verticais":
			return _mod2(floori(u * (2 * n + 1)))
		"listras_horizontais":
			return _mod2(floori(v * (2 * n + 1)))
		"faixa_diagonal":
			return 1 if absf(u - v * 0.95 - 0.02) / 1.38 < wv / 2.0 else 0
		"faixa_horizontal":
			return 1 if absf(v - 0.3) < wv / 2.0 else 0
		"faixa_vertical":
			return 1 if absf(u - 0.5) < wv / 2.0 else 0
		"metades":
			return 0 if u < 0.5 else 1
		"xadrez":
			var cells := 2 * n
			return _mod2(floori(u * cells) + floori(v * aspect * cells))
		"listras_diagonais":
			return _mod2(floori((u - v * 0.8 + 1.0) * (n + 0.5)))
		"chevron":
			return 1 if absf(v - 0.16 - absf(u - 0.5) * 0.7) < wv / 2.0 else 0
		"duas_faixas":
			return 1 if absf(u - 0.32) < wv / 2.0 or absf(u - 0.68) < wv / 2.0 else 0
		"losangos":
			var va := v * aspect
			return _mod2(floori((u + va) * n) + floori((u - va + 8.0) * n))
	return 0


## `k % 2` do JavaScript seguido de `cores[i] || cores[0]`: negativo vira a cor principal.
static func _mod2(k: int) -> int:
	return 0 if k < 0 else k % 2


# --- parâmetros do shader -------------------------------------------------------------------------

## Uniforms que dependem só dos mapas (modos 0 e 1).
func map_params() -> Dictionary:
	return {
		"maps": texture(),
		"size_px": source_size,
		"map_to_source": map_to_source(),
		"median": median,
		"bbox": bbox_fractions(),
	}


## Cores do kit para color0..2.
static func kit_color_params(kit: Dictionary) -> Dictionary:
	return {"color0": kit_color(kit, 0), "color1": kit_color(kit, 1), "color2": kit_color(kit, 2)}


## Uniforms da camisa (modo 0) que dependem do kit e da calibração do torso (sem os mapas).
static func shirt_kit_params(kit: Dictionary, calibration: Dictionary) -> Dictionary:
	var p := kit_color_params(kit)
	var collar: Dictionary = calibration.get("collar", {})
	var crest: Dictionary = calibration.get("crest", {})
	p["mode"] = 0
	p["pattern"] = pattern_code(kit.get("pattern"))
	p["pattern_count"] = float(maxi(1, roundi(num(kit.get("count"), 1.0))))
	p["pattern_width"] = num(kit.get("width"), 0.16)
	p["collar_left"] = _vec2(collar.get("left"), Vector2(0.38, 0.0))
	p["collar_right"] = _vec2(collar.get("right"), Vector2(0.62, 0.0))
	p["collar_depth"] = float(collar.get("depth", 0.055))
	p["crest_enabled"] = truthy(kit.get("crest")) and crest.get("center") is Array and crest.has("size")
	p["crest_center"] = _vec2(crest.get("center"), Vector2(0.7, 0.3))
	p["crest_size"] = float(crest.get("size", 0.0))
	return p


## Uniforms da manga (modo 1) que dependem do kit e da calibração do braço (sem os mapas).
static func sleeve_kit_params(kit: Dictionary, arm_calibration: Dictionary) -> Dictionary:
	var p := kit_color_params(kit)
	var sleeve: Dictionary = arm_calibration.get("sleeve", SLEEVE_DEFAULT)
	var cuff: Variant = kit.get("cuff")
	p["mode"] = 1
	p["sleeve_a"] = _vec2(sleeve.get("a"), Vector2(0.0, 0.2))
	p["sleeve_b"] = _vec2(sleeve.get("b"), Vector2(1.0, 0.2))
	p["sleeve_color"] = color_index(kit.get("sleeve_color", 0))
	p["cuff_enabled"] = not (cuff is bool and cuff == false)   # `kit.cuff !== false`
	p["cuff_color"] = color_index(kit.get("cuff_color", 1))
	p["cuff_width"] = num(kit.get("cuff_width"), 0.032)
	p["cuff_trim"] = truthy(kit.get("cuff_trim"))
	p["cuff_trim_color"] = color_index(kit.get("cuff_trim_color", 2))
	return p


## Todos os uniforms do torso (modo 0): mapas + kit + calibração (body_calibration do catálogo).
func shirt_params(kit: Dictionary, calibration: Dictionary) -> Dictionary:
	var p := map_params()
	p.merge(shirt_kit_params(kit, calibration), true)
	return p


## Todos os uniforms do braço (modo 1): mapas + kit + calibração da manga.
func sleeve_params(kit: Dictionary, arm_calibration: Dictionary) -> Dictionary:
	var p := map_params()
	p.merge(sleeve_kit_params(kit, arm_calibration), true)
	return p


## Uniforms da gola PNG (modo 2): cor da gola e do friso vindas do kit. Índice inválido cai no
## padrão de colorirGola (gola branca, friso #1d1d1b).
static func collar_params(kit: Dictionary) -> Dictionary:
	var main_raw: Variant = kit.get("collar_color")
	var trim_raw: Variant = kit.get("collar_trim_color")
	var main_i := color_index_or_invalid(0 if main_raw == null else main_raw)
	var trim_i := color_index_or_invalid(1 if trim_raw == null else trim_raw)
	return {
		"mode": 2,
		"collar_main": kit_color(kit, main_i) if main_i >= 0 else Color("#ffffff"),
		"collar_trim": kit_color(kit, trim_i) if trim_i >= 0 else Color("#1d1d1b"),
	}


static func _vec2(v: Variant, fallback: Vector2) -> Vector2:
	if v is Array and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return fallback
