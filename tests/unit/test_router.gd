extends TestCase
## Router: pilha por aba, troca de aba preservando a pilha, raiz ao tocar na aba ativa, voltar,
## telas cheias, links profundos. Fora da árvore: as trocas de cena só ficam registradas.


func _router() -> AppRouter:
	return AppRouter.new()


func _routes(r: AppRouter, tab: String = "") -> Array:
	return r.stack(tab).map(func(e): return e.route)


func test_comeca_no_inicio() -> void:
	var r := _router()
	check_eq(r.current_tab, "home")
	check_eq(r.current_route(), "home")
	check_eq(r.depth(), 1)
	for tab in Routes.TABS:
		check_eq(_routes(r, tab), [Routes.TAB_ROOTS[tab]], "aba %s começa na raiz" % tab)
	r.free()


func test_pilha_por_aba() -> void:
	var r := _router()
	r.go("modes")
	r.go("prematch", {"kind": "friendly"})
	check_eq(_routes(r), ["home", "modes", "prematch"], "empilha no Início")
	r.go("athlete", {"id": "a1"})
	check_eq(r.current_tab, "squad", "rota de outra aba troca a aba")
	check_eq(_routes(r), ["squad", "athlete"], "pilha do Elenco")
	r.switch_tab("home")
	check_eq(r.current_route(), "prematch", "voltar à aba mantém onde estava")
	check_eq(r.current_params(), {"kind": "friendly"}, "com os params")
	r.switch_tab("home")
	check_eq(_routes(r), ["home"], "tocar na aba ativa volta para a raiz")
	r.go("prematch")
	r.go("prematch")
	check_eq(_routes(r), ["home", "prematch"], "mesma rota no topo não duplica")
	r.go("home")
	check_eq(_routes(r), ["home"], "ir para a raiz limpa a pilha da aba")
	r.free()


func test_voltar() -> void:
	var r := _router()
	r.go("athlete", {"id": "a1"})
	# Sem casca registrada o voltar não desempilha (não há tela): simula a casca.
	var shell := FakeShell.new()
	r._shell = shell
	check(r.back(), "desempilha")
	check_eq(_routes(r), ["squad"])
	check(r.back(), "na raiz de outra aba vai para o Início")
	check_eq(r.current_tab, "home")
	check(shell.renders >= 2, "a casca redesenha a cada passo")
	r.free()
	shell.free()


func test_tela_cheia() -> void:
	var r := _router()
	r.go("modes")
	check(r.go("match"), "abre a partida")
	check(r.is_fullscreen(), "em tela cheia")
	check_eq(r.last_scene_request, Routes.get_route("match").scene, "troca para a cena da partida")
	check_eq(r.current_route(), "match")
	check(r.back(), "voltar sai da tela cheia")
	check(not r.is_fullscreen())
	check_eq(r.last_scene_request, Routes.SHELL_SCENE, "volta para a casca")
	check_eq(r.current_route(), "modes", "na mesma pilha de antes")
	r.free()


func test_trocar_topo_e_reset() -> void:
	var r := _router()
	r.go("modes")
	r.replace("prematch", {"kind": "official"})
	check_eq(_routes(r), ["home", "prematch"], "replace troca o topo")
	r.go("athlete", {"id": "x"})
	r.reset()
	for tab in Routes.TABS:
		check_eq(r.depth(tab), 1, "reset limpa %s" % tab)
	check_eq(r.current_route(), "home")
	r.free()


func test_links_profundos() -> void:
	var r := _router()
	check(r.open_link("foteba://atleta/abc-123"), "link de atleta")
	check_eq(r.current_tab, "squad")
	check_eq(_routes(r), ["squad", "athlete"], "pilha montada com a raiz")
	check_eq(r.current_params(), {"id": "abc-123"})
	check(r.open_link("foteba://loja"), "link de aba")
	check_eq(r.current_tab, "shop")
	check(not r.open_link("foteba://nao-existe"), "link desconhecido")
	check(not r.open_link("https://exemplo.com"), "outro esquema")
	check(not r.go("rota_que_nao_existe"), "rota desconhecida")
	r.free()


func test_cenas_das_rotas_existem() -> void:
	for id in Routes.TABLE:
		var scene := str(Routes.get_route(id).scene)
		check(ResourceLoader.exists(scene), "cena da rota %s: %s" % [id, scene])
		check(Routes.is_fullscreen(id) or Routes.TABS.has(Routes.tab_of(id)), "rota %s tem aba ou é tela cheia" % id)
	check(ResourceLoader.exists(Routes.SHELL_SCENE), "cena da casca")
	for link in Routes.LINKS:
		check(Routes.has(Routes.LINKS[link]), "link %s aponta para rota existente" % link)
	for tab in Routes.TABS:
		check(GameIcons.has(Routes.TAB_ICONS[tab]), "ícone da aba %s" % tab)


func test_layout_por_largura() -> void:
	check_eq(AppShell.layout_for(390.0), AppShell.Layout.COMPACT, "celular em retrato")
	check_eq(AppShell.layout_for(700.0), AppShell.Layout.MEDIUM, "celular deitado / tablet")
	check_eq(AppShell.layout_for(1100.0), AppShell.Layout.EXPANDED, "desktop")


class FakeShell extends Node:
	var renders := 0

	func render() -> void:
		renders += 1
