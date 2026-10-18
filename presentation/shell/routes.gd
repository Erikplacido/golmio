class_name Routes
extends RefCounted
## Tabela de rotas do app (docs/PLANO_DE_TELAS.md §2). Cada rota tem a cena e, se mora dentro da
## casca (AppShell), a aba dona da pilha; rotas "fullscreen" trocam a cena inteira e escondem a
## navegação (partida, estreia, demonstrações). Rota nova = uma linha aqui.
##
##   scene ...... cena da tela
##   tab ........ aba (TABS) cuja pilha recebe a tela; ausente em fullscreen
##   title ...... chave i18n do título no subcabeçalho (telas empilhadas)
##   fullscreen . true = cena própria, sem barra superior nem navegação

const SHELL_SCENE := "res://presentation/shell/app_shell.tscn"

## Os cinco destinos fixos, na ordem da barra.
const TABS := ["home", "squad", "collection", "club", "shop"]
## Raiz de cada aba (tocar na aba ativa volta para cá).
const TAB_ROOTS := {"home": "home", "squad": "squad", "collection": "collection", "club": "club", "shop": "shop"}
const TAB_LABELS := {"home": "NAV_INICIO", "squad": "NAV_ELENCO", "collection": "NAV_COLECAO", "club": "NAV_CLUBE", "shop": "NAV_LOJA"}
## Ícones (GameIcons) de cada aba.
const TAB_ICONS := {"home": "inicio", "squad": "elenco", "collection": "colecao", "club": "clube", "shop": "loja"}

const TABLE := {
	# Início
	"home": {"scene": "res://presentation/home/home_screen.tscn", "tab": "home", "title": "NAV_INICIO"},
	"modes": {"scene": "res://presentation/home/modes_screen.tscn", "tab": "home", "title": "MODOS_TITULO"},
	"prematch": {"scene": "res://presentation/prematch/prematch_screen.tscn", "tab": "home", "title": "PREJOGO_TITULO"},
	"result": {"scene": "res://presentation/result/result_screen.tscn", "tab": "home", "title": "RESULTADO_TITULO"},
	# Elenco
	"squad": {"scene": "res://presentation/squad/squad_screen.tscn", "tab": "squad", "title": "NAV_ELENCO"},
	"lineup": {"scene": "res://presentation/tactics/tactics_view.tscn", "tab": "squad", "title": "ESCALACAO_TITULO"},
	"athlete": {"scene": "res://presentation/squad/athlete_screen.tscn", "tab": "squad", "title": "ATLETA_TITULO"},
	# Coleção, Clube e Loja
	"collection": {"scene": "res://presentation/collection/collection_screen.tscn", "tab": "collection", "title": "NAV_COLECAO"},
	"club": {"scene": "res://presentation/club/club_screen.tscn", "tab": "club", "title": "NAV_CLUBE"},
	"shop": {"scene": "res://presentation/shop/shop_screen.tscn", "tab": "shop", "title": "NAV_LOJA"},
	# Tela cheia
	"club_creation": {"scene": "res://presentation/onboarding/create_club_screen.tscn", "fullscreen": true},
	"starter_pack": {"scene": "res://presentation/onboarding/starter_pack_screen.tscn", "fullscreen": true},
	"first_lineup": {"scene": "res://presentation/onboarding/first_lineup_screen.tscn", "fullscreen": true},
	"match": {"scene": "res://presentation/match_view/match_view.tscn", "fullscreen": true},
	"sandbox": {"scene": "res://presentation/match_view/match_sandbox_view.tscn", "fullscreen": true},
	"packs_demo": {"scene": "res://presentation/packs/pack_opening_view.tscn", "fullscreen": true},
	"ritual_demo": {"scene": "res://presentation/packs/pack_ritual_demo.tscn", "fullscreen": true},
	"diagnostics": {"scene": "res://presentation/diagnostics/determinism_check.tscn", "fullscreen": true},
}

## Links profundos foteba://<caminho>[/<id>] -> rota (o id vira params.id).
const LINKS := {
	"inicio": "home", "modos": "modes", "prejogo": "prematch", "elenco": "squad", "escalacao": "lineup",
	"atleta": "athlete", "colecao": "collection", "clube": "club", "loja": "shop",
}
const LINK_SCHEME := "foteba://"


static func has(route_id: String) -> bool:
	return TABLE.has(route_id)


static func get_route(route_id: String) -> Dictionary:
	return TABLE.get(route_id, {})


static func is_fullscreen(route_id: String) -> bool:
	return bool(get_route(route_id).get("fullscreen", false))


static func tab_of(route_id: String) -> String:
	return str(get_route(route_id).get("tab", ""))


static func is_root(route_id: String) -> bool:
	var tab := tab_of(route_id)
	return tab != "" and TAB_ROOTS.get(tab) == route_id
