extends TestCase
## PortraitRenderer, UniformMaps e o shader do uniforme (headless: sem pixels desenhados).
## A paridade da montagem está em test_portrait_layout; aqui: nós na ordem certa, material e modo
## por camada, gola e escudo, kit do clube, mapas de análise e detecção do corpo em imagens
## sintéticas, mapas pré-calculados pelo exportador (sem análise por pixel na hora de desenhar) e
## a chave de cache do PortraitBaker (muda com qualquer calibração ou pixel do catálogo).


## Receita com a primeira peça ATIVA de cada slot ("" se o slot não tem peça ativa: hoje orelha,
## queixo e braço, que saíram do conjunto). head = "" usa a primeira cabeça ativa.
func _face(cat: PortraitCatalog, head: String = "") -> Dictionary:
	var face := {"head": head if head != "" else _active(cat, "head")}
	for slot in ["ear", "eye", "eyebrow", "nose", "mouth", "hair", "chin", "skin_mark", "body", "arm"]:
		face[slot] = _active(cat, slot)
	return face


func _active(cat: PortraitCatalog, slot: String, index: int = 0) -> String:
	var ids := cat.ids_with_status(slot, "active")
	return str(ids[index]) if ids.size() > index else ""


## Catálogo igual ao compartilhado, mas com os soquetes de uma cabeça alterados.
func _catalog_with_head(head_id: String, change: Callable) -> PortraitCatalog:
	var base := PortraitCatalog.shared()
	var heads := base.heads.duplicate(true)
	var file := base.file_of("head", head_id)
	heads[file] = change.call(heads[file].duplicate(true))
	return PortraitCatalog.from_data(base.data, {"heads": heads}, base.part_anchors, base.body_anchors)


func _node_keys(r: PortraitRenderer) -> Array:
	return r.layer_nodes().map(func(n): return "%s/%s/%s" % [n.layer.slot, n.layer.id, n.layer.side])


func _layer_keys(layers: Array) -> Array:
	return layers.map(func(l): return "%s/%s/%s" % [l.slot, l.id, l.side])


func _mode(node: Node2D) -> int:
	var mat := node.material as ShaderMaterial
	return -1 if mat == null else int(mat.get_shader_parameter("mode"))


func test_shader_loads() -> void:
	var shader := PortraitRenderer.uniform_shader()
	check(shader != null, "uniform_collar.gdshader não carregou")
	if shader == null:
		return
	var code := shader.code
	check(code.contains("shader_type canvas_item"), "shader não é canvas_item")
	for u in ["mode", "maps", "render_scale", "pattern", "collar_left", "crest_enabled", "sleeve_a",
			"cuff_width", "collar_main", "collar_trim", "band_softness", "collar_blend_mode"]:
		check(code.contains("uniform") and code.contains(u), "uniform ausente no shader: %s" % u)
	# Com renderizador de verdade, a lista de uniforms vem do shader compilado.
	var names: Array = shader.get_shader_uniform_list().map(func(p): return p.name)
	if not names.is_empty():
		for u in ["mode", "maps", "collar_main", "sleeve_a"]:
			check(names.has(u), "uniform não compilado: %s" % u)


func test_nodes_follow_layout_order_and_modes() -> void:
	var cat := PortraitCatalog.shared()
	var face := _face(cat)
	var r := PortraitRenderer.new()
	r.setup(face, {}, cat)
	var expected := PortraitLayout.build(cat, face)
	check_eq(_node_keys(r), _layer_keys(expected), "nós fora da ordem oficial")
	var nodes := r.layer_nodes()
	for i in mini(nodes.size(), expected.size()):
		var n: Node2D = nodes[i]
		check(n.transform.is_equal_approx(expected[i].transform), "transform da camada %d" % i)
		check(n.get_parent().get_child(i) == n, "nó %d fora da posição na árvore" % i)
		var slot: String = expected[i].slot
		var want := 0 if slot == "body" else (1 if slot == "arm" else -1)
		check_eq(_mode(n), want, "modo do shader em %s" % slot)
		check(n.texture != null, "sem textura em %s" % slot)
		check_eq(n.size, Vector2(expected[i].w, expected[i].h), "tamanho original em %s" % slot)
	var body := r.find_layer("body")
	var collar := body.get_node_or_null("collar") if body else null
	check(collar != null, "gola PNG não é filha do tronco")
	if collar:
		check_eq(_mode(collar), 2, "modo da gola")
	check(body != null and body.get_node_or_null("crest_label") != null, "sigla do escudo ausente")
	check_eq(r.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "filtro com mipmaps")
	r.free()


func test_flags_change_node_order() -> void:
	var head := _active(PortraitCatalog.shared(), "head", 1)
	var cat := _catalog_with_head(head, func(a):
		a.body.behind = false
		a.hair.behind = true
		a.ear_left.behind = false
		return a)
	var face := _face(cat, head)
	var r := PortraitRenderer.new()
	r.setup(face, {}, cat)
	var slots: Array = r.layer_nodes().map(func(n): return n.layer.slot)
	# Sem orelha, queixo e braço no conjunto atual; a marca de pele não tem soquete nas cabeças novas.
	check_eq(slots, ["hair", "head", "body", "eye", "eyebrow", "nose", "mouth"],
		"ordem com corpo na frente e cabelo atrás")
	check_eq(_node_keys(r), _layer_keys(PortraitLayout.build(cat, face)), "renderer = layout")
	r.free()
	var r2 := PortraitRenderer.new()
	var bald := _face(PortraitCatalog.shared())
	bald.hair = ""
	bald.arm = ""
	r2.setup(bald)
	var slots2: Array = r2.layer_nodes().map(func(n): return n.layer.slot)
	check(not slots2.has("hair") and not slots2.has("arm"), "peça vazia virou nó: %s" % [slots2])
	check_eq(slots2[0], "body", "sem braço, o tronco vem primeiro")
	r2.free()


func test_unknown_ids_do_not_break() -> void:
	var cat := PortraitCatalog.shared()
	var face := _face(cat)
	face.nose = "nose_999"
	face.body = "body_999"
	var r := PortraitRenderer.new()
	r.setup(face, {"collar": "gola que não existe"}, cat)
	var slots: Array = r.layer_nodes().map(func(n): return n.layer.slot)
	check(not slots.has("nose") and not slots.has("body") and not slots.has("arm"), "desconhecidos viraram nós: %s" % [slots])
	check(slots.has("head") and slots.has("mouth"), "o resto sumiu: %s" % [slots])
	r.setup({"head": "head_999"}, {}, cat)
	check(r.layer_nodes().is_empty(), "cabeça desconhecida desenhou")
	check_eq(r.content_rect(), Rect2(), "sem conteúdo")
	r.free()


func test_collar_node_uses_contract_rect() -> void:
	var cat := PortraitCatalog.shared()
	var face := _face(cat)
	for collar_id in cat.ids("collar"):
		var r := PortraitRenderer.new()
		r.setup(face, {"collar": collar_id, "colors": ["#123456", "#abcdef", "#fedcba"], "collar_color": 1,
			"collar_trim_color": 2}, cat)
		var body := r.find_layer("body")
		var node: Node2D = body.get_node_or_null("collar")
		check(node != null, "gola %s ausente" % collar_id)
		if node:
			var rect := PortraitLayout.collar_rect(cat.body_calibration(face.body).collar, body.size, cat.size_of("collar", collar_id), cat.collar_calibration(collar_id))
			var drawn: Rect2 = node.transform * Rect2(Vector2.ZERO, node.size)
			check(drawn.position.is_equal_approx(rect.position) and drawn.size.is_equal_approx(rect.size),
				"retângulo da gola %s: %s x %s" % [collar_id, drawn, rect])
			var mat := node.material as ShaderMaterial
			check((mat.get_shader_parameter("collar_main") as Color).is_equal_approx(Color("#abcdef")), "cor da gola")
			check((mat.get_shader_parameter("collar_trim") as Color).is_equal_approx(Color("#fedcba")), "cor do friso")
		r.free()
	# Por nome de arquivo e "nenhuma".
	var r2 := PortraitRenderer.new()
	r2.setup(face, {"collar": "Retrato esportivo com gola polo retrô.png"}, cat)
	var c2 := r2.find_layer("body").get_node_or_null("collar")
	check(c2 != null and c2.layer.id == "collar_003", "gola por nome de arquivo")
	r2.set_kit({"collar": "nenhuma"})
	check(r2.find_layer("body").get_node_or_null("collar") == null, "gola 'nenhuma' continuou")
	r2.free()


func test_set_kit_updates_uniforms() -> void:
	var cat := PortraitCatalog.shared()
	var r := PortraitRenderer.new()
	r.setup(_face(cat), {}, cat)
	var body_mat := r.find_layer("body").material as ShaderMaterial
	check_eq(int(body_mat.get_shader_parameter("pattern")), UniformMaps.PATTERNS.find("listras_verticais"), "padrão do KIT_PADRAO")
	var kit := {"pattern": "xadrez", "colors": ["#112233", "#445566", "#778899"], "count": 4, "sleeve_color": 1,
		"cuff": false, "crest": false}
	r.set_kit(kit)
	body_mat = r.find_layer("body").material as ShaderMaterial
	check_eq(int(body_mat.get_shader_parameter("pattern")), 7, "xadrez")
	check_near(float(body_mat.get_shader_parameter("pattern_count")), 4.0, 1e-6, "count")
	check((body_mat.get_shader_parameter("color0") as Color).is_equal_approx(Color("#112233")), "cor principal")
	check(not bool(body_mat.get_shader_parameter("crest_enabled")), "escudo desligado")
	check(r.find_layer("body").get_node_or_null("crest_label") == null, "sigla sem escudo")
	# Mangas: só quando o catálogo tem braços (o conjunto atual não tem; o código fica pronto).
	if r.find_layer("arm", "left") == null:
		r.free()
		return
	var arm_mat := r.find_layer("arm", "left").material as ShaderMaterial
	check_eq(int(arm_mat.get_shader_parameter("mode")), 1, "modo da manga")
	check_eq(int(arm_mat.get_shader_parameter("sleeve_color")), 1, "cor da manga")
	check(not bool(arm_mat.get_shader_parameter("cuff_enabled")), "punho desligado")
	var right_mat := r.find_layer("arm", "right").material as ShaderMaterial
	check(right_mat != arm_mat, "cada braço tem o seu material")
	check_near(float(arm_mat.get_shader_parameter("density_ratio")),
		sqrt(absf(r.find_layer("arm", "left").transform.determinant())) / sqrt(absf(r.find_layer("body").transform.determinant())),
		1e-4, "braço usa a escala de análise do tronco")
	r.free()


func test_fit_size_and_content_rect() -> void:
	var cat := PortraitCatalog.shared()
	var r := PortraitRenderer.new()
	r.setup(_face(cat), {}, cat)
	var raw := r.content_rect()
	check_eq(raw, PortraitLayout.bounds(r.layers), "sem fit, a caixa é a do layout")
	r.fit_size = Vector2(200, 300)
	var fit := r.content_rect()
	check(Rect2(Vector2.ZERO, Vector2(200, 300)).grow(0.01).encloses(fit), "não coube: %s" % fit)
	check(absf(fit.size.x - 200.0) < 0.01 or absf(fit.size.y - 300.0) < 0.01, "não encostou na borda: %s" % fit)
	check(fit.get_center().is_equal_approx(Vector2(100, 150)), "não centralizou: %s" % fit)
	r.free()


func test_kit_for_club() -> void:
	var club := Club.new()
	club.colors = {"primary": "#0000ff", "secondary": "#ffff00"}
	club.short_name = "Fut"
	var kit := PortraitRenderer.kit_for_club(club)
	check_eq(kit.colors, ["#0000ff", "#ffff00", "#1d1d1b"], "cores do clube")
	check_eq(kit.pattern, UniformMaps.KIT_DEFAULT.pattern, "padrão do KIT_PADRAO")
	check_eq(kit.collar, UniformMaps.KIT_DEFAULT.collar, "gola padrão")
	check_eq(kit.sigla, "FUT", "sigla do clube")
	club.ext["club_identity"] = {"kit": {"pattern": "metades", "colors": ["#000000"], "collar": "collar_004"}}
	var kit2 := PortraitRenderer.kit_for_club(club)
	check_eq(kit2.pattern, "metades", "kit do clube")
	check_eq(kit2.colors, ["#000000", "#ffffff", "#1d1d1b"], "cores completadas pelo KIT_PADRAO")
	check_eq(kit2.collar, "collar_004", "gola do kit")
	check_eq(kit2.cuff_width, 0.032, "campos ausentes vêm do KIT_PADRAO")
	check_eq(PortraitRenderer.kit_for_club(null).colors, UniformMaps.KIT_DEFAULT.colors, "sem clube")


func test_normalize_kit_like_montagem() -> void:
	var k := UniformMaps.normalize_kit({"collar": null, "cuff": null, "colors": ["#1", "#2", "#3", "#4"]})
	check_eq(k.collar, UniformMaps.KIT_DEFAULT.collar, "gola nula volta ao padrão")
	check_eq(k.cuff, true, "punho nulo volta ao padrão")
	check_eq(k.colors.size(), 3, "três cores")
	var p := UniformMaps.shirt_kit_params({"crest": 0, "count": 0}, {"crest": {"center": [0.5, 0.5], "size": 0.1}})
	check(not p.crest_enabled, "crest 0 é falso (JS)")
	check_near(p.pattern_count, 1.0, 1e-9, "count 0 vale 1 (JS `count || 1`)")


func test_pattern_index_matches_cor_padrao() -> void:
	var kit := {"pattern": "listras_verticais", "count": 3}
	# 2n+1 = 7 faixas: u em [0, 1/7) principal, [1/7, 2/7) secundária...
	check_eq(UniformMaps.pattern_index(kit, 0.05, 0.5, 1.0), 0, "listra 0")
	check_eq(UniformMaps.pattern_index(kit, 0.2, 0.5, 1.0), 1, "listra 1")
	check_eq(UniformMaps.pattern_index(kit, -0.2, 0.5, 1.0), 0, "u negativo -> principal")
	kit.pattern = "listras_horizontais"
	check_eq(UniformMaps.pattern_index(kit, 0.5, 0.2, 1.0), 1, "horizontal")
	kit = {"pattern": "faixa_diagonal", "width": 0.16}
	check_eq(UniformMaps.pattern_index(kit, 0.5, 0.5, 1.0), 1, "diagonal no meio")
	check_eq(UniformMaps.pattern_index(kit, 0.9, 0.1, 1.0), 0, "fora da diagonal")
	kit.pattern = "faixa_horizontal"
	check_eq(UniformMaps.pattern_index(kit, 0.5, 0.3, 1.0), 1, "faixa no peito")
	check_eq(UniformMaps.pattern_index(kit, 0.5, 0.6, 1.0), 0, "fora da faixa no peito")
	kit.pattern = "faixa_vertical"
	check_eq(UniformMaps.pattern_index(kit, 0.52, 0.9, 1.0), 1, "faixa central")
	kit.pattern = "metades"
	check_eq(UniformMaps.pattern_index(kit, 0.49, 0.0, 1.0), 0, "metade esquerda")
	check_eq(UniformMaps.pattern_index(kit, 0.51, 0.0, 1.0), 1, "metade direita")
	kit = {"pattern": "xadrez", "count": 2}
	check_eq(UniformMaps.pattern_index(kit, 0.1, 0.1, 1.0), 0, "casa 0,0")
	check_eq(UniformMaps.pattern_index(kit, 0.3, 0.1, 1.0), 1, "casa 1,0")
	check_eq(UniformMaps.pattern_index(kit, 0.1, 0.2, 1.5), 1, "casa 0,1 com aspecto")
	check_eq(UniformMaps.pattern_index({"pattern": "lisa"}, 0.7, 0.7, 1.0), 0, "lisa")
	check_eq(UniformMaps.pattern_code("inexistente"), 0, "padrão desconhecido = lisa")


func test_collar_line_is_quadratic_bezier() -> void:
	var collar := {"left": [0.3, 0.1], "right": [0.7, 0.1], "depth": 0.2}
	check_near(UniformMaps.collar_line_y(collar, 100.0, 100.0, 10.0), 10.0, 1e-9, "antes da gola")
	check_near(UniformMaps.collar_line_y(collar, 100.0, 100.0, 90.0), 10.0, 1e-9, "depois da gola")
	# No meio (t = 0.5): 0.25 yl + 0.5 cy + 0.25 yr com cy = 2 x fundo - média = 30.
	check_near(UniformMaps.collar_line_y(collar, 100.0, 100.0, 50.0), 20.0, 1e-9, "fundo da gola")


func test_uniform_maps_on_synthetic_image() -> void:
	# 40 x 30, retângulo opaco cinza (x 10..29, y 5..24), resto transparente.
	var img := Image.create_empty(40, 30, false, Image.FORMAT_RGBA8)
	for y in range(5, 25):
		for x in range(10, 30):
			img.set_pixel(x, y, Color8(128, 128, 128, 255))
	var maps := UniformMaps.analyze(img, Vector2(80, 60), 0)
	check_eq(Vector2i(maps.width, maps.height), Vector2i(40, 30), "sem redução")
	check_eq(maps.bbox, Rect2i(10, 5, 20, 20), "bbox")
	var count := 0
	for v in maps.mask:
		count += v
	check_eq(count, 400, "pixels da máscara")
	check_eq(maps.dist[5 * 40 + 10], 1, "distância no canto")
	check_eq(maps.dist[14 * 40 + 19], 10, "distância no centro")
	check_eq(maps.dist[0], 0, "distância fora")
	check_near(maps.lum_blur[14 * 40 + 19], 128.0 / 255.0, 1e-5, "Lb uniforme dentro da silhueta")
	check_near(maps.lum_blur[5 * 40 + 10], 128.0 / 255.0, 1e-5, "Lb não escurece na borda")
	check_near(maps.median, 128.0 / 255.0, 1e-6, "mediana (percentil 60)")
	check_eq(maps.row_left[10], 10, "início da linha")
	check_eq(maps.row_right[10], 29, "fim da linha")
	check_eq(maps.row_left[0], -1, "linha vazia")
	check_near(maps.map_to_source(), 2.0, 1e-9, "pixels originais por pixel do mapa")
	check_eq(maps.bbox_fractions(), Vector4(0.25, 5.0 / 30.0, 0.75, 25.0 / 30.0), "bbox em frações")
	var tex_img := maps.to_image()
	check_eq(tex_img.get_size(), Vector2i(40, 30), "tamanho da textura de mapas")
	var c := tex_img.get_pixel(19, 14)
	check_eq(c.r8, 128, "R = Lb")
	check_eq(c.g8, 10, "G = distância")
	check_eq(c.b8, 255, "B = máscara")
	check_eq(tex_img.get_pixel(0, 0).b8, 0, "B fora da máscara")
	# Imagem escura: mediana nunca abaixo de 0.2. Redução respeita analysis_width.
	var dark := Image.create_empty(64, 32, false, Image.FORMAT_RGBA8)
	dark.fill(Color8(5, 5, 5, 255))
	var dm := UniformMaps.analyze(dark, Vector2.ZERO, 16)
	check_eq(Vector2i(dm.width, dm.height), Vector2i(16, 8), "reduzida para 16 px")
	check_near(dm.median, 0.2, 1e-9, "mediana mínima")
	check(UniformMaps.analyze(Image.new()).is_empty(), "imagem vazia")


func test_detect_body_on_synthetic_silhouette() -> void:
	# Pescoço estreito (x 45..55, y 0..19) sobre um tronco largo (x 10..89, y 20..99).
	var img := Image.create_empty(100, 100, false, Image.FORMAT_RGBA8)
	for y in 100:
		for x in 100:
			var inside := (x >= 45 and x <= 55 and y < 20) or (x >= 10 and x <= 89 and y >= 20)
			if inside:
				img.set_pixel(x, y, Color8(200, 190, 180, 255))
	var det := UniformMaps.analyze(img, Vector2.ZERO, 0).detect_body()
	check_eq(det.collar.left, [0.45, 0.2], "gola esquerda")
	check_eq(det.collar.right, [0.55, 0.2], "gola direita")
	check_near(det.collar.depth, 0.255, 1e-9, "fundo da gola")
	check_eq(det.shoulders.left, [0.115, 0.27], "ombro esquerdo")
	check_eq(det.shoulders.right, [0.875, 0.27], "ombro direito")
	check_eq(det.crest.center, [0.658, 0.37], "centro do escudo")
	check_near(det.crest.size, 0.1264, 1e-9, "tamanho do escudo")
	# A calibração salva sobrepõe campo a campo (calibracaoCorpo).
	var merged := UniformMaps.merge_body_calibration(det, {"shoulders": {"left": [0.1, 0.3]}, "crest": {"size": 0.2}})
	check_eq(merged.shoulders.left, [0.1, 0.3], "ombro salvo")
	check_eq(merged.shoulders.right, [0.875, 0.27], "ombro detectado")
	check_near(merged.crest.size, 0.2, 1e-9, "escudo salvo")
	check_eq(merged.crest.center, [0.658, 0.37], "centro detectado")
	check(merged.calibrated, "calibrado quando há algo salvo")
	check(not UniformMaps.calibration_complete({"shoulders": {"left": [0, 0]}}), "calibração incompleta")
	var arm := UniformMaps.merge_arm_calibration({})
	check_eq(arm.sleeve.a, [0.0, 0.2], "manga padrão")
	check(not arm.calibrated, "braço sem calibração")


func test_real_body_maps_are_sane() -> void:
	var cat := PortraitCatalog.shared()
	var body_id := _active(cat, "body")
	var maps := UniformMaps.for_part(cat, "body", body_id)
	check(maps != null and not maps.is_empty(), "mapas do torso")
	if maps == null or maps.is_empty():
		return
	check(maps.width <= UniformMaps.ANALYSIS_WIDTH, "largura de análise")
	check(maps.median >= 0.2 and maps.median <= 1.0, "mediana fora da faixa: %f" % maps.median)
	check(maps.bbox.size.x > maps.width / 2, "silhueta do torso pequena demais: %s" % maps.bbox)
	check(UniformMaps.for_part(cat, "body", body_id) == maps, "cache estático")
	# A detecção automática num torso real cai perto da calibração salva.
	var det := maps.detect_body()
	var saved := cat.body_anchor(body_id)
	check(absf(float(det.shoulders.left[1]) - float(saved.shoulders.left[1])) < 0.12, "ombro detectado longe do calibrado")
	check(float(det.collar.left[0]) < float(det.collar.right[0]), "gola detectada invertida")


func test_baker_cache_key() -> void:
	var cat := PortraitCatalog.shared()
	var face := _face(cat)
	var k1 := PortraitBaker.cache_key(face, {}, Vector2i(256, 320), cat)
	check_eq(k1, PortraitBaker.cache_key(face.duplicate(), UniformMaps.KIT_DEFAULT, Vector2i(256, 320), cat), "kit vazio = KIT_PADRAO")
	check(k1 != PortraitBaker.cache_key(face, {"pattern": "lisa"}, Vector2i(256, 320), cat), "kit muda a chave")
	check(k1 != PortraitBaker.cache_key(face, {}, Vector2i(128, 160), cat), "tamanho muda a chave")
	check_eq(k1.length(), 64, "sha256 hex")
	check(PortraitBaker.cache_path(k1).begins_with("user://portraits/"), "cache em user://portraits")
	# Os mesmos dados montados de novo dão a mesma chave (a impressão digital é do conteúdo).
	var same := PortraitCatalog.from_data(cat.data.duplicate(true), {"heads": cat.heads.duplicate(true)},
		cat.part_anchors.duplicate(true), cat.body_anchors.duplicate(true))
	check_eq(PortraitBaker.cache_key(face, {}, Vector2i(256, 320), same), k1, "mesmo conteúdo, mesma chave")
	# unpremultiply devolve a cor reta nas bordas semitransparentes.
	var img := Image.create_empty(2, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color8(50, 25, 0, 128))
	img.set_pixel(1, 0, Color8(10, 20, 30, 255))
	PortraitBaker.unpremultiply(img)
	check_eq(img.get_pixel(0, 0).r8, 100, "cor dividida pelo alfa")
	check_eq(img.get_pixel(1, 0).r8, 10, "opaco intacto")


func test_baker_cache_key_changes_with_calibration_and_pixels() -> void:
	# Regressão: a chave só olhava version e content_hash do catalog.json, que não cobriam as
	# âncoras nem os pixels. Recalibrar um soquete devolvia o PNG velho do cache para sempre.
	var cat := PortraitCatalog.shared()
	var face := _face(cat)
	var size := Vector2i(256, 320)
	var k0 := PortraitBaker.cache_key(face, {}, size, cat)
	var head_file := cat.file_of("head", face.head)
	var moved := _catalog_with_head(face.head, func(a):
		a.eye.x = float(a.eye.x) + 40.0
		return a)
	check(PortraitBaker.cache_key(face, {}, size, moved) != k0, "soquete recalibrado muda a chave")
	var hair := _catalog_with_head(face.head, func(a):
		a.hair.y = float(a.hair.y) + 40.0
		return a)
	check(PortraitBaker.cache_key(face, {}, size, hair) != k0, "soquete do cabelo muda a chave")
	var pa := cat.part_anchors.duplicate(true)
	var hair_file := cat.file_of("hair", face.hair)
	if not (pa.parts.get("hair") is Dictionary):
		pa.parts["hair"] = {}
	var entry: Dictionary = pa.parts.hair.get(hair_file, {})
	entry["native_scale"] = float(entry.get("native_scale", 1.0)) + 0.25
	pa.parts.hair[hair_file] = entry
	var scaled := PortraitCatalog.from_data(cat.data, {"heads": cat.heads}, pa, cat.body_anchors)
	check(PortraitBaker.cache_key(face, {}, size, scaled) != k0, "escala nativa muda a chave")
	var ba := cat.body_anchors.duplicate(true)
	var body_file := cat.file_of("body", face.body)
	ba.bodies[body_file].shoulders.left = [0.2, 0.3]
	var shoulders := PortraitCatalog.from_data(cat.data, {"heads": cat.heads}, cat.part_anchors, ba)
	check(PortraitBaker.cache_key(face, {}, size, shoulders) != k0, "ombros do torso mudam a chave")
	var data := cat.data.duplicate(true)
	data.parts.head[face.head]["tex_hash"] = "0".repeat(64)
	var redrawn := PortraitCatalog.from_data(data, {"heads": cat.heads}, cat.part_anchors, cat.body_anchors)
	check(PortraitBaker.cache_key(face, {}, size, redrawn) != k0, "PNG redesenhado (tex_hash) muda a chave")
	check(head_file != "", "cabeça do teste existe")


func test_catalog_hashes_pixels_and_anchors() -> void:
	# O exportador grava o hash dos pixels de cada textura e das três âncoras: o content_hash (e
	# com ele o golden de paridade) muda quando muda uma calibração ou um desenho.
	var cat := PortraitCatalog.shared()
	var anchors: Dictionary = cat.data.get("anchors", {})
	for f in [PortraitCatalog.HEAD_ANCHORS_FILE, PortraitCatalog.PART_ANCHORS_FILE, PortraitCatalog.BODY_ANCHORS_FILE]:
		check_eq(str(anchors.get(f, "")).length(), 64, "hash de %s no catálogo" % f)
	for slot in cat.data.get("slots", []):
		for id in cat.ids(slot):
			if str(cat.part(slot, id).get("status", "")) == "missing":
				continue
			check_eq(str(cat.part(slot, id).get("tex_hash", "")).length(), 64, "tex_hash de %s/%s" % [slot, id])


func test_baker_capture_survives_freed_host() -> void:
	# Regressão: se a tela (host) fosse liberada enquanto bake esperava o quadro, viewport.get_texture()
	# dava SCRIPT ERROR. _capture confere o viewport antes de tocar nele.
	var freed := SubViewport.new()
	freed.free()
	check(PortraitBaker._capture(freed) == null, "viewport liberado -> null, sem erro")
	check(PortraitBaker._capture(null) == null, "nulo -> null")
	var loose := SubViewport.new()
	check(PortraitBaker._capture(loose) == null, "fora da árvore (não desenhado) -> null")
	check(not is_instance_valid(loose) or loose.is_queued_for_deletion(), "o viewport é descartado")


func test_precomputed_maps_skip_pixel_analysis() -> void:
	# Regressão: a análise em GDScript (~200 ms por peça) rodava na thread principal dentro da
	# abertura do pacote. Com os mapas do exportador, for_part só carrega a textura.
	var cat := PortraitCatalog.shared()
	UniformMaps.clear_cache()
	for slot in ["body", "arm"]:
		for id in cat.ids(slot):
			var info := cat.maps_info(slot, id)
			check(not info.is_empty(), "catálogo sem mapas para %s/%s" % [slot, id])
			var maps := UniformMaps.for_part(cat, slot, id)
			check(maps != null and maps.precomputed, "%s/%s não usou os mapas pré-calculados" % [slot, id])
			if maps == null:
				continue
			check(maps.mask.is_empty() and maps.lum_blur.is_empty(), "%s/%s decodificou pixels sem precisar" % [slot, id])
			check_eq(Vector2i(maps.width, maps.height), Vector2i(int(info.w), int(info.h)), "tamanho do mapa %s/%s" % [slot, id])
			check_eq(maps.texture().get_size(), Vector2(info.w, info.h), "textura do mapa %s/%s" % [slot, id])
			check(maps.width <= UniformMaps.ANALYSIS_WIDTH, "largura de análise %s/%s" % [slot, id])
			check_eq(maps.source_size, cat.size_of(slot, id), "tamanho original %s/%s" % [slot, id])
			var params := maps.map_params()
			check(params.maps == maps.texture(), "o shader recebe a textura pré-calculada")
	# O torso usa a detecção do catálogo (sem abrir pixels) e a calibração salva por cima.
	var body_id: String = cat.ids("body")[0]
	var det := cat.detected_body(body_id)
	check_eq(det, cat.part("body", body_id).detected, "detecção vem do catálogo")


func test_precomputed_maps_match_runtime_analysis() -> void:
	# Os mapas do exportador (porta Python de Montagem.analisar, a partir do PNG original) batem
	# com a análise em GDScript da textura exportada, a menos da reamostragem.
	var cat := PortraitCatalog.shared()
	var pieces := []
	for id in cat.ids("arm").slice(0, 1):
		pieces.append(["arm", id])
	for id in cat.ids("body"):
		pieces.append(["body", id])
	for piece in pieces:
		var slot: String = piece[0]
		var id: String = piece[1]
		var pre := UniformMaps.for_part(cat, slot, id)
		var live := UniformMaps.analyze(cat.texture(slot, id).get_image(), cat.size_of(slot, id))
		if pre == null or live.is_empty():
			check(false, "sem mapas para comparar em %s/%s" % [slot, id])
			continue
		check_near(pre.median, live.median, 0.03, "mediana %s/%s" % [slot, id])
		var a := pre.bbox_fractions()
		var b := live.bbox_fractions()
		for k in 4:
			check_near(a[k], b[k], 0.02, "bbox[%d] %s/%s" % [k, slot, id])
		if slot == "body":
			var det: Dictionary = cat.part("body", id).detected
			var ldet := live.detect_body()
			for group in ["collar", "shoulders"]:
				for side in ["left", "right"]:
					for k in 2:
						check_near(float(det[group][side][k]), float(ldet[group][side][k]), 0.03,
							"%s.%s[%d] de %s" % [group, side, k, id])
			check_near(float(det.collar.depth), float(ldet.collar.depth), 0.03, "collar.depth de %s" % id)
			# detect_body também funciona nos mapas pré-calculados (decodifica a textura sob demanda)
			# e dá o mesmo que o exportador gravou, a menos da largura de detecção (360 x 400 px).
			var pdet := pre.detect_body()
			check_eq(pre.row_left.size(), pre.height, "linhas decodificadas de %s" % id)
			check_near(float(pdet.shoulders.left[1]), float(det.shoulders.left[1]), 0.02, "ombro decodificado de %s" % id)


func test_catalog_without_maps_falls_back_to_analysis() -> void:
	var cat := PortraitCatalog.shared()
	var data := cat.data.duplicate(true)
	for slot in ["body", "arm"]:
		for id in data.parts.get(slot, {}):
			data.parts[slot][id].erase("maps")
			data.parts[slot][id].erase("detected")
	var old := PortraitCatalog.from_data(data, {"heads": cat.heads}, cat.part_anchors, cat.body_anchors)
	var body_id: String = cat.ids("body")[0]
	var maps := UniformMaps.for_part(old, "body", body_id)
	check(maps != null and not maps.precomputed and not maps.is_empty(), "sem mapas no catálogo, analisa a textura")
	var det := old.detected_body(body_id)
	check(det.get("collar") is Dictionary and det.get("shoulders") is Dictionary, "detecção pela análise")
