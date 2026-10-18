class_name MatchSpeedBar
extends PanelContainer
## Faixa de controle da partida, sempre visível (com ou sem barra de toque): velocidade em botões
## diretos (1× a 5×, um toque para cada) e, só em build de desenvolvimento, "Finalizar agora",
## que encerra a partida no placar do momento. Só emite sinais; quem decide é o MatchView.

signal speed_picked(value: float)
signal end_now_pressed

const BUTTON_H := 48.0
## Abaixo desta largura (px lógicos) some o rótulo "Velocidade" e o botão de encerrar fica curto.
const NARROW := 560.0

var _label: Label
var _icon: TextureRect
var _speed_buttons := {}   # valor -> Button
var _end_button: Button
var _end_gap: Control
var _narrow := false


## `speeds`: valores oferecidos (MatchView.SPEEDS). `allow_end_now`: mostra "Finalizar agora".
func _init(speeds: Array = [0.25, 0.5, 1.0, 2.0, 3.0, 4.0, 5.0], allow_end_now := false) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(DesignTokens.COLOR_BG_SURFACE, 0.92)
	sb.border_color = DesignTokens.COLOR_BORDER_BASE
	sb.border_width_top = 1
	sb.set_content_margin_all(DesignTokens.SPACING_SM)
	add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DesignTokens.SPACING_XS)
	add_child(row)

	_icon = GameIcons.rect("acelerar", 22)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_icon)
	_label = UiKit.label(tr("PARTIDA_VELOCIDADE"), UiKit.FONT_SMALL, UiKit.INK)
	_label.add_theme_font_override("font", DesignTokens.text_font(DesignTokens.WEIGHT_SEMIBOLD))
	_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_label)

	for v in speeds:
		var value := float(v)
		var b := Button.new()
		b.text = MatchSpeedBar.label_for(value)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(BUTTON_H, BUTTON_H)
		b.tooltip_text = tr("PARTIDA_VELOCIDADE_DICA") % MatchSpeedBar.label_for(value)
		b.add_theme_font_size_override("font_size", UiKit.FONT_BODY)
		b.add_theme_font_override("font", DesignTokens.display_font())
		b.pressed.connect(func() -> void: speed_picked.emit(value))
		row.add_child(b)
		_speed_buttons[value] = b

	if allow_end_now:
		_end_gap = UiKit.spacer(DesignTokens.SPACING_SM)
		row.add_child(_end_gap)
		_end_button = UiKit.button(tr("PARTIDA_ENCERRAR_AGORA"), "destructive", "fechar", BUTTON_H)
		_end_button.focus_mode = Control.FOCUS_NONE
		_end_button.tooltip_text = tr("PARTIDA_ENCERRAR_DICA")
		_end_button.add_theme_font_size_override("font_size", UiKit.FONT_SMALL)
		_end_button.pressed.connect(func() -> void: end_now_pressed.emit())
		row.add_child(_end_button)
	set_speed(1.0)


## Marca a velocidade atual (amarelo = selecionada).
func set_speed(value: float) -> void:
	for v in _speed_buttons:
		var b: Button = _speed_buttons[v]
		b.set_pressed_no_signal(v == value)
		UiKit.style_button(b, "primary" if v == value else "secondary")
		if _narrow:
			# Celular: o botão fica no alvo de toque (48) sem o respiro lateral da arte.
			for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
				DesignTokens.compact_margins(b.get_theme_stylebox(st), 4, 4)


## Botão de uma velocidade (dicas guiadas apontam para ele); null se não existe.
func speed_button(value: float) -> Button:
	return _speed_buttons.get(value)


## Some/mostra "Finalizar agora" (some depois que a partida acabou).
func set_end_enabled(on: bool) -> void:
	if _end_button:
		_end_button.disabled = not on


func set_width(w: float) -> void:
	var narrow := w < NARROW
	if narrow != _narrow:
		_narrow = narrow
		for v in _speed_buttons:
			if (_speed_buttons[v] as Button).button_pressed:
				set_speed(v)
	_label.visible = not narrow
	# Celular em retrato: sete botões de 48 + ícone não cabem em ~360 px lógicos (o 5× saía da tela).
	# Sem o ícone, os botões dividem a largura toda e encolhem até 34.
	_icon.visible = not narrow
	for v in _speed_buttons:
		var b: Button = _speed_buttons[v]
		b.custom_minimum_size.x = 34.0 if narrow else BUTTON_H
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL if narrow else Control.SIZE_FILL
		b.clip_text = narrow
	if _end_button:
		_end_button.text = "" if narrow else tr("PARTIDA_ENCERRAR_AGORA")
		_end_button.custom_minimum_size.x = BUTTON_H if narrow else 0.0
		_end_gap.custom_minimum_size.x = 0.0 if narrow else DesignTokens.SPACING_SM
		# Só o ícone no estreito: sem o respiro da arte ele fica nos 48 do alvo de toque.
		UiKit.style_button(_end_button, "destructive")
		if narrow:
			for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
				DesignTokens.compact_margins(_end_button.get_theme_stylebox(st), 4, 4)


func bar_height() -> float:
	return BUTTON_H + DesignTokens.SPACING_SM * 2 + 1


## "¼×", "½×", "1×" ... "5×".
static func label_for(value: float) -> String:
	if is_equal_approx(value, 0.25):
		return "¼×"
	return "½×" if is_equal_approx(value, 0.5) else "%d×" % roundi(value)
