extends SceneTree
## Folha das molduras: o MESMO atleta (gerador real, ruleset de desenvolvimento) desenhado em todos
## os níveis de data/cards/card_config.json (normal, raro, lendário, mítico, divino e estrela
## convidada), para comparar com o visuais/card_studio.html depois de mexer numa moldura, num foil
## ou no brilho divino (e rodar python3 visuais/exportar_cards.py).
##
## Precisa de renderizador de verdade (NÃO use --headless):
##   godot --path jogo --script res://tools/card_frames_sheet.gd -- --out=/tmp/molduras.png
## Opções:
##   --out=<png>        arquivo de saída (obrigatório)
##   --seed=7           semente do atleta
##   --card=360         largura de cada figurinha em pixels (altura = largura × StickerCard.ASPECT)
##   --cols=3           colunas da grade
##   --wait=0.6         segundos de animação antes da captura (o foil e o brilho andam com o tempo)

const RULESET := "res://rulesets/dev.json"
const DATE := "2026-10-02"
const BG := Color("#0f3d28")
const TEXT := Color("#f3ead2")
const GAP := 24
const CAPTION_H := 26


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := {"out": "", "seed": "7", "card": "360", "cols": "3", "wait": "0.6"}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	if str(args.out) == "":
		printerr("uso: godot --path jogo --script res://tools/card_frames_sheet.gd -- --out=<arquivo.png>")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		printerr("card_frames_sheet precisa de renderizador: rode sem --headless")
		quit(2)
		return

	var reg := MechanicRegistry.new()
	reg.discover()
	reg.apply_ruleset(Ruleset.load_file(RULESET))
	var world := World.new()
	world.date = DATE
	var gen: Variant = reg.bus.decide("athlete_generator.generate", {
		"world": world, "count": 1, "seed": int(args.seed), "tiers": ["ouro"], "positions": ["MID"],
		"origin": {"source": "test", "date": DATE}, "unique": false, "commit": false,
	})
	if not (gen is Dictionary) or not bool(gen.get("ok", false)):
		printerr("athlete_generator.generate falhou: %s" % str(gen))
		reg.dispose()
		quit(1)
		return
	var a: Athlete = gen.athletes[0]
	var kit := UniformMaps.normalize_kit({"pattern": "listras_verticais", "colors": ["#1d4ed8", "#ffffff", "#0b1f4d"],
		"count": 3, "collar": "collar_003", "crest": true, "sigla": "FTB"})

	var frames := StickerCard.frames()
	var cols := maxi(1, int(args.cols))
	var card := Vector2i(maxi(120, int(args.card)), roundi(maxi(120, int(args.card)) * StickerCard.ASPECT))
	var rows := ceili(float(frames.size()) / cols)
	var cell := Vector2i(card.x + GAP, card.y + CAPTION_H + GAP)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(cols * cell.x + GAP, rows * cell.y + GAP)
	viewport.transparent_bg = false
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sheet := Control.new()
	sheet.size = Vector2(viewport.size)
	viewport.add_child(sheet)
	var bg := ColorRect.new()
	bg.color = BG
	bg.size = sheet.size
	sheet.add_child(bg)
	for i in frames.size():
		var f: String = frames[i]
		var origin := Vector2(GAP + (i % cols) * cell.x, GAP + (i / cols) * cell.y)
		var sticker := StickerCard.new()
		sticker.size = Vector2(card)
		sticker.position = origin
		sticker.set_card({"kind": "athlete", "athlete_id": a.id, "tier": a.tier(), "frame": f, "name": a.name,
			"position": a.position, "nationality": a.nationality, "face": a.dna.face}, kit, null, a.attributes)
		sticker.set_face_up(true)
		sheet.add_child(sticker)
		var l := Label.new()
		var cfg := StickerCard.frame_config(f)
		l.text = "%s · %s · foil %s" % [f, str(cfg.get("label", f)), str((cfg.get("foil", {}) as Dictionary).get("tipo", "-"))]
		l.position = origin + Vector2(0, card.y + 4)
		l.size = Vector2(card.x, CAPTION_H)
		l.clip_text = true
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", TEXT)
		sheet.add_child(l)
	print("atleta %s (%s, %s) em %d molduras" % [a.name, a.position, a.tier(), frames.size()])

	await create_timer(maxf(0.0, float(args.wait))).timeout
	await process_frame
	await RenderingServer.frame_post_draw
	var img := viewport.get_texture().get_image()
	var err := img.save_png(str(args.out))
	print("folha %dx%d salva em %s (%s)" % [img.get_width(), img.get_height(), args.out, error_string(err)])
	reg.dispose()
	quit(0 if err == OK else 1)
