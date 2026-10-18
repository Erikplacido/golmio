extends TestCase
## Telas novas (presentation/*): cada cena monta com dados reais (GameStore em memória injetado em
## ScreenBase.store) e chega ao estado certo; sem clube, mostra o estado vazio com a saída.
## Fora da árvore: _ready() é chamado à mão.

const SCREENS := {
	"home": "res://presentation/home/home_screen.tscn",
	"modes": "res://presentation/home/modes_screen.tscn",
	"prematch": "res://presentation/prematch/prematch_screen.tscn",
	"result": "res://presentation/result/result_screen.tscn",
	"squad": "res://presentation/squad/squad_screen.tscn",
	"athlete": "res://presentation/squad/athlete_screen.tscn",
	"collection": "res://presentation/collection/collection_screen.tscn",
	"club": "res://presentation/club/club_screen.tscn",
	"shop": "res://presentation/shop/shop_screen.tscn",
	"starter_pack": "res://presentation/onboarding/starter_pack_screen.tscn",
	"first_lineup": "res://presentation/onboarding/first_lineup_screen.tscn",
}


func _store(with_club: bool = true) -> GameStore:
	var backend := MemoryBackend.new()
	var reg := Fixtures.registry("res://rulesets/dev.json")
	if with_club:
		var world := World.new()
		world.date = "2026-10-10"
		OnboardingService.create_club(world, {"name": "Vila Nova FC", "sigla": "VIL"}, reg, backend)
	var g := GameStore.new()
	g.bind(backend, reg)
	g.reload()
	return g


func _mount(route: String, g: GameStore, p: Dictionary = {}) -> ScreenBase:
	var s: ScreenBase = (load(SCREENS[route]) as PackedScene).instantiate()
	s.store = g
	s.setup(route, p)
	s._ready()
	return s


func _find_text(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text.contains(text):
		return true
	if node is Button and (node as Button).text.contains(text):
		return true
	for c in node.get_children():
		if _find_text(c, text):
			return true
	return false


func _done(g: GameStore, nodes: Array) -> void:
	for n in nodes:
		n.free()
	g.registry.dispose()
	g.free()


func test_telas_montam_prontas_com_clube() -> void:
	var g := _store()
	var opp: Dictionary = g.friendly_opponents()[0]
	var params := {
		"prematch": {"kind": "friendly", "opponent": opp.key},
		"athlete": {"id": g.squad()[0].id},
	}
	var made: Array = []
	for route in SCREENS:
		var s := _mount(route, g, params.get(route, {}))
		made.append(s)
		if route == "result":
			check_eq(s.state, ScreenBase.State.EMPTY, "resultado sem partida: estado vazio")
		else:
			check_eq(s.state, ScreenBase.State.READY, "%s pronta" % route)
	_done(g, made)


func test_sem_clube_mostra_a_saida() -> void:
	var g := _store(false)
	var made: Array = []
	for route in ["home", "squad", "club", "modes", "prematch"]:
		var s := _mount(route, g)
		made.append(s)
		check_eq(s.state, ScreenBase.State.EMPTY, "%s sem clube: vazio" % route)
	check(_find_text(made[0], tr("INICIO_CRIAR_CLUBE")), "Início oferece criar o clube")
	_done(g, made)


func test_inicio_destaca_o_oficial_e_depois_o_amistoso() -> void:
	var g := _store()
	var s := _mount("home", g)
	check(s.find_child("PlayOfficial", true, false) != null, "JOGAR do oficial")
	var prep := g.prepare_match(GameStore.KIND_OFFICIAL, g.official_opponent())
	var setup: MatchSetup = prep.setup
	setup.match_minutes = 4.0
	var e := MatchEngine.create(setup, g.registry)
	g.finish_match(e.run_to_end())
	e.dispose()
	s.refresh()
	check(s.find_child("PlayOfficial", true, false) == null, "oficial jogado: sem JOGAR do oficial")
	check(s.find_child("Countdown", true, false) != null, "contagem para o próximo oficial")
	var r := _mount("result", g)
	check_eq(r.state, ScreenBase.State.READY, "resultado da partida que acabou")
	check(_find_text(r, tr("RESULTADO_CARREIRA").to_upper()), "mostra o que mudou no clube")
	_done(g, [s, r])


func test_pre_jogo_bloqueia_escalacao_invalida() -> void:
	var g := _store()
	var t := g.tactics()
	var starters: Array = t.starting_11
	starters[0] = ""
	t.starting_11 = starters
	g.save_tactics(t)
	var s := _mount("prematch", g, {"kind": "friendly"})
	var play: Button = s.find_child("Play", true, false)
	check(play != null and play.disabled, "JOGAR desabilitado")
	check(play != null and play.tooltip_text != "", "e diz o motivo")
	_done(g, [s])


func test_elenco_filtra_e_busca() -> void:
	var g := _store()
	var s: SquadScreen = _mount("squad", g)
	var rows := func() -> int:
		return s.cards().size()
	check_eq(rows.call(), 11, "11 figurinhas")
	check(s.find_child("Grid_titular", true, false) != null, "bloco de titulares")
	check(s._list.find_child("Section_reserva", true, false) != null, "bloco de reservas (vazio, com aviso)")
	s._sector = "GK"
	s._render_list()
	check_eq(rows.call(), 1, "1 goleiro")
	s._sector = "ALL"
	s._query = "zzzz-ninguem"
	s._render_list()
	check_eq(rows.call(), 0, "busca sem resultado")
	check(_find_text(s, tr("ELENCO_FILTRO_VAZIO")), "estado vazio do filtro")
	_done(g, [s])
