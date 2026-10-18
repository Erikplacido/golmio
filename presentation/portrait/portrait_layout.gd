class_name PortraitLayout
extends RefCounted
## Montagem do retrato em matemática pura (sem texturas): porta fiel de Montagem.compor(),
## matriz() e encaixe() de visuais/montagem.js, a especificação canônica. O teste
## tests/unit/test_portrait_layout.gd compara TODAS as matrizes com o golden
## tests/golden/portrait_layout.json, gerado a partir do próprio montagem.js.
##
## Cada camada leva o pixel (u, v) da imagem ORIGINAL da peça, em [0, w] x [0, h], ao espaço da
## cabeça (a cabeça fica em (0, 0) com a transformação identidade). Quem desenha estica a textura
## exportada (que pode ser menor) para Rect2(0, 0, w, h) e aplica `transform`.
## As contas são feitas em float de 64 bits: `m` = [a, b, c, d, e, f] (convenção do canvas,
## | a c e | / | b d f |) é a matriz exata; `transform` é a mesma em Transform2D (32 bits, para
## desenhar). A paridade com o golden (erro <= 1e-6) é conferida em `m`.
##
## Ordem oficial das camadas (Montagem.compor):
##   1 corpo, se head.body.behind != false: braços (ombros de body_anchors), depois o tronco
##   2 cabelo, se hair.behind == true
##   3 orelhas, se ear_left.behind != false (ou soquete ausente)
##   4 cabeça em (0, 0)
##   5 corpo, se body.behind == false
##   6 orelhas, se ear_left.behind == false
##   7 skin_mark · 8 chin · 9 olhos · 10 sobrancelhas · 11 nariz · 12 boca (olhos e sobrancelhas são
##     ilustrados em par numa imagem só, num soquete único)
##   13 cabelo, se não estiver atrás
## Peça "" ou desconhecida não desenha (desconhecida gera aviso).

## Soquetes de cada slot na cabeça: [chave em head_anchors.json, é o lado direito espelhado?]
## (Montagem.SOQUETES). Olhos e sobrancelhas vêm ilustrados em par (sem espelhamento). Os braços
## encaixam nos ombros do torso, não na cabeça.
const SOCKETS := {
	"ear": [["ear_left", false], ["ear_right", true]],
	"eye": [["eye", false]],
	"eyebrow": [["eyebrow", false]],
	"nose": [["nose", false]],
	"mouth": [["mouth", false]],
	"chin": [["chin", false]],
	"skin_mark": [["skin_mark", false]],
	"hair": [["hair", false]],
	"body": [["body", false]],
}
## Gola PNG: largura = largura do pescoço x 1.25; topo a 16% da altura acima da linha da gola.
const COLLAR_WIDTH_FACTOR := 1.25
const COLLAR_TOP_FACTOR := 0.16


## Camadas na ordem de desenho: [{slot, id, side, m: [a, b, c, d, e, f], transform: Transform2D, w, h}].
## head_anchor_override, se não vazio, substitui POR INTEIRO os soquetes da cabeça (o golden
## passa só os soquetes usados, às vezes com flags alteradas).
static func build(catalog: PortraitCatalog, face: Dictionary, head_anchor_override: Dictionary = {}) -> Array:
	var layers: Array = []
	if catalog == null:
		push_warning("PortraitLayout: sem catálogo")
		return layers
	var head_id := str(face.get("head", ""))
	var anchor: Dictionary = head_anchor_override if not head_anchor_override.is_empty() else catalog.head_anchor(head_id)
	if anchor.is_empty():
		if head_id != "":
			push_warning("PortraitLayout: cabeça sem soquetes ou desconhecida: %s" % head_id)
		return layers
	var body_behind := not anchor.has("body") or not _is_false(anchor["body"], "behind")
	var hair_behind := anchor.has("hair") and _is_true(anchor["hair"], "behind")
	var ears_behind := not anchor.has("ear_left") or not _is_false(anchor["ear_left"], "behind")

	if body_behind:
		_add_body(layers, catalog, face, anchor)
	if hair_behind:
		_add_part(layers, catalog, face, anchor, "hair")
	if ears_behind:
		_add_part(layers, catalog, face, anchor, "ear")
	var head_size := _usable_size(catalog, "head", head_id)
	if head_size != Vector2.ZERO:
		layers.append(_layer("head", head_id, "", [1.0, 0.0, 0.0, 1.0, 0.0, 0.0], head_size))
	if not body_behind:
		_add_body(layers, catalog, face, anchor)
	if not ears_behind:
		_add_part(layers, catalog, face, anchor, "ear")
	for slot in ["skin_mark", "chin", "eye", "eyebrow", "nose", "mouth"]:
		_add_part(layers, catalog, face, anchor, slot)
	if not hair_behind:
		_add_part(layers, catalog, face, anchor, "hair")
	return layers


## Montagem.matriz(): Translate(soquete) x Rotate(rotation, graus) x Scale(+-k, k) x
## Translate(-pivot * (w, h)), com k = scale (ou override) x escala nativa. O sinal - só no
## soquete direito quando flipX != false. `scale || 1`: escala nula ou zero vale 1.
## Devolve [a, b, c, d, e, f] em float de 64 bits.
static func socket_m(sock: Dictionary, w: float, h: float, pivot: Array, native: float,
		right: bool, scale_override: Variant = null) -> Array:
	var base := _js_number(sock.get("scale"))
	if scale_override != null:
		base = _js_number(scale_override)
	var k := (base if base != 0.0 and not is_nan(base) else 1.0) * native
	var sx := -k if right and not _is_false(sock, "flipX") else k
	var r := (_js_number(sock.get("rotation")) * PI) / 180.0
	if is_nan(r):
		r = 0.0
	var cs := cos(r)
	var sn := sin(r)
	var a := sx * cs
	var b := sx * sn
	var c := -k * sn
	var d := k * cs
	var px := float(pivot[0]) * w
	var py := float(pivot[1]) * h
	var x := _js_number(sock.get("x"))
	var y := _js_number(sock.get("y"))
	return [a, b, c, d, x - a * px - c * py, y - b * px - d * py]


## socket_m() como Transform2D (para desenhar).
static func socket_matrix(sock: Dictionary, w: float, h: float, pivot: Vector2, native: float,
		right: bool, scale_override: Variant = null) -> Transform2D:
	return to_transform(socket_m(sock, w, h, [pivot.x, pivot.y], native, right, scale_override))


## Produto de matrizes do canvas p x q (aplica q primeiro).
static func mul(p: Array, q: Array) -> Array:
	return [
		p[0] * q[0] + p[2] * q[1],
		p[1] * q[0] + p[3] * q[1],
		p[0] * q[2] + p[2] * q[3],
		p[1] * q[2] + p[3] * q[3],
		p[0] * q[4] + p[2] * q[5] + p[4],
		p[1] * q[4] + p[3] * q[5] + p[5],
	]


## [a, b, c, d, e, f] -> Transform2D(Vector2(a, b), Vector2(c, d), Vector2(e, f)).
static func to_transform(m: Array) -> Transform2D:
	return Transform2D(Vector2(m[0], m[1]), Vector2(m[2], m[3]), Vector2(m[4], m[5]))


## Retângulo da gola PNG no espaço do torso ORIGINAL (antes da escala de desenho), como em
## Montagem.vestir(): largura = pescoço x width_factor (padrão 1.25), centrada no pescoço,
## topo a top_factor da altura acima da linha da gola (padrão 16%).
## collar_calib pode conter:
##   - width_factor: float (relação com largura do pescoço, padrão 1.25)
##   - top_factor: float (fração da altura da gola acima da linha, padrão 0.16)
##   - scale: float (multiplicador de escala extra, padrão 1.0)
##   - offset: Array [dx, dy] ou Vector2 (deslocamento em px)
##   - offset_x, offset_y: float (deslocamentos pontuais em px)
static func collar_rect(collar: Dictionary, body_size: Vector2, collar_size: Vector2,
		collar_calib: Dictionary = {}) -> Rect2:
	if collar_size.x <= 0.0 or collar_size.y <= 0.0:
		return Rect2()
	var left: Array = collar.get("left", [0.38, 0.0])
	var right: Array = collar.get("right", [0.62, 0.0])
	var xl := float(left[0]) * body_size.x
	var yl := float(left[1]) * body_size.y
	var xr := float(right[0]) * body_size.x
	var yr := float(right[1]) * body_size.y
	var neck_w := xr - xl
	var cx := (xl + xr) / 2.0
	var cy := (yl + yr) / 2.0

	var wf := float(collar_calib.get("width_factor", COLLAR_WIDTH_FACTOR))
	var tf := float(collar_calib.get("top_factor", COLLAR_TOP_FACTOR))
	var sc := float(collar_calib.get("scale", 1.0))
	if sc <= 0.0:
		sc = 1.0

	var s := (neck_w * wf / collar_size.x) * sc
	var w := collar_size.x * s
	var h := collar_size.y * s

	var ox := 0.0
	var oy := 0.0
	if collar_calib.has("offset"):
		var off: Variant = collar_calib["offset"]
		if off is Array and (off as Array).size() >= 2:
			ox += float(off[0])
			oy += float(off[1])
		elif off is Vector2:
			ox += (off as Vector2).x
			oy += (off as Vector2).y
	if collar_calib.has("offset_x"):
		ox += float(collar_calib["offset_x"])
	if collar_calib.has("offset_y"):
		oy += float(collar_calib["offset_y"])

	return Rect2(cx - w / 2.0 + ox, cy - h * tf + oy, w, h)


## Caixa que a camada ocupa no espaço da cabeça (Montagem.caixa).
static func layer_rect(layer: Dictionary) -> Rect2:
	var t: Transform2D = layer.get("transform", Transform2D.IDENTITY)
	return t * Rect2(0.0, 0.0, float(layer.get("w", 0)), float(layer.get("h", 0)))


## União das caixas de todas as camadas (Rect2() se não há camadas).
static func bounds(layers: Array) -> Rect2:
	var out := Rect2()
	var first := true
	for layer in layers:
		var r := layer_rect(layer)
		if first:
			out = r
			first = false
		else:
			out = out.merge(r)
	return out


# --- internos -----------------------------------------------------------------------------------

## Montagem.compor -> peca(slot): uma camada por soquete presente, com override de escala por arquivo.
static func _add_part(layers: Array, catalog: PortraitCatalog, face: Dictionary, anchor: Dictionary, slot: String) -> void:
	var id := str(face.get(slot, ""))
	var size := _usable_size(catalog, slot, id)
	if size == Vector2.ZERO:
		return
	var pivot := catalog.pivot_xy(slot, id)
	var native := catalog.native_scale(slot, id)
	var file := catalog.file_of(slot, id)
	var paired: bool = SOCKETS[slot].size() == 2
	for entry in SOCKETS[slot]:
		var key: String = entry[0]
		var right: bool = entry[1]
		var sock: Variant = anchor.get(key)
		if not (sock is Dictionary):
			continue
		var s: Dictionary = (sock as Dictionary).duplicate()
		var offsets: Variant = s.get("offsets")
		if offsets is Dictionary and offsets.get(file) is Array:
			var off: Array = offsets[file]
			if off.size() >= 2:
				var odx: float = float(off[0])
				var ody: float = float(off[1])
				var ox: float = -odx if (right and s.get("flipX", true)) else odx
				s["x"] = float(s.get("x", 0.0)) + ox
				s["y"] = float(s.get("y", 0.0)) + ody
		var override: Variant = null
		var scales: Variant = s.get("scales")
		if scales is Dictionary and scales.get(file) != null:
			override = scales[file]
		var side := ("right" if right else "left") if paired else ""
		layers.append(_layer(slot, id, side, socket_m(s, size.x, size.y, pivot, native, right, override), size))


## Montagem.compor -> tronco(): braços nos ombros do torso (antes) e o tronco. O soquete do corpo
## agora também respeita `offsets` por arquivo.
static func _add_body(layers: Array, catalog: PortraitCatalog, face: Dictionary, anchor: Dictionary) -> void:
	var body_id := str(face.get("body", ""))
	var body_size := _usable_size(catalog, "body", body_id)
	var sock: Variant = anchor.get("body")
	if body_size == Vector2.ZERO or not (sock is Dictionary):
		return
	var s_body: Dictionary = (sock as Dictionary).duplicate()
	var body_offsets: Variant = s_body.get("offsets")
	var b_file := catalog.file_of("body", body_id)
	if body_offsets is Dictionary and body_offsets.get(b_file) is Array:
		var off_b: Array = body_offsets[b_file]
		if off_b.size() >= 2:
			s_body["x"] = float(s_body.get("x", 0.0)) + float(off_b[0])
			s_body["y"] = float(s_body.get("y", 0.0)) + float(off_b[1])
	var m := socket_m(s_body, body_size.x, body_size.y, catalog.pivot_xy("body", body_id),
		catalog.native_scale("body", body_id), false)
	var arm_id := str(face.get("arm", ""))
	var arm_size := _usable_size(catalog, "arm", arm_id)
	if arm_size != Vector2.ZERO:
		var shoulders: Dictionary = catalog.body_calibration(body_id).get("shoulders", {})
		var arm_pivot := catalog.pivot_xy("arm", arm_id)
		var ns := catalog.native_scale("arm", arm_id)
		for entry in [["left", false], ["right", true]]:
			var side: String = entry[0]
			var sh: Variant = shoulders.get(side)
			if not (sh is Array and sh.size() >= 2):
				continue
			var sx := -ns if entry[1] else ns
			# M_corpo x Translate(ombro x (bw, bh)) x Scale(+-ns, ns) x Translate(-pivot x (aw, ah))
			var am := mul(m, [1.0, 0.0, 0.0, 1.0, float(sh[0]) * body_size.x, float(sh[1]) * body_size.y])
			am = mul(am, [sx, 0.0, 0.0, ns, 0.0, 0.0])
			am = mul(am, [1.0, 0.0, 0.0, 1.0, -float(arm_pivot[0]) * arm_size.x, -float(arm_pivot[1]) * arm_size.y])
			layers.append(_layer("arm", arm_id, side, am, arm_size))
	layers.append(_layer("body", body_id, "", m, body_size))


static func _layer(slot: String, id: String, side: String, m: Array, size: Vector2) -> Dictionary:
	return {"slot": slot, "id": id, "side": side, "m": m, "transform": to_transform(m), "w": size.x, "h": size.y}


## Tamanho original da peça, ou ZERO se não desenha ("" em silêncio; desconhecida com aviso).
static func _usable_size(catalog: PortraitCatalog, slot: String, id: String) -> Vector2:
	if id == "":
		return Vector2.ZERO
	var size := catalog.size_of(slot, id)
	if not catalog.has_part(slot, id):
		push_warning("PortraitLayout: peça desconhecida %s/%s" % [slot, id])
		return Vector2.ZERO
	if size.x <= 0.0 or size.y <= 0.0:
		push_warning("PortraitLayout: peça sem dimensões %s/%s" % [slot, id])
		return Vector2.ZERO
	return size


## `soquete[chave] === false` do JavaScript.
static func _is_false(sock: Variant, key: String) -> bool:
	if not (sock is Dictionary):
		return false
	var v: Variant = sock.get(key)
	return v is bool and v == false


## `soquete[chave] === true` do JavaScript.
static func _is_true(sock: Variant, key: String) -> bool:
	if not (sock is Dictionary):
		return false
	var v: Variant = sock.get(key)
	return v is bool and v == true


## Number() do JavaScript para o que vem de JSON: null -> 0, número -> float, texto numérico.
static func _js_number(v: Variant) -> float:
	match typeof(v):
		TYPE_NIL:
			return 0.0
		TYPE_INT, TYPE_FLOAT:
			return float(v)
		TYPE_BOOL:
			return 1.0 if v else 0.0
		TYPE_STRING:
			return (v as String).to_float() if (v as String).is_valid_float() else NAN
	return NAN
