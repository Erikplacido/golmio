extends SceneTree
## Folha de atletas para conferência visual de ponta a ponta: gera 12 atletas pelo gerador REAL
## (mecânica athlete_generator, pelo hook athlete_generator.generate, com o ruleset de
## desenvolvimento) com tiers variados de Bronze a Deus e sementes fixas, e desenha a figurinha de
## cada um (StickerCard + PortraitRenderer) vestida com o kit de um clube fictício diferente
## (PortraitRenderer.kit_for_club lê club.ext["club_identity"].kit). Todos os 8 padrões de estampa
## e as golas do catálogo aparecem, além de um kit sem gola.
##
## Precisa de renderizador de verdade (NÃO use --headless):
##   godot --path jogo --script res://tools/athlete_sheet.gd -- --out=/tmp/folha_atletas.png
## Opções:
##   --out=<png>                    arquivo de saída (obrigatório)
##   --seed=2026                    semente do lote (mesma semente = mesmos atletas)
##   --cols=4                       colunas da grade
##   --card=240                     largura de cada figurinha em pixels (altura = largura × StickerCard.ASPECT)
##   --ruleset=res://rulesets/dev.json
## No console sai uma linha por atleta (tier, posição, nacionalidade, nome, média, 3 melhores
## atributos, dna_hash) e o resultado de athlete_generator.validate.

const DEFAULT_RULESET := "res://rulesets/dev.json"
const HOOK_GENERATE := "athlete_generator.generate"
const HOOK_VALIDATE := "athlete_generator.validate"
const DATE := "2026-09-27"
const DEFAULT_SEED := 2026
## Um tier por atleta (do mais comum ao mais raro) e a posição forçada de cada um, para a folha
## cobrir todos os tiers e todas as posições.
const TIERS := ["bronze", "bronze", "prata", "prata", "prata", "ouro", "ouro", "ouro", "diamante", "diamante", "deus", "deus"]
const POSITIONS := ["GK", "DEF", "MID", "FWD", "DEF", "GK", "MID", "FWD", "DEF", "FWD", "MID", "GK"]
## Clubes fictícios: [nome, sigla, padrão, cores, gola (ID do catálogo ou "nenhuma")].
const CLUBS := [
	["Rubro Várzea", "RVZ", "listras_verticais", ["#c8102e", "#ffffff", "#1d1d1b"], "collar_001"],
	["Anil FC", "ANL", "lisa", ["#1d4ed8", "#ffffff", "#0b1f4d"], "collar_002"],
	["Verdão da Vila", "VDV", "faixa_diagonal", ["#16a34a", "#ffffff", "#0f3d22"], "collar_003"],
	["Canarinho EC", "CAN", "faixa_horizontal", ["#facc15", "#15803d", "#1d1d1b"], "collar_004"],
	["Carvão AC", "CRV", "listras_horizontais", ["#111111", "#ffffff", "#9ca3af"], "collar_001"],
	["Lilás United", "LIL", "metades", ["#7c3aed", "#f5f3ff", "#2e1065"], "collar_002"],
	["Laranja Mecânica", "LMC", "xadrez", ["#f97316", "#ffffff", "#7c2d12"], "collar_003"],
	["Celeste SC", "CEL", "faixa_vertical", ["#0ea5e9", "#ffffff", "#0c4a6e"], "collar_004"],
	["Grená Operário", "GRE", "lisa", ["#7f1d1d", "#fde68a", "#1d1d1b"], "nenhuma"],
	["Esmeralda FC", "ESM", "listras_verticais", ["#065f46", "#facc15", "#022c22"], "collar_002"],
	["Rosa Atlético", "RSA", "faixa_diagonal", ["#e11d48", "#111111", "#ffffff"], "collar_001"],
	["Marinha EC", "MAR", "metades", ["#1e3a8a", "#e5e7eb", "#facc15"], "collar_003"],
]
const BG := Color("#0f3d28")
const TEXT := Color("#f3ead2")
const TEXT_DIM := Color("#b9c9bd")
const GAP := 22
const HEADER_H := 74
const CAPTION_H := 44


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := {"out": "", "seed": str(DEFAULT_SEED), "cols": "4", "card": "240", "ruleset": DEFAULT_RULESET}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	if str(args.out) == "":
		printerr("uso: godot --path jogo --script res://tools/athlete_sheet.gd -- --out=<arquivo.png> [--seed=N]")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		printerr("athlete_sheet precisa de renderizador: rode sem --headless")
		quit(2)
		return

	var reg := MechanicRegistry.new()
	reg.discover()
	reg.apply_ruleset(Ruleset.load_file(str(args.ruleset)))
	if not reg.is_enabled("athlete_generator"):
		printerr("athlete_generator desligado em %s" % args.ruleset)
		reg.dispose()
		quit(1)
		return
	var world := World.new()
	world.date = DATE
	var batch_seed := int(args.seed)
	var gen: Variant = reg.bus.decide(HOOK_GENERATE, {
		"world": world, "count": TIERS.size(), "seed": batch_seed, "tiers": TIERS, "positions": POSITIONS,
		"origin": {"source": "test", "date": DATE}, "unique": true, "commit": true,
	})
	if not (gen is Dictionary) or not bool(gen.get("ok", false)):
		printerr("athlete_generator.generate falhou: %s" % str(gen))
		reg.dispose()
		quit(1)
		return
	var athletes: Array = gen.athletes
	var catalog := PortraitCatalog.shared()

	var cols := maxi(1, int(args.cols))
	var card_w := maxi(120, int(args.card))
	var card := Vector2i(card_w, roundi(card_w * StickerCard.ASPECT))
	var rows := ceili(float(athletes.size()) / cols)
	var cell := Vector2i(card.x + GAP, card.y + CAPTION_H + GAP)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(cols * cell.x + GAP, HEADER_H + rows * cell.y + GAP / 2)
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
	sheet.add_child(_label("FOTEBA · folha de atletas", Vector2(GAP, 12), Vector2(sheet.size.x - 2 * GAP, 30), 22, TEXT, true))
	sheet.add_child(_label("athlete_generator@1 · semente %d · catálogo %s · %s · %d atletas gerados pelo hook, figurinhas com o kit de clubes fictícios"
		% [batch_seed, catalog.version, str(args.ruleset).get_file(), athletes.size()],
		Vector2(GAP, 42), Vector2(sheet.size.x - 2 * GAP, 20), 13, TEXT_DIM))

	var t0 := Time.get_ticks_msec()
	var valid := 0
	for i in athletes.size():
		var a: Athlete = athletes[i]
		var club := _club(i)
		var kit := PortraitRenderer.kit_for_club(club)
		var origin := Vector2(GAP + (i % cols) * cell.x, HEADER_H + (i / cols) * cell.y)
		var sticker := StickerCard.new()
		sticker.size = Vector2(card)
		sticker.position = origin
		sticker.set_card({"kind": "athlete", "athlete_id": a.id, "tier": a.tier(), "name": a.name,
			"position": a.position, "nationality": a.nationality, "face": a.dna.face}, kit, catalog, a.attributes)
		sticker.set_face_up(true)
		sheet.add_child(sticker)
		var v: Variant = reg.bus.decide(HOOK_VALIDATE, {"world": world, "athlete": a})
		var ok := v is Dictionary and bool(v.get("ok", false))
		if ok:
			valid += 1
		var caption := "%s · %s · %s · média %.1f\n%s · %s · dna %s" % [StickerCard.tier_style(a.tier()).label,
			StickerCard.position_label(a.position, true), a.nationality, _mean(a), club.short_name,
			str(kit.pattern), a.dna_hash().substr(0, 10)]
		sheet.add_child(_label(caption, origin + Vector2(0, card.y + 6), Vector2(card.x, CAPTION_H), 11,
			TEXT if ok else Color("#ff8a80")))
		print("%2d %-8s %-3s %s %-26s média %5.1f  %s  dna %s  %s" % [i, a.tier(), a.position, a.nationality,
			a.name, _mean(a), _top(a), a.dna_hash().substr(0, 16), "ok" if ok else "INVÁLIDO %s" % str(v)])
	print("figurinhas montadas em %d ms; %d/%d atletas válidos" % [Time.get_ticks_msec() - t0, valid, athletes.size()])

	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := viewport.get_texture().get_image()
	var err := img.save_png(str(args.out))
	print("folha %dx%d salva em %s (%s)" % [img.get_width(), img.get_height(), args.out, error_string(err)])
	reg.dispose()
	quit(0 if err == OK and valid == athletes.size() else 1)


## Clube fictício i (cores + kit em club.ext["club_identity"].kit, como a futura club_creation).
static func _club(i: int) -> Club:
	var d: Array = CLUBS[i % CLUBS.size()]
	var colors: Array = d[3]
	var c := Club.new()
	c.id = "folha_%02d" % i
	c.name = str(d[0])
	c.short_name = str(d[1])
	c.colors = {"primary": colors[0], "secondary": colors[1]}
	c.ext["club_identity"] = {"kit": {
		"pattern": str(d[2]),
		"colors": colors.duplicate(),
		"count": 2 + i % 4,
		"width": 0.14 + 0.02 * (i % 4),
		"collar": str(d[4]),
		"collar_color": (i + 1) % 3,
		"collar_trim_color": (i + 2) % 3,
		"sleeve_color": 0 if i % 4 != 3 else 1,
		"cuff": i % 5 != 4,
		"cuff_color": 1 if i % 2 == 0 else 2,
		"cuff_trim": i % 3 == 0,
		"cuff_trim_color": 2,
		"crest": true,
		"sigla": str(d[1]),
	}}
	return c


static func _mean(a: Athlete) -> float:
	var total := 0.0
	for k in AthleteDna.BASE_ATTRIBUTE_IDS:
		total += a.attr(k)
	return total / AthleteDna.BASE_ATTRIBUTE_IDS.size()


static func _top(a: Athlete) -> String:
	var parts: Array = []
	for st in StickerCard.top_stats(a.attributes, 3):
		parts.append("%s %d" % [st[0], st[1]])
	return ", ".join(parts)


static func _label(text: String, pos: Vector2, size: Vector2, font_px: int, color: Color, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.clip_text = true
	l.add_theme_font_size_override("font_size", font_px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", StickerCard.font(bold))
	return l
