extends Node
## Ponto de entrada: tela de abertura e depois decide qual rota abrir (Router).
##   sem clube ................ criação de clube (O01) e a estreia guiada;
##   estreia pela metade ...... retoma na etapa salva (pacote, primeira escalação, estreia, tour);
##   com clube ................ Início (H01).
## Diagnóstico de determinismo: URL com ?diag (navegador) ou argumento -- --diag (desktop).
## Pular a abertura: URL com ?skip ou argumento -- --skip-intro. Atalhos de desenvolvimento (também
## pulam): ?tactics / --tactics, ?club_creation / --club-creation, --route=<id> e --link=foteba://...

const TITLE_SCREEN := "res://presentation/title/title_screen.tscn"
## Etapa da estreia -> rota onde ela continua.
const ONBOARDING_ROUTES := {
	GameStore.STAGE_CREATE: "club_creation",
	GameStore.STAGE_STARTER: "starter_pack",
	GameStore.STAGE_FIRST_LINEUP: "first_lineup",
	GameStore.STAGE_DEBUT: "first_lineup",
	GameStore.STAGE_TOUR: "home",
	GameStore.STAGE_DONE: "home",
}


func _ready() -> void:
	if _wants("diag", "--diag"):
		_router().go.call_deferred("diagnostics")
		return
	if _wants("tactics", "--tactics"):
		_router().go.call_deferred("lineup")
		return
	if _wants("club_creation", "--club-creation"):
		_router().go.call_deferred("club_creation")
		return
	if _arg("route") != "" or _arg("link") != "":
		_open_dev_target.call_deferred()
		return
	if _wants("skip", "--skip-intro"):
		_route_main.call_deferred()
		return
	var title: Node = load(TITLE_SCREEN).instantiate()
	add_child(title)
	title.started.connect(func():
		title.queue_free()
		_route_main()
	, CONNECT_ONE_SHOT)


## Depois da abertura: estreia (sem clube ou pela metade) ou Início.
func _route_main() -> void:
	var game: GameStore = get_node_or_null("/root/Game")
	if game:
		game.reload()
	var stage := game.onboarding_stage() if game else GameStore.STAGE_DONE
	_router().reset(ONBOARDING_ROUTES.get(stage, "home"))


func _open_dev_target() -> void:
	var r := _router()
	if _arg("link") != "" and r.open_link(_arg("link")):
		return
	if not r.go(_arg("route")):
		_route_main()


func _router() -> AppRouter:
	return get_node("/root/Router") as AppRouter


func _wants(query: String, arg: String) -> bool:
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("window.location.search", true)).contains(query)
	return OS.get_cmdline_user_args().has(arg)


func _arg(name: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	return ""
