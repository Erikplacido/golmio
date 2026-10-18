extends Node
## Capturas automáticas das telas (docs/PLANO_DE_TELAS.md, Fase 0). Abre cada rota pelo Router e
## salva um PNG por rota. Sempre num perfil de save separado (--profile), nunca no do jogador.
## Desenha de verdade: não use --headless. O tamanho da janela vem de --resolution.
##
##   godot --path . --resolution 1280x800 res://tools/screens_snapshot.tscn -- --keep-window \
##       --profile=capturas --ruleset=dev --out=/tmp/telas [--routes=home,squad] [--fresh] [--play=2]
##
##   --fresh     apaga o perfil e cria um clube novo (estreia concluída)
##   --play=N    joga N amistosos simulados (histórico e tela de Resultado)
##   --official  o primeiro jogo simulado é o oficial do dia (precisa de daily_official ligado)
##   rota "match_intro": prepara um amistoso e captura a apresentação e o cara-ou-coroa da partida
##   rota "prematch_details": o pré-jogo com a janela de detalhes aberta (só no compacto)
##   --overflow  lista os nós que passam da borda direita (texto cortado no celular)
## Ou use tools/capturar_telas.sh, que roda nas quatro resoluções de referência.

const DEFAULT_ROUTES := ["home", "modes", "prematch", "result", "squad", "athlete", "lineup",
	"collection", "club", "shop", "starter_pack", "first_lineup"]
const SETTLE_SECONDS := 1.2

var _out := ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# Sobrevive às trocas de cena (rotas de tela cheia).
	var tree := get_tree()
	get_parent().remove_child(self)
	tree.root.add_child(self)
	var profile := _arg("profile")
	_out = _arg("out")
	if profile == "" or _out == "":
		push_error("screens_snapshot: passe --profile=<nome> e --out=<pasta>")
		tree.quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	var game: GameStore = tree.root.get_node("Game")
	var app := tree.root.get_node("App")
	if OS.get_cmdline_user_args().has("--fresh") or not game.has_club():
		_seed_world(app, game)
	var plays := int(_arg("play")) if _arg("play") != "" else 0
	for i in plays:
		var official := i == 0 and OS.get_cmdline_user_args().has("--official")
		_simulate(game, GameStore.KIND_OFFICIAL if official else GameStore.KIND_FRIENDLY)
	var routes: Array = Array(_arg("routes").split(",", false)) if _arg("routes") != "" else DEFAULT_ROUTES
	var vp := get_viewport().get_visible_rect().size
	var tag := "%dx%d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]
	var router: AppRouter = tree.root.get_node("Router")
	for route in routes:
		var p := {}
		if route == "athlete" and not game.squad().is_empty():
			p = {"id": game.squad()[0].id}
		if route == "prematch":
			p = {"kind": GameStore.KIND_FRIENDLY}
		router.reset()
		await tree.create_timer(0.2).timeout
		if route == "match_intro":
			game.prepare_match(GameStore.KIND_FRIENDLY, game.friendly_opponents()[0])
			router.go("match", p)
		elif route == "prematch_details":
			router.go("prematch", {"kind": GameStore.KIND_FRIENDLY})
			await tree.create_timer(SETTLE_SECONDS).timeout
			var details: Button = tree.root.find_child("Details", true, false)
			if details:
				details.pressed.emit()
		else:
			router.go(route, p)
		await tree.create_timer(SETTLE_SECONDS).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := _out.path_join("%s_%s.png" % [route, tag])
		img.save_png(path)
		if route == "match_intro":
			await tree.create_timer(2.6).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_out.path_join("%s_moeda_%s.png" % [route, tag]))
			game.discard_pending_match()
		print("[capturas] %s (lógico %s) -> %s" % [route, vp, path])
		if OS.get_cmdline_user_args().has("--overflow"):
			_report_overflow(tree.root, route, vp.x)
	tree.quit()


func _seed_world(app: Node, game: GameStore) -> void:
	game.backend.save_world({})
	var world := World.new()
	world.date = game.today()
	var data := {"name": "Vila Nova FC", "sigla": "VIL", "club_identity": {"kit": {
		"pattern": "listras_verticais", "colors": ["#c8102e", "#ffffff", "#1d1d1b"], "sigla": "VIL"}}}
	var res := OnboardingService.create_club(world, data, app.registry, game.backend)
	if not bool(res.get("ok", false)):
		push_error("screens_snapshot: não criou o clube: %s" % str(res))
	game.reload()
	game.advance_onboarding(GameStore.STAGE_DONE)


func _simulate(game: GameStore, kind: String) -> void:
	var opps := game.friendly_opponents() if kind == GameStore.KIND_FRIENDLY else [game.official_opponent()]
	var prep := game.prepare_match(kind, opps[0])
	if not bool(prep.get("ok", false)):
		push_error("screens_snapshot: partida não preparada: %s" % str(prep.get("errors")))
		return
	var app := get_tree().root.get_node("App")
	var engine := MatchEngine.create(prep.setup, app.registry)
	var result := engine.run_to_end()
	engine.dispose()
	game.finish_match(result)


## Nós visíveis que passam da borda direita: o mais alto de cada ramo (o pai cabe) e, dentro dele,
## os nós mais fundos cuja largura mínima já não cabe no espaço até a borda (quem empurra).
func _report_overflow(node: Node, route: String, right: float, parent_over: bool = false) -> void:
	var over := parent_over
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is Control:
		var c := node as Control
		var r := c.get_global_transform() * Rect2(Vector2.ZERO, c.size)
		over = r.end.x > right + 1.0 and r.position.x < right
		if over and not parent_over:
			var room := (right - r.position.x) / maxf(c.get_global_transform().get_scale().x, 0.001)
			print("[corte] %s: %s fim=%d min=%d cabe=%d" % [route, c.get_path(), int(r.end.x),
				int(c.get_combined_minimum_size().x), int(room)])
			for culprit: Control in _too_wide(c, room):
				var kids := []
				for k in culprit.get_children():
					if k is Control and (k as Control).visible:
						var t := " \"%s\"" % str(k.get("text")).left(24) if k.get("text") != null else ""
						kids.append("%s%s=%d" % [k.get_class(), t, int((k as Control).get_combined_minimum_size().x)])
				print("[corte]     %s min=%d <- %s" % [c.get_path_to(culprit),
					int(culprit.get_combined_minimum_size().x), ", ".join(kids)])
				if OS.get_cmdline_user_args().has("--overflow-chain"):
					var n: Control = culprit
					while n != null:
						var widest: Control = null
						for k in n.get_children():
							if k is Control and (k as Control).visible and (widest == null \
									or (k as Control).get_combined_minimum_size().x > widest.get_combined_minimum_size().x):
								widest = k
						if widest:
							var kids2 := []
							for k in widest.get_children():
								if k is Control and (k as Control).visible:
									var t2 := " \"%s\"" % str(k.get("text")).left(24) if k.get("text") != null else ""
									kids2.append("%s%s=%d" % [k.get_class(), t2, int((k as Control).get_combined_minimum_size().x)])
							print("[corte]       > %s=%d <- %s" % [widest.get_class(), int(widest.get_combined_minimum_size().x), ", ".join(kids2)])
						n = widest
	for k in node.get_children():
		_report_overflow(k, route, right, over)


func _too_wide(c: Control, room: float) -> Array:
	var out := []
	for k in c.get_children():
		if k is Control and (k as Control).visible and (k as Control).get_combined_minimum_size().x > room + 0.5:
			out.append_array(_too_wide(k, room))
	if out.is_empty() and c.get_combined_minimum_size().x > room + 0.5:
		out.append(c)
	return out


static func _arg(name: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	return ""
