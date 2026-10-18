extends SceneTree
## Grade de retratos para conferência visual do PortraitRenderer e do shader do uniforme.
## Precisa de renderizador de verdade (NÃO use --headless):
##   godot --path jogo --script res://tools/portrait_snapshot.gd -- --out=/tmp/retratos.png
## Opções:
##   --out=<png>          arquivo de saída (obrigatório)
##   --count=12           número de retratos
##   --cols=4             colunas da grade
##   --cell=300x420       tamanho de cada célula em pixels
##   --offset=0           desloca a escolha das receitas (outras combinações do catálogo)
##   --render-scale=0     > 0 fixa o render_scale do uniforme (0 = automático)
##   --collar-blend=0     0 = faixas do contrato; 1 = pesos contínuos de colorirGola (web)
##   --bake               também desenha 2 retratos com PortraitBaker (sem cache) e salva
##                        <out>_baked.png, para conferir o render em textura
## As receitas saem do catálogo por índice (determinísticas, evitando pares rejeitados) e os kits
## percorrem os 8 padrões de estampa e as 4 golas, com cores, punhos e escudos variados.

const PAPER := Color("#efe6d2")
const PALETTE := ["#c8102e", "#1d4ed8", "#16a34a", "#facc15", "#111111", "#ffffff", "#7c3aed",
	"#f97316", "#0ea5e9", "#7f1d1d", "#065f46", "#e11d48", "#94a3b8", "#1e3a8a"]
const SIGLAS := ["FTB", "ECB", "SCR", "AAV", "UNI", "VRZ", "ATL", "CRB"]
const FACE_SLOTS := ["ear", "eye", "eyebrow", "nose", "mouth", "hair", "chin", "skin_mark", "body", "arm"]


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := {"out": "", "count": "12", "cols": "4", "cell": "300x420", "offset": "0", "render-scale": "0",
		"collar-blend": "0"}
	var bake := false
	for a in OS.get_cmdline_user_args():
		if a == "--bake":
			bake = true
			continue
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	if str(args.out) == "":
		printerr("uso: godot --path jogo --script res://tools/portrait_snapshot.gd -- --out=<arquivo.png>")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		printerr("portrait_snapshot precisa de renderizador: rode sem --headless")
		quit(2)
		return
	var count := int(args.count)
	var cols := maxi(1, int(args.cols))
	var cell_parts: PackedStringArray = str(args.cell).split("x")
	var cell := Vector2i(int(cell_parts[0]), int(cell_parts[1]))
	var rows := ceili(float(count) / cols)
	var label_h := 46
	var cat := PortraitCatalog.shared()
	var t0 := Time.get_ticks_msec()

	var viewport := SubViewport.new()
	viewport.size = Vector2i(cols * cell.x, rows * (cell.y + label_h))
	viewport.transparent_bg = false
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var bg := ColorRect.new()
	bg.color = PAPER
	bg.size = Vector2(viewport.size)
	viewport.add_child(bg)

	for i in count:
		var face := recipe(cat, i + int(args.offset))
		var kit := kit_for(cat, i)
		var origin := Vector2((i % cols) * cell.x, (i / cols) * (cell.y + label_h))
		var r := PortraitRenderer.new()
		r.uniform_render_scale = float(args["render-scale"])
		r.collar_blend_mode = int(args["collar-blend"])
		r.fit_size = Vector2(cell) - Vector2(16, 16)
		r.position = origin + Vector2(8, 8)
		r.setup(face, kit, cat)
		viewport.add_child(r)
		var label := Label.new()
		label.position = origin + Vector2(6, cell.y - 4)
		label.size = Vector2(cell.x - 12, label_h)
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color("#2b2620"))
		label.text = "%s %s %s %s\n%s | gola %s | %s" % [face.head, face.hair if face.hair != "" else "careca",
			face.body, face.arm, kit.pattern, cat.collar_id(str(kit.collar)), ",".join(kit.colors)]
		viewport.add_child(label)
	print("retratos montados em %d ms" % (Time.get_ticks_msec() - t0))

	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := viewport.get_texture().get_image()
	var err := img.save_png(str(args.out))
	print("grade %dx%d salva em %s (%s)" % [img.get_width(), img.get_height(), args.out, error_string(err)])

	if bake:
		var baked: Array = []
		for i in 2:
			var tex: Texture2D = await PortraitBaker.bake(recipe(cat, i), kit_for(cat, i + 3), Vector2i(256, 320), root, cat, false)
			if tex != null:
				baked.append(tex.get_image())
		if baked.size() == 2:
			var sheet := Image.create_empty(512 + 24, 320 + 16, false, Image.FORMAT_RGBA8)
			sheet.fill(Color("#7a8a99"))
			for k in 2:
				sheet.blend_rect(baked[k], Rect2i(Vector2i.ZERO, Vector2i(256, 320)), Vector2i(8 + k * 264, 8))
			var baked_out := str(args.out).get_basename() + "_baked.png"
			sheet.save_png(baked_out)
			print("retratos em textura (PortraitBaker) salvos em %s" % baked_out)
		else:
			printerr("PortraitBaker não devolveu as texturas")
	quit(0 if err == OK else 1)


## Receita determinística por índice: cada slot anda com um passo diferente pelo catálogo,
## pulando pares cabeça x peça rejeitados pelo validador.
static func recipe(cat: PortraitCatalog, i: int) -> Dictionary:
	var rejected := {}
	for pair in cat.data.get("validation", {}).get("rejected", []):
		rejected["%s|%s" % [pair[0], pair[1]]] = true
	var heads := cat.ids_with_status("head", "active")
	var face := {"head": heads[i % heads.size()]}
	var steps := {"ear": 3, "eye": 5, "eyebrow": 1, "nose": 2, "mouth": 7, "hair": 3, "chin": 1, "skin_mark": 1, "body": 1, "arm": 1}
	for slot in FACE_SLOTS:
		var ids := cat.ids_with_status(slot, "active")
		if ids.is_empty():
			face[slot] = ""
			continue
		var k: int = i * int(steps[slot]) + FACE_SLOTS.find(slot)
		var id := ""
		for attempt in ids.size():
			var candidate: String = ids[(k + attempt) % ids.size()]
			if not rejected.has("%s|%s" % [face.head, candidate]):
				id = candidate
				break
		face[slot] = id
	if i % 6 == 5:
		face.hair = ""
	if i % 2 == 1:
		face.chin = ""
	if i % 3 != 0:
		face.skin_mark = ""
	return face


## Kit determinístico por índice: todos os padrões, todas as golas, cores e punhos variados.
static func kit_for(cat: PortraitCatalog, i: int) -> Dictionary:
	var collars := cat.ids("collar")
	var p: String = PALETTE[(i * 5) % PALETTE.size()]
	var s: String = PALETTE[(i * 5 + 3 + i / 3) % PALETTE.size()]
	if s == p:
		s = "#ffffff" if p != "#ffffff" else "#111111"
	return {
		"pattern": UniformMaps.PATTERNS[i % UniformMaps.PATTERNS.size()],
		"colors": [p, s, ["#111111", "#ffffff", p, s][i % 4]],
		"count": 2 + i % 4,
		"width": 0.12 + 0.02 * (i % 6),
		"collar": collars[i % collars.size()] if not collars.is_empty() else "nenhuma",
		"collar_color": (i + 2) % 3,
		"collar_trim_color": (i + 1) % 3,
		"sleeve_color": 0 if i % 3 != 2 else 1,
		"cuff": i % 5 != 4,
		"cuff_color": (i + 1) % 3,
		"cuff_trim": i % 2 == 0,
		"cuff_trim_color": (i + 2) % 3,
		"crest": true,
		"sigla": SIGLAS[i % SIGLAS.size()],
	}
