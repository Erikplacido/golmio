class_name MatchTouchBar
extends PanelContainer
## Barra de controles de toque da partida: os mesmos comandos do teclado em botões grandes
## (alvo mínimo de 48 px lógicos), só com ícone: o nome do comando fica na dica e no nome acessível.
## A velocidade fica na MatchSpeedBar, logo acima, com um botão por valor.
## Só emite `action`; quem decide o que fazer é o MatchView.

signal action(id: String)

const BUTTON_H := 48.0

## [id, rótulo, ícone (GameIcons)]
const ITEMS := [
	["pause", "Pausar", "pausar"],
	["critical", "Lance", "pular"],
	["replay", "Replay", "replay"],
	["cutscenes", "Vinhetas", "torcida"],
	["tactics", "Táticas", "tatica"],
	["new", "Nova", "falta"],
	["finish", "Resultado", "estatisticas"],
]
## Itens da partida de demonstração; a do clube do jogador troca por set_actions().
const DEMO_ACTIONS := ["pause", "critical", "replay", "cutscenes", "tactics", "new"]
const ICON_SIZE := 30

var _grid: GridContainer
var _buttons := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(DesignTokens.COLOR_BG_SURFACE, 0.92)
	sb.border_color = DesignTokens.COLOR_BORDER_BASE
	sb.border_width_top = 1
	sb.set_content_margin_all(DesignTokens.SPACING_SM)
	add_theme_stylebox_override("panel", sb)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", DesignTokens.SPACING_SM)
	_grid.add_theme_constant_override("v_separation", DesignTokens.SPACING_SM)
	add_child(_grid)
	for item in ITEMS:
		var b := Button.new()
		b.tooltip_text = item[1]
		b.accessibility_name = item[1]
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, BUTTON_H)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.add_theme_font_size_override("font_size", UiKit.FONT_BODY)
		_style(b, item[0] == "pause")
		if item[0] == "cutscenes":
			b.toggle_mode = true
		GameIcons.apply(b, item[2], ICON_SIZE)
		var id: String = item[0]
		b.pressed.connect(func(): action.emit(id))
		b.visible = DEMO_ACTIONS.has(id)
		_grid.add_child(b)
		_buttons[id] = b
	var gear := GearButton.new()
	gear.custom_minimum_size = Vector2(BUTTON_H, BUTTON_H)
	_style(gear, false)
	_grid.add_child(gear)
	set_width(size.x)


## Mostra só estes comandos (ids de ITEMS), na ordem de ITEMS. A engrenagem fica sempre.
func set_actions(ids: Array) -> void:
	for id in _buttons:
		(_buttons[id] as Button).visible = ids.has(id)
	set_width(size.x)


## Botão de um comando (dicas guiadas apontam para ele); null se não existe.
func button(id: String) -> Button:
	return _buttons.get(id)


func _visible_count() -> int:
	var n := 1   # engrenagem
	for id in _buttons:
		if (_buttons[id] as Button).visible:
			n += 1
	return n


## Ajusta colunas à largura disponível (em pixels lógicos da barra).
func set_width(w: float) -> void:
	if _grid:
		_grid.columns = _visible_count()   # só ícones: cabem numa linha mesmo no celular


## Altura que a barra ocupa com o número de linhas atual.
func bar_height() -> float:
	var rows := ceili(float(_visible_count()) / float(maxi(_grid.columns, 1))) if _grid else 1
	return rows * BUTTON_H + (rows - 1) * DesignTokens.SPACING_SM + DesignTokens.SPACING_SM * 2 + 1


func update_state(paused: bool, speed: float, cutscenes: bool, replaying: bool) -> void:
	if _buttons.is_empty():
		return
	var pause_btn: Button = _buttons["pause"]
	pause_btn.tooltip_text = "Sair do replay" if replaying else ("Continuar" if paused else "Pausar")
	pause_btn.accessibility_name = pause_btn.tooltip_text
	var icon_id := "fechar" if replaying else ("jogar" if paused else "pausar")
	if pause_btn.get_meta("icon_id", "") != icon_id:
		GameIcons.apply(pause_btn, icon_id, ICON_SIZE)
		pause_btn.set_meta("icon_id", icon_id)
	(_buttons["cutscenes"] as Button).set_pressed_no_signal(cutscenes)


func _style(b: Button, primary: bool) -> void:
	b.add_theme_stylebox_override("normal", DesignTokens.style_button(primary, false))
	b.add_theme_stylebox_override("hover", DesignTokens.style_button(primary, true))
	b.add_theme_stylebox_override("pressed", DesignTokens.style_button(true, false, true))
	b.add_theme_stylebox_override("hover_pressed", DesignTokens.style_button(true, true, true))
	b.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_PRIMARY)
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		var s: StyleBox = b.get_theme_stylebox(st)
		s.content_margin_left = 6
		s.content_margin_right = 6
