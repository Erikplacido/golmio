class_name ScreenBase
extends Control
## Contrato de tela (docs/PLANO_DE_TELAS.md §6): toda tela nova estende esta classe e ganha os cinco
## estados num padrão só:
##   carregando (esqueleto, nunca tela branca) · vazio (o que vai aparecer e como conseguir) ·
##   erro (o que houve + Tentar de novo) · offline (último dado salvo, ações de servidor desligadas)
##   · pronto (o conteúdo, com no máximo uma ação principal em amarelo).
##
## Ciclo: o Router/AppShell chama setup(rota, params) antes de pôr na árvore; no _ready a tela monta
## a estrutura em build() e preenche em refresh(). Ao voltar a ser exibida (pilha da aba), on_shown()
## refaz se o Game mudou enquanto ela estava escondida.
##
## Subclasses: sobrescrevam build() (estrutura fixa, em `content`) e refresh() (dados -> estado);
## handle_back() -> true para vetar o voltar (ex.: alterações não salvas).

enum State { LOADING, EMPTY, ERROR, OFFLINE, READY }

signal state_changed(state: int)

## Respiro em volta do conteúdo (px lógicos).
const PAD := 16.0

## Largura máxima da coluna de conteúdo (telas largas). 0 = sem limite.
var max_content_width := 980.0
var route_id := ""
var params: Dictionary = {}
var state: int = State.LOADING
## Onde a tela monta o conteúdo do estado "pronto".
var content: VBoxContainer
## true quando está dentro da casca (barra superior e navegação já existem).
var embedded := false
## Estado injetado (testes e ferramentas); sem ele, o autoload Game.
var store: GameStore = null

var _column: Control
var _frame: UiScaledFrame = null
var _state_box: VBoxContainer
var _revision_seen := -1


func setup(p_route: String, p_params: Dictionary) -> void:
	route_id = p_route
	params = p_params.duplicate(true)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = DesignTokens.base_theme()
	var host: Control = self
	if not embedded:
		add_child(UiFrames.paper_background())
		# Fora da casca ninguém amplia a tela para leitura: a moldura faz isso (UiScaledFrame).
		_frame = UiScaledFrame.new()
		_frame.name = "ScaledFrame"
		add_child(_frame)
		host = _frame
	_column = UiKit.column(max_content_width if max_content_width > 0.0 else 100000.0)
	_column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(_column)
	var stack := Control.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(stack)
	content = UiKit.vbox(DesignTokens.SPACING_MD)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, int(PAD))
	stack.add_child(content)
	_state_box = UiKit.vbox(DesignTokens.SPACING_MD)
	_state_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, int(PAD))
	_state_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_state_box.visible = false
	stack.add_child(_state_box)
	build()
	_refresh_now()


## Tamanho em px lógicos (o que o layout deve usar): o da moldura de leitura fora da casca.
func logical_size() -> Vector2:
	return _frame.size if _frame else size


## Monta a estrutura fixa da tela em `content`. Chamado uma vez.
func build() -> void:
	pass


## Lê os dados e escolhe o estado (show_ready, show_empty...). Chamado no início, ao voltar a
## exibir com dados novos e pelo "Tentar de novo".
func refresh() -> void:
	show_ready()


## Título do subcabeçalho da casca (telas empilhadas). "" = o da tabela de rotas.
func screen_title() -> String:
	return ""


## true = a tela tratou o voltar (o Router não desempilha).
func handle_back() -> bool:
	return false


## Chamado pela casca quando a tela volta ao topo da pilha.
func on_shown() -> void:
	if _game_revision() != _revision_seen:
		_refresh_now()


func _refresh_now() -> void:
	_revision_seen = _game_revision()
	refresh()


func _game_revision() -> int:
	var g := game()
	return g.revision if g else 0


## O estado do jogador: o injetado em `store` ou o autoload Game (null fora do jogo).
func game() -> GameStore:
	if store != null:
		return store
	return get_node_or_null("/root/Game") as GameStore if is_inside_tree() else null


func router() -> AppRouter:
	return get_node_or_null("/root/Router") as AppRouter if is_inside_tree() else null


## Navega (sem Router — tela aberta solta no editor — não faz nada).
func go(route: String, p: Dictionary = {}) -> void:
	var r := router()
	if r:
		r.go(route, p)


# --- estados --------------------------------------------------------------------------------

func show_ready() -> void:
	_set_state(State.READY)


## Esqueleto com o formato da tela (blocos de papel), nunca tela branca.
func show_loading() -> void:
	_fill_state([_skeleton(56), _skeleton(160), _skeleton(96), _skeleton(96)], false)
	_set_state(State.LOADING)


func show_empty(icon_id: String, heading: String, text: String, action_label: String = "", action: Callable = Callable()) -> void:
	_fill_state([UiKit.empty_state(icon_id, heading, text, action_label, action)])
	_set_state(State.EMPTY)


## Erro: o que aconteceu e "Tentar de novo" (chama refresh()).
func show_error(text: String, retry: bool = true) -> void:
	var box := UiKit.empty_state("erro", tr("ESTADO_ERRO_TITULO"), text,
		tr("UI_TENTAR_NOVAMENTE") if retry else "", _refresh_now if retry else Callable())
	_fill_state([box])
	_set_state(State.ERROR)


## Offline: mantém o conteúdo (último dado salvo) e mostra a faixa do aviso por cima.
func show_offline(text: String = "") -> void:
	var banner := UiKit.card(Color("#fde2dc"), "ui_aviso")
	var h := UiKit.hbox(DesignTokens.SPACING_SM)
	h.add_child(GameIcons.rect("bloqueado", 24))
	h.add_child(UiKit.label(text if text != "" else tr("ESTADO_OFFLINE"), UiKit.FONT_BODY, UiKit.INK, true))
	banner.add_child(h)
	_fill_state([banner])
	_state_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	content.visible = true
	_state_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_state(State.OFFLINE)


func _set_state(s: int) -> void:
	state = s
	content.visible = s in [State.READY, State.OFFLINE]
	_state_box.visible = s != State.READY
	state_changed.emit(s)


func _fill_state(nodes: Array, centered: bool = true) -> void:
	for c in _state_box.get_children():
		c.queue_free()
	_state_box.alignment = BoxContainer.ALIGNMENT_CENTER if centered else BoxContainer.ALIGNMENT_BEGIN
	_state_box.mouse_filter = Control.MOUSE_FILTER_STOP
	for n in nodes:
		_state_box.add_child(n)


func _skeleton(h: float) -> Control:
	var p := UiKit.card(DesignTokens.COLOR_BG_HOVER)
	p.custom_minimum_size = Vector2(0, h)
	p.modulate = Color(1, 1, 1, 0.6)
	return p


## Remove todos os filhos de um contêiner (listas refeitas no refresh).
static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
