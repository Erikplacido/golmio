class_name AppRouter
extends Node
## Autoload "Router": navegação do app (docs/PLANO_DE_TELAS.md §2).
##   - rotas por id (Routes.TABLE); go() empilha na aba dona da rota e troca de aba se precisar;
##   - cada aba guarda a própria pilha: trocar de aba e voltar mantém onde o jogador estava;
##   - tocar na aba ativa volta para a raiz dela;
##   - back() desfaz o último passo (Esc, botão voltar do Android, botão na tela): fecha a
##     sobreposição aberta, sai da tela cheia, desempilha, volta para o Início e, na raiz do Início,
##     pede confirmação antes de fechar o app;
##   - links profundos foteba://atleta/<id> montam a pilha da aba certa (open_link);
##   - sobreposições do sistema (modal, toast, coach mark) em `overlays`, por cima de qualquer cena.
## A casca (AppShell) desenha a pilha; telas de tela cheia são cenas próprias (change_scene).
## Tela que quer vetar o voltar (alterações não salvas, partida em andamento) implementa
## handle_back() -> bool (true = já tratou).

signal route_changed(route_id: String, params: Dictionary)

## Abaixo do painel de Configurações (100), acima das vinhetas e do HUD (15–20).
const OVERLAY_LAYER := 90

var current_tab := "home"
var overlays: OverlayLayer
## aba -> Array de entradas {uid, route, params}
var _stacks := {}
## Rota de tela cheia aberta agora ({} = casca).
var _fullscreen := {}
var _shell: Node = null
var _next_uid := 0
## Última troca de cena pedida (fora da árvore, como nos testes, só fica registrada aqui).
var last_scene_request := ""


func _init() -> void:
	reset_stacks()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlays = OverlayLayer.new()
	overlays.name = "Overlays"
	overlays.layer = OVERLAY_LAYER
	add_child(overlays)
	# O botão voltar do Android chega como NOTIFICATION_WM_GO_BACK_REQUEST em vez de fechar o app.
	get_tree().quit_on_go_back = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if back():
			get_viewport().set_input_as_handled()


# --- navegação --------------------------------------------------------------------------------

## Abre a rota. Na casca, empilha na aba dela (ir para a raiz de uma aba limpa a pilha dela); em
## tela cheia, troca a cena. false se a rota não existe.
func go(route_id: String, params: Dictionary = {}) -> bool:
	if not Routes.has(route_id):
		push_warning("Router: rota desconhecida '%s'" % route_id)
		return false
	if Routes.is_fullscreen(route_id):
		_fullscreen = {"uid": _uid(), "route": route_id, "params": params.duplicate(true)}
		_change_scene(str(Routes.get_route(route_id).scene))
		route_changed.emit(route_id, params)
		return true
	var tab := Routes.tab_of(route_id)
	var stack: Array = _stacks[tab]
	var entry := {"uid": _uid(), "route": route_id, "params": params.duplicate(true)}
	if Routes.is_root(route_id):
		stack = [entry]
	elif stack.back().route == route_id and stack.back().params == params:
		pass   # já está no topo: só mostra
	else:
		stack.append(entry)
	_stacks[tab] = stack
	current_tab = tab
	_fullscreen = {}
	_show_shell()
	return true


## Troca o topo da pilha da aba atual (sub-abas, como Atletas · Escalação).
func replace(route_id: String, params: Dictionary = {}) -> bool:
	if not Routes.has(route_id) or Routes.is_fullscreen(route_id) or Routes.tab_of(route_id) != current_tab:
		return go(route_id, params)
	var stack: Array = _stacks[current_tab]
	if stack.size() <= 1:
		return go(route_id, params)
	stack[stack.size() - 1] = {"uid": _uid(), "route": route_id, "params": params.duplicate(true)}
	_fullscreen = {}
	_show_shell()
	return true


## Vai para a aba (mantém a pilha dela). Tocar na aba ativa volta para a raiz.
func switch_tab(tab: String) -> void:
	if not Routes.TABS.has(tab):
		return
	if tab == current_tab and _fullscreen.is_empty():
		var stack: Array = _stacks[tab]
		if stack.size() > 1:
			_stacks[tab] = [stack[0]]
	current_tab = tab
	_fullscreen = {}
	_show_shell()


## Desfaz o último passo. false quando não há o que desfazer (ex.: tela de abertura).
func back() -> bool:
	if overlays and overlays.close_top():
		return true
	var scene := get_tree().current_scene if is_inside_tree() else null
	if not _fullscreen.is_empty():
		if scene and scene.has_method("handle_back") and scene.handle_back():
			return true
		_fullscreen = {}
		_show_shell()
		return true
	if _shell == null or not is_instance_valid(_shell):
		return false
	var screen: Node = _shell.current_screen() if _shell.has_method("current_screen") else null
	if screen and screen.has_method("handle_back") and screen.handle_back():
		return true
	var stack: Array = _stacks[current_tab]
	if stack.size() > 1:
		stack.pop_back()
		_show_shell()
		return true
	if current_tab != "home":
		current_tab = "home"
		_show_shell()
		return true
	confirm_quit()
	return true


## Limpa todas as pilhas e abre a rota (fim da estreia, troca de clube).
func reset(route_id: String = "home", params: Dictionary = {}) -> bool:
	reset_stacks()
	return go(route_id, params)


func reset_stacks() -> void:
	for tab in Routes.TABS:
		_stacks[tab] = [{"uid": _uid(), "route": Routes.TAB_ROOTS[tab], "params": {}}]
	current_tab = "home"


## foteba://atleta/<id> -> pilha [Elenco, Ficha]. false se o link não é conhecido.
func open_link(url: String) -> bool:
	if not url.begins_with(Routes.LINK_SCHEME):
		return false
	var parts := url.trim_prefix(Routes.LINK_SCHEME).split("/", false)
	if parts.is_empty():
		return go("home")
	var route := str(Routes.LINKS.get(parts[0], ""))
	if route == "":
		return false
	var params := {"id": parts[1].uri_decode()} if parts.size() > 1 else {}
	if not Routes.is_fullscreen(route) and not Routes.is_root(route):
		var tab := Routes.tab_of(route)
		_stacks[tab] = [{"uid": _uid(), "route": Routes.TAB_ROOTS[tab], "params": {}}]
	return go(route, params)


## Pede confirmação e fecha o app (no navegador não há o que fechar).
func confirm_quit() -> void:
	if OS.has_feature("web") or overlays == null:
		return
	overlays.confirm(tr("SAIR_TITULO"), tr("SAIR_TEXTO"), tr("SAIR_CONFIRMAR"),
		func() -> void: get_tree().quit(), true)


# --- estado (para a casca e as telas) -----------------------------------------------------------

## Entrada no topo: a tela cheia aberta ou o topo da aba atual.
func top() -> Dictionary:
	return _fullscreen if not _fullscreen.is_empty() else _stacks[current_tab].back()


func current_route() -> String:
	return str(top().get("route", ""))


func current_params() -> Dictionary:
	return top().get("params", {})


func is_fullscreen() -> bool:
	return not _fullscreen.is_empty()


func stack(tab: String = "") -> Array:
	return _stacks.get(tab if tab != "" else current_tab, [])


func depth(tab: String = "") -> int:
	return stack(tab).size()


## uids de todas as entradas vivas (a casca solta as telas que saíram das pilhas).
func live_uids() -> Dictionary:
	var out := {}
	for tab in _stacks:
		for e in _stacks[tab]:
			out[e.uid] = true
	return out


# --- casca ----------------------------------------------------------------------------------

## A casca se registra ao entrar na árvore e desenha o topo da pilha.
func attach_shell(shell: Node) -> void:
	_shell = shell
	_fullscreen = {}
	shell.tree_exiting.connect(func() -> void:
		if _shell == shell:
			_shell = null
	, CONNECT_ONE_SHOT)


func _show_shell() -> void:
	if _shell != null and is_instance_valid(_shell):
		_shell.render()
	else:
		_change_scene(Routes.SHELL_SCENE)
	route_changed.emit(current_route(), current_params())


func _change_scene(path: String) -> void:
	last_scene_request = path
	if not is_inside_tree():
		return
	if overlays:
		overlays.clear()
	get_tree().change_scene_to_file.call_deferred(path)


func _uid() -> int:
	_next_uid += 1
	return _next_uid
