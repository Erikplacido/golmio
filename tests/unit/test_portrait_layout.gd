extends TestCase
## Paridade da montagem dos retratos com visuais/montagem.js (a especificação canônica).
## O golden tests/golden/portrait_layout.json foi gerado rodando Montagem.compor() de verdade
## (node visuais/gerar_paridade_layout.js). Aqui PortraitLayout monta as mesmas receitas e cada
## camada tem de bater: mesma sequência slot/id/side, mesmo w/h e matriz com erro <= 1e-6.

const GOLDEN_PATH := "res://tests/golden/portrait_layout.json"
const EPS := 1e-6


func _golden() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN_PATH))
	return parsed if parsed is Dictionary else {}


## Compara a matriz de 64 bits da camada ([a, b, c, d, e, f]) com a do golden; confere também
## que o Transform2D (32 bits) é a mesma matriz, com a tolerância de float de 32 bits.
func _check_matrix(layer: Dictionary, m: Array, label: String) -> void:
	var got: Array = layer.m
	var t: Transform2D = layer.transform
	var t32 := [t.x.x, t.x.y, t.y.x, t.y.y, t.origin.x, t.origin.y]
	for i in 6:
		if absf(float(t32[i]) - float(m[i])) > 1e-3 + absf(float(m[i])) * 1e-6:
			failures.append("%s: transform[%d] esperado %.6f, obtido %.6f" % [label, i, float(m[i]), float(t32[i])])
			return
	for i in 6:
		if absf(float(got[i]) - float(m[i])) > EPS:
			failures.append("%s: m[%d] esperado %.9f, obtido %.9f" % [label, i, float(m[i]), float(got[i])])
			return


func test_golden_is_for_this_catalog() -> void:
	var g := _golden()
	check(not g.is_empty(), "golden ausente: node visuais/gerar_paridade_layout.js")
	var cat := PortraitCatalog.shared()
	check_eq(str(g.get("catalog_version", "")), cat.version, "versão do catálogo do golden")
	check_eq(str(g.get("catalog_hash", "")), cat.content_hash, "hash do catálogo do golden (regenere o golden)")


func test_all_golden_cases_match() -> void:
	var g := _golden()
	var cat := PortraitCatalog.shared()
	var cases: Array = g.get("cases", [])
	# Catálogo atual: 7 cabeças x 6 receitas (o golden cresce com o catálogo).
	check(cases.size() >= 40, "golden com poucos casos: %d" % cases.size())
	var draws_checked := 0
	for c in cases:
		var layers := PortraitLayout.build(cat, c.face, c.head_anchor)
		var draws: Array = c.draws
		if layers.size() != draws.size():
			failures.append("%s: %d camadas, esperado %d (%s)" % [c.name, layers.size(), draws.size(),
				", ".join(layers.map(func(l): return "%s/%s" % [l.slot, l.side]))])
			continue
		for i in draws.size():
			var d: Dictionary = draws[i]
			var l: Dictionary = layers[i]
			var label := "%s #%d %s/%s/%s" % [c.name, i, d.slot, d.id, d.side]
			if l.slot != d.slot or l.id != d.id or l.side != d.side:
				failures.append("%s: obtido %s/%s/%s" % [label, l.slot, l.id, l.side])
				continue
			check_near(float(l.w), float(d.w), 0.0, label + " w")
			check_near(float(l.h), float(d.h), 0.0, label + " h")
			_check_matrix(l, d.m, label)
			draws_checked += 1
	check(draws_checked >= 280, "desenhos conferidos: %d" % draws_checked)


func test_all_golden_sweep_matches() -> void:
	var g := _golden()
	var cat := PortraitCatalog.shared()
	var sweep: Array = g.get("sweep", [])
	check(sweep.size() >= 260, "varredura com poucas matrizes: %d" % sweep.size())
	var built := {}
	var checked := 0
	for s in sweep:
		var face := {"head": s.head, s.slot: s.id}
		if s.slot == "arm":
			face["body"] = s.body
		var key := JSON.stringify(face)
		if not built.has(key):
			built[key] = PortraitLayout.build(cat, face).filter(func(l): return l.slot == s.slot)
		var found := false
		for l in built[key]:
			if l.id == s.id and l.side == s.side:
				_check_matrix(l, s.m, "sweep %s %s %s %s" % [s.head, s.slot, s.id, s.side])
				found = true
				checked += 1
				break
		if not found:
			failures.append("sweep %s %s %s %s: camada não montada" % [s.head, s.slot, s.id, s.side])
	check_eq(checked, sweep.size(), "matrizes da varredura conferidas")


func test_order_follows_flags() -> void:
	var cat := PortraitCatalog.shared()
	var face := _full_face(cat)
	# Orelha e queixo saíram do conjunto atual (status "missing"), mas continuam desenháveis: entram
	# aqui para conferir a ordem de todos os slots, com soquetes de queixo e marca de pele na cabeça.
	face.ear = cat.ids("ear")[0]
	face.chin = cat.ids("chin")[0]
	face.skin_mark = cat.ids("skin_mark")[0]
	var anchor := cat.head_anchor(face.head).duplicate(true)
	for slot in ["chin", "skin_mark"]:
		anchor[slot] = (anchor.nose as Dictionary).duplicate()
	anchor.body.behind = true
	anchor.hair.behind = false
	anchor.ear_left.behind = true
	var base := _slots(PortraitLayout.build(cat, face, anchor))
	# Olhos e sobrancelhas: uma camada só (o par vem ilustrado numa imagem).
	check_eq(base, ["body", "ear", "ear", "head", "skin_mark", "chin", "eye", "eyebrow", "nose", "mouth",
		"hair"], "ordem padrão")
	var a2 := anchor.duplicate(true)
	a2.body.behind = false
	a2.hair.behind = true
	a2.ear_left.behind = false
	check_eq(_slots(PortraitLayout.build(cat, face, a2)), ["hair", "head", "body", "ear", "ear",
		"skin_mark", "chin", "eye", "eyebrow", "nose", "mouth"], "corpo na frente, cabelo atrás")
	# Sem o soquete ear_left as orelhas continuam atrás; sem o soquete do corpo não há corpo nem braço.
	var a3 := anchor.duplicate(true)
	a3.erase("body")
	var slots3 := _slots(PortraitLayout.build(cat, face, a3))
	check(not slots3.has("body") and not slots3.has("arm"), "sem soquete de corpo: %s" % [slots3])


func test_empty_and_unknown_parts_do_not_draw() -> void:
	var cat := PortraitCatalog.shared()
	var face := _full_face(cat)
	face.hair = ""
	face.chin = ""
	face.skin_mark = ""
	face.eye = "eye_999"
	var slots := _slots(PortraitLayout.build(cat, face))
	check(not slots.has("hair") and not slots.has("chin") and not slots.has("skin_mark"), "peça vazia desenhou: %s" % [slots])
	check(not slots.has("eye"), "ID desconhecido desenhou")
	check(slots.has("head") and slots.has("mouth"), "o resto do rosto sumiu: %s" % [slots])
	check(PortraitLayout.build(cat, {"head": "head_999"}).is_empty(), "cabeça desconhecida montou camadas")
	# Sem braço (o conjunto atual não tem braços): só o tronco.
	face.arm = ""
	var with_body := _slots(PortraitLayout.build(cat, face))
	check(with_body.has("body") and not with_body.has("arm"), "braço vazio desenhou: %s" % [with_body])


func test_socket_matrix_follows_formula() -> void:
	# Soquete direito espelhado, rodado 30 graus, escala 2 x nativa 1.5, pivot (0.25, 0.75).
	var sock := {"x": 100.0, "y": 50.0, "scale": 2.0, "rotation": 30.0, "flipX": true}
	var m := PortraitLayout.socket_m(sock, 40.0, 20.0, [0.25, 0.75], 1.5, true)
	var k := 3.0
	var r := deg_to_rad(30.0)
	var a := -k * cos(r)
	var b := -k * sin(r)
	var c := -k * sin(r)
	var d := k * cos(r)
	check_near(m[0], a, EPS, "a")
	check_near(m[1], b, EPS, "b")
	check_near(m[2], c, EPS, "c")
	check_near(m[3], d, EPS, "d")
	check_near(m[4], 100.0 - a * 10.0 - c * 15.0, EPS, "e")
	check_near(m[5], 50.0 - b * 10.0 - d * 15.0, EPS, "f")
	# O pivot cai exatamente no soquete.
	check_near(m[0] * 10.0 + m[2] * 15.0 + m[4], 100.0, EPS, "pivot x")
	check_near(m[1] * 10.0 + m[3] * 15.0 + m[5], 50.0, EPS, "pivot y")
	var t := PortraitLayout.socket_matrix(sock, 40.0, 20.0, Vector2(0.25, 0.75), 1.5, true)
	check_near(t.origin.x, m[4], 1e-3, "Transform2D = m")
	# flipX == false: o lado direito não espelha; scale 0 vale 1 (`scale || 1`).
	var m2 := PortraitLayout.socket_m({"x": 0, "y": 0, "scale": 0, "flipX": false}, 10.0, 10.0, [0.0, 0.0], 1.0, true)
	check_near(m2[0], 1.0, EPS, "sem espelho")
	# Override de escala por arquivo.
	var m3 := PortraitLayout.socket_m({"x": 0, "y": 0, "scale": 1}, 10.0, 10.0, [0.0, 0.0], 2.0, false, 1.5)
	check_near(m3[3], 3.0, EPS, "override x nativa")


func test_collar_rect_formula() -> void:
	var collar := {"left": [0.3, 0.1], "right": [0.7, 0.12], "depth": 0.2}
	var body := Vector2(800.0, 1000.0)
	var gola := Vector2(600.0, 200.0)
	var r := PortraitLayout.collar_rect(collar, body, gola)
	var xl := 240.0
	var xr := 560.0
	var s := (xr - xl) * 1.25 / 600.0
	var cy := (100.0 + 120.0) / 2.0
	# Rect2 é de 32 bits: tolerância de 1e-4 px.
	check_near(r.size.x, 600.0 * s, 1e-4, "largura")
	check_near(r.size.y, 200.0 * s, 1e-4, "altura")
	check_near(r.position.x, 400.0 - 600.0 * s / 2.0, 1e-4, "x")
	check_near(r.position.y, cy - 200.0 * s * 0.16, 1e-4, "y")
	check_eq(PortraitLayout.collar_rect(collar, body, Vector2.ZERO), Rect2(), "gola sem tamanho")


func test_collar_rect_with_individual_calibration() -> void:
	var collar := {"left": [0.3, 0.1], "right": [0.7, 0.12], "depth": 0.2}
	var body := Vector2(800.0, 1000.0)
	var gola := Vector2(600.0, 200.0)
	var calib := {
		"width_factor": 1.4,
		"top_factor": 0.2,
		"scale": 1.1,
		"offset": [5.0, -3.0],
	}
	var r := PortraitLayout.collar_rect(collar, body, gola, calib)
	var xl := 240.0
	var xr := 560.0
	var s := ((xr - xl) * 1.4 / 600.0) * 1.1
	var cy := (100.0 + 120.0) / 2.0
	check_near(r.size.x, 600.0 * s, 1e-4, "largura com calibracao")
	check_near(r.size.y, 200.0 * s, 1e-4, "altura com calibracao")
	check_near(r.position.x, 400.0 - 600.0 * s / 2.0 + 5.0, 1e-4, "x com offset")
	check_near(r.position.y, cy - 200.0 * s * 0.2 - 3.0, 1e-4, "y com offset")


func test_bounds_cover_all_layers() -> void:
	var cat := PortraitCatalog.shared()
	var layers := PortraitLayout.build(cat, _full_face(cat))
	var b := PortraitLayout.bounds(layers)
	for l in layers:
		var r := PortraitLayout.layer_rect(l)
		check(b.grow(0.001).encloses(r), "caixa não cobre %s/%s" % [l.slot, l.side])
	# A cabeça em (0, 0) com tamanho original.
	var head: Dictionary = layers.filter(func(l): return l.slot == "head")[0]
	check_eq(PortraitLayout.layer_rect(head), Rect2(Vector2.ZERO, cat.size_of("head", head.id)), "caixa da cabeça")


func test_catalog_resolves_ids_and_collars() -> void:
	var cat := PortraitCatalog.shared()
	var heads := cat.ids_with_status("head", "active")
	check(heads.size() >= 1, "catálogo sem cabeças ativas")
	for h in heads:
		check(not cat.head_anchor(h).is_empty(), "%s sem soquetes" % h)
	check_eq(cat.pivot("ear", "ear_001"), Vector2(0.85, 0.5), "pivot padrão da orelha (sem calibração)")
	check_eq(cat.pivot("nose", "nose_001"), Vector2(0.38, 0.34), "pivot padrão do nariz (default_pivots)")
	check_eq(cat.pivot("nose", "nose_010"), Vector2(0.3692, 0.336), "pivot calibrado")
	check(cat.is_part_calibrated("mouth", "mouth_010"), "boca nova calibrada")
	check_near(cat.native_scale("mouth", "mouth_010"), 1.0, EPS, "escala nativa calibrada")
	check_near(cat.native_scale("nose", "nose_001"), 1.0, EPS, "escala nativa padrão")
	check(PortraitCatalog.FALLBACK_PIVOTS.has("ear") and cat.ids_with_status("ear", "active").is_empty(),
		"orelhas fora do conjunto atual (vêm desenhadas na cabeça)")
	check_eq(cat.collar_id("collar_002"), "collar_002", "gola por ID")
	check_eq(cat.collar_id("Caricatura retrô com gola redonda.png"), "collar_001", "gola por arquivo NFC")
	check_eq(cat.collar_id("Caricatura retrô com gola redonda.png"), "collar_001", "gola por arquivo NFD")
	check_eq(cat.collar_id("Gola V"), "collar_002", "gola por rótulo")
	check_eq(cat.collar_id("nenhuma"), "", "sem gola")
	check_eq(cat.collar_id("gola inexistente"), "", "gola desconhecida")
	var col_cal := cat.collar_calibration("collar_001")
	check(col_cal.has("width_factor") and col_cal.has("top_factor"), "gola 001 tem calibracao individual")
	check_eq(cat.collar_calibration("gola_inexistente"), {}, "gola inexistente sem calibracao")
	var body_id: String = cat.ids_with_status("body", "active")[0]
	var cal := cat.body_calibration(body_id)
	check(cal.calibrated, "%s calibrado" % body_id)
	check(cal.shoulders.left is Array and cal.collar.has("depth") and cal.crest.has("size"), "calibração completa do torso")
	check(not cat.arm_calibration("arm_001").calibrated, "braço fora do catálogo usa a manga padrão")


# --- auxiliares ---------------------------------------------------------------------------------

## Primeira peça ATIVA de cada slot ("" se o slot não tem peça ativa).
func _full_face(cat: PortraitCatalog) -> Dictionary:
	var face := {"head": cat.ids_with_status("head", "active")[0]}
	for slot in ["ear", "eye", "eyebrow", "nose", "mouth", "hair", "chin", "skin_mark", "body", "arm"]:
		var ids := cat.ids_with_status(slot, "active")
		face[slot] = ids[0] if not ids.is_empty() else ""
	return face


func _slots(layers: Array) -> Array:
	return layers.map(func(l): return l.slot)
