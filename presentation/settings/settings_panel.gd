extends Control
## Painel de configurações (overlay do autoload Settings). Responsivo: o cartão ocupa até 760×660
## lógicos e, em telas estreitas, os controles descem para baixo do texto de cada linha.
## Toda mudança vale na hora e é salva; mudanças de janela no desktop pedem confirmação e voltam
## sozinhas em CONFIRM_SECONDS (uma resolução que não cabe no monitor não deixa o jogador preso).

const CONFIRM_SECONDS := 12.0
const NARROW_WIDTH := 560.0
const CONTROL_WIDTH := 230.0

const SECTION_TITLES := {
	"display": "Tela",
	"performance": "Desempenho",
	"gameplay": "Partida",
	"controls": "Controles",
	"audio": "Áudio",
	"accessibility": "Acessibilidade",
}

## key -> [título, descrição]
const TEXTS := {
	"window_mode": ["Modo de exibição", "Janela, maximizada ou tela cheia. Atalho: F11 ou Alt+Enter."],
	"resolution": ["Tamanho da janela", "Vale no modo janela. Automático ocupa cerca de 85% do monitor."],
	"screen": ["Monitor", "Em qual monitor o jogo abre."],
	"aspect": ["Ajuste à tela", "Preencher usa toda a área em monitores ultrawide, 4:3, retrato e celulares. Manter conserva o enquadramento original com faixas nas bordas."],
	"ui_scale": ["Escala da interface", "Tamanho de textos e botões. A automática aumenta em telas pequenas."],
	"orientation": ["Orientação", "Como o jogo fica no aparelho. No navegador do celular só vale em tela cheia."],
	"vsync": ["Sincronia vertical (V-Sync)", "Evita cortes na imagem. A adaptativa reduz travadas quando o FPS cai."],
	"max_fps": ["Limite de FPS", "Limitar reduz consumo de energia, ruído e aquecimento."],
	"msaa_2d": ["Suavização de bordas (MSAA 2D)", "Bordas mais lisas no campo e nos jogadores. Custa desempenho."],
	"battery_saver": ["Economia de bateria", "Limita a 30 FPS e só redesenha os menus quando algo muda."],
	"show_fps": ["Mostrar FPS", "Contador no canto superior esquerdo."],
	"match_speed": ["Velocidade inicial da partida", "¼× = 90 minutos em 10 min reais; ½× em 5 min; 1× em 2 min 30 s; 5× em 30 s. Durante o jogo: teclas 9 (¼×), 0 (½×) e 1 a 5."],
	"cutscenes": ["Vinhetas de lances", "Arte em tela cheia em gols, faltas, cartões e bolas paradas. Atalho: V."],
	"cutscene_length": ["Duração das vinhetas", "Toque ou Espaço sempre fecham a vinheta antes."],
	"auto_replay": ["Replay no lance crítico", "Ao pular para o próximo lance crítico, mostra o replay dele."],
	"pause_on_focus_loss": ["Pausar ao sair do jogo", "Pausa quando a janela ou a aba perde o foco, ou o app vai para segundo plano."],
	"touch_controls": ["Controles na tela", "Barra de botões durante a partida. Automático: só em telas de toque."],
	"key_hints": ["Dicas de teclado", "Mostra os atalhos no placar. Automático: some em telas de toque."],
	"volume_master": ["Volume geral", ""],
	"volume_music": ["Música", ""],
	"volume_sfx": ["Efeitos e torcida", ""],
	"mute": ["Silenciar tudo", ""],
	"mute_unfocused": ["Silenciar em segundo plano", "Corta o som quando a janela ou a aba perde o foco."],
	"reduce_motion": ["Reduzir movimento", "Vinhetas sem zoom nem esmaecimento e replays sem câmera lenta."],
	"team_markers": ["Marcadores de time", "Visitantes ganham anel duplo: dá para distinguir os times sem depender da cor."],
}

const OPTION_LABELS := {
	"window_mode": {"windowed": "Janela", "maximized": "Janela maximizada",
		"fullscreen": "Tela cheia", "exclusive_fullscreen": "Tela cheia exclusiva"},
	"aspect": {"expand": "Preencher (recomendado)", "keep": "Manter proporção"},
	"orientation": {"auto": "Livre (gira com o aparelho)", "portrait": "Travar em retrato", "landscape": "Travar em paisagem"},
	"vsync": {"on": "Ligada", "adaptive": "Adaptativa", "off": "Desligada"},
	"cutscene_length": {"short": "Curta", "normal": "Normal", "long": "Longa"},
	"touch_controls": {"auto": "Automático", "on": "Sempre", "off": "Nunca"},
	"key_hints": {"auto": "Automático", "on": "Sempre", "off": "Nunca"},
	"match_speed": {0.25: "¼×", 0.5: "½×", 1.0: "1×", 2.0: "2×", 3.0: "3×", 4.0: "4×", 5.0: "5×"},
	"msaa_2d": {0: "Desligada", 2: "2×", 4: "4×"},
}

const SHORTCUTS := [
	["F10", "Abrir/fechar configurações"],
	["F11 · Alt+Enter", "Alternar tela cheia"],
	["Esc", "Fechar painel · sair do replay"],
	["Espaço", "Pausar/continuar a partida"],
	["1 a 5", "Velocidade da partida"],
	["C", "Pular para o próximo lance crítico"],
	["P", "Replay do último lance"],
	["V", "Ligar/desligar vinhetas"],
	["T", "Táticas"],
	["R", "Nova partida"],
]

## Settings (autoload); injetado antes de entrar na árvore.
var service: Node

var _card: PanelContainer
var _tabs: TabContainer
var _controls := {}          # key -> Control
var _rows := {}              # key -> Control (linha inteira)
var _info_label: Label
var _confirm_bar: PanelContainer
var _confirm_label: Label
var _confirm_left := 0.0
var _confirm_snapshot := {}
var _narrow := false
var _built := false
var _popup_scale := 1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = _make_theme()
	var dim := ColorRect.new()
	dim.color = Color(DesignTokens.COLOR_INK, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", DesignTokens.style_window())
	add_child(_card)
	resized.connect(_layout)
	service.changed.connect(_on_setting_changed)


func open(tab: String = "") -> void:
	visible = true
	_rebuild()
	if tab != "":
		var idx := _section_index(tab)
		if idx >= 0:
			_tabs.current_tab = idx
	_layout()


func close() -> void:
	if not _confirm_snapshot.is_empty():
		_confirm_keep()
	visible = false


func _process(delta: float) -> void:
	if not visible or _confirm_snapshot.is_empty():
		return
	_confirm_left -= delta
	if _confirm_left <= 0.0:
		_confirm_revert()
	else:
		_confirm_label.text = "Manter esta configuração de tela? Voltando à anterior em %d s." % ceili(_confirm_left)


# --- layout -------------------------------------------------------------------------------------------

func _layout() -> void:
	if _card == null:
		return
	# Em telas que encolhem o layout (celular em retrato), o cartão é ampliado por `k` para o texto
	# e os alvos de toque continuarem com tamanho físico decente.
	var k: float = service.readability_scale()
	var vp := size / k
	var margin := 8.0 if vp.x < NARROW_WIDTH else 24.0
	var max_h := 660.0 if vp.x >= NARROW_WIDTH else 1000.0
	var card_size := Vector2(minf(vp.x - margin * 2.0, 760.0), minf(vp.y - margin * 2.0, max_h))
	_card.scale = Vector2(k, k)
	_card.size = card_size
	_card.position = (size - card_size * k) / 2.0
	_popup_scale = k
	var narrow := card_size.x < NARROW_WIDTH
	if narrow != _narrow and _built:
		_narrow = narrow
		_rebuild()
	_narrow = narrow
	_update_info()


func _rebuild() -> void:
	var current := _tabs.current_tab if _tabs else 0
	for c in _card.get_children():
		_card.remove_child(c)
		c.queue_free()
	_controls.clear()
	_rows.clear()
	_narrow = size.x / service.readability_scale() - 16.0 < NARROW_WIDTH

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", DesignTokens.SPACING_MD)
	_card.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", DesignTokens.SPACING_SM)
	root.add_child(header)
	var title := Label.new()
	title.text = "Configurações".to_upper()
	title.add_theme_font_size_override("font_size", UiKit.FONT_H2)
	title.add_theme_font_override("font", DesignTokens.display_font())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "Fechar"
	close_btn.custom_minimum_size = Vector2(110, 40)
	GameIcons.apply(close_btn, "fechar", 18)
	close_btn.pressed.connect(func(): service.close_panel())
	header.add_child(close_btn)

	_confirm_bar = _build_confirm_bar()
	root.add_child(_confirm_bar)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.clip_tabs = true
	root.add_child(_tabs)
	for section in GameSettings.SECTIONS:
		var page := _build_section(section)
		if page == null:
			continue
		_tabs.add_child(page)
		_tabs.set_tab_title(_tabs.get_tab_count() - 1, SECTION_TITLES[section])
	_tabs.current_tab = clampi(current, 0, _tabs.get_tab_count() - 1)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", DesignTokens.SPACING_SM)
	root.add_child(footer)
	var hint := Label.new()
	hint.text = "As mudanças valem na hora e ficam salvas neste aparelho."
	hint.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	hint.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_MUTED)
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hint.clip_text = true
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint.tooltip_text = hint.text
	hint.mouse_filter = Control.MOUSE_FILTER_PASS
	footer.add_child(hint)
	var reset := Button.new()
	reset.text = "Restaurar padrões da aba"
	reset.custom_minimum_size = Vector2(0, 40)
	reset.pressed.connect(func():
		var page := _tabs.get_current_tab_control()
		if page:
			service.reset_section(str(page.get_meta("section")))
	)
	footer.add_child(reset)

	_built = true
	_refresh_all()


func _build_section(section: String) -> Control:
	var s: GameSettings = service.settings
	var keys: Array = s.keys_in(section).filter(func(k): return s.is_available(k))
	if keys.is_empty() and section != "controls":
		return null
	var scroll := ScrollContainer.new()
	scroll.name = section
	scroll.set_meta("section", section)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, DesignTokens.SPACING_MD)
	scroll.add_child(margin)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", DesignTokens.SPACING_LG)
	margin.add_child(list)
	for key in keys:
		list.add_child(_build_row(key))
	if section == "display":
		_info_label = Label.new()
		_info_label.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
		_info_label.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_MUTED)
		_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(HSeparator.new())
		list.add_child(_info_label)
	elif section == "controls":
		list.add_child(HSeparator.new())
		list.add_child(_build_shortcuts())
	elif section == "audio":
		var note := Label.new()
		note.text = "Os barramentos Música e Efeitos já existem; sons novos devem tocar neles para respeitar estes volumes."
		note.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
		note.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_MUTED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(note)
	return scroll


func _build_row(key: String) -> Control:
	var row: BoxContainer = VBoxContainer.new() if _narrow else HBoxContainer.new()
	row.add_theme_constant_override("separation", DesignTokens.SPACING_SM if _narrow else DesignTokens.SPACING_LG)
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 2)
	row.add_child(text_box)
	var t: Array = TEXTS.get(key, [key, ""])
	var title := Label.new()
	title.text = t[0]
	title.add_theme_font_size_override("font_size", UiKit.FONT_BODY)
	title.add_theme_font_override("font", DesignTokens.text_font(DesignTokens.WEIGHT_SEMIBOLD))
	text_box.add_child(title)
	var desc_text: String = t[1]
	if key == "window_mode" and bool(service.platform.get("web", false)):
		desc_text = "No navegador, a tela cheia esconde barras e abas. Atalho: F11."
	if desc_text != "":
		var desc := Label.new()
		desc.text = desc_text
		desc.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
		desc.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_SECONDARY)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_box.add_child(desc)

	var control := _build_control(key)
	if _narrow:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		control.custom_minimum_size.x = CONTROL_WIDTH
		control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	_controls[key] = control
	_rows[key] = row
	return row


func _build_control(key: String) -> Control:
	var spec: Dictionary = GameSettings.SCHEMA[key]
	var def: Variant = spec["default"]
	if def is bool:
		var cb := CheckButton.new()
		cb.text = ""
		cb.custom_minimum_size.y = 40
		cb.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cb.toggled.connect(func(on: bool): service.set_value(key, on))
		return cb
	if def is int and spec.has("min") and key != "screen":
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", DesignTokens.SPACING_SM)
		var slider := HSlider.new()
		slider.min_value = spec["min"]
		slider.max_value = spec["max"]
		slider.step = 5
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.custom_minimum_size.y = 32
		var value_lbl := Label.new()
		value_lbl.custom_minimum_size.x = 44
		value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		slider.value_changed.connect(func(v: float):
			value_lbl.text = "%d%%" % int(v)
			service.set_value(key, int(v))
		)
		box.add_child(slider)
		box.add_child(value_lbl)
		box.set_meta("slider", slider)
		box.set_meta("value_label", value_lbl)
		return box
	var opt := OptionButton.new()
	opt.custom_minimum_size.y = 40
	opt.fit_to_longest_item = false
	opt.clip_text = true
	opt.item_selected.connect(func(idx: int): _on_option_selected(key, opt.get_item_metadata(idx)))
	# A lista suspensa é outra janela: não herda a escala do cartão.
	opt.pressed.connect(func(): opt.get_popup().content_scale_factor = _popup_scale)
	return opt


func _on_option_selected(key: String, value: Variant) -> void:
	var risky := key in GameSettings.RISKY_KEYS and bool(service.platform.get("desktop", false))
	if risky and _confirm_snapshot.is_empty():
		for k in GameSettings.RISKY_KEYS:
			_confirm_snapshot[k] = service.get_value(k)
	service.set_value(key, value)
	if risky and not _confirm_snapshot.is_empty():
		_confirm_left = CONFIRM_SECONDS
		_confirm_bar.visible = true


# --- confirmação de tela ------------------------------------------------------------------------------

func _build_confirm_bar() -> PanelContainer:
	var bar := PanelContainer.new()
	var sb := DesignTokens.style_badge(DesignTokens.COLOR_ACCENT_GOLD, DesignTokens.RADIUS_MD)
	sb.set_content_margin_all(DesignTokens.SPACING_SM)
	bar.add_theme_stylebox_override("panel", sb)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", DesignTokens.SPACING_SM)
	bar.add_child(box)
	_confirm_label = Label.new()
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_label.custom_minimum_size.x = 160
	_confirm_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(_confirm_label)
	var keep := Button.new()
	keep.text = "Manter"
	keep.custom_minimum_size = Vector2(100, 36)
	GameIcons.apply(keep, "confirmar", 18)
	keep.pressed.connect(_confirm_keep)
	box.add_child(keep)
	var undo := Button.new()
	undo.text = "Desfazer"
	undo.custom_minimum_size = Vector2(110, 36)
	GameIcons.apply(undo, "voltar", 18)
	undo.pressed.connect(_confirm_revert)
	box.add_child(undo)
	bar.visible = not _confirm_snapshot.is_empty()
	return bar


func _confirm_keep() -> void:
	_confirm_snapshot.clear()
	if _confirm_bar:
		_confirm_bar.visible = false


func _confirm_revert() -> void:
	var snap := _confirm_snapshot.duplicate()
	_confirm_snapshot.clear()
	_confirm_bar.visible = false
	for k in snap:
		service.set_value(k, snap[k])


# --- valores ------------------------------------------------------------------------------------------

func _on_setting_changed(key: String, _value: Variant) -> void:
	if not visible or not _built:
		return
	if key in ["window_mode", "ui_scale", "cutscenes", "mute"]:
		_refresh_all()
	else:
		_refresh(key)
	_update_info()


func _refresh_all() -> void:
	for key in _controls:
		_refresh(key)


func _refresh(key: String) -> void:
	var control: Control = _controls.get(key)
	if control == null:
		return
	var value: Variant = service.get_value(key)
	if control is CheckButton:
		control.set_pressed_no_signal(bool(value))
	elif control is OptionButton:
		_fill_options(key, control, value)
	elif control.has_meta("slider"):
		var slider: HSlider = control.get_meta("slider")
		slider.set_value_no_signal(float(value))
		(control.get_meta("value_label") as Label).text = "%d%%" % int(value)
	var row: Control = _rows.get(key)
	if row:
		var enabled := _is_enabled(key)
		row.modulate.a = 1.0 if enabled else 0.45
		if control is BaseButton:
			control.disabled = not enabled
		elif control.has_meta("slider"):
			(control.get_meta("slider") as HSlider).editable = enabled


func _is_enabled(key: String) -> bool:
	match key:
		"resolution":
			return str(service.get_value("window_mode")) == "windowed"
		"cutscene_length":
			return bool(service.get_value("cutscenes"))
		"volume_master", "volume_music", "volume_sfx":
			return not bool(service.get_value("mute"))
	return true


func _fill_options(key: String, opt: OptionButton, value: Variant) -> void:
	var s: GameSettings = service.settings
	var items: Array = []   # [label, valor]
	match key:
		"resolution":
			for r in s.resolution_options(service.usable_screen_size()):
				items.append([_resolution_label(r), r])
		"screen":
			items.append(["Atual", -1])
			for sc in service.screen_options():
				items.append(["Monitor %d (%d × %d)" % [sc.index + 1, sc.size.x, sc.size.y], sc.index])
		"ui_scale":
			for o in s.options(key):
				var label := "%d%%" % roundi(float(o) * 100.0)
				if float(o) <= 0.0:
					label = "Automática (%d%%)" % roundi(service.auto_ui_scale() * 100.0)
				items.append([label, o])
		"max_fps":
			for o in s.options(key):
				items.append(["Sem limite" if int(o) == 0 else "%d FPS" % int(o), o])
		_:
			var labels: Dictionary = OPTION_LABELS.get(key, {})
			for o in s.options(key):
				items.append([str(labels.get(o, o)), o])
	opt.clear()
	var selected := -1
	for i in items.size():
		opt.add_item(items[i][0])
		opt.set_item_metadata(i, items[i][1])
		if _same(items[i][1], value):
			selected = i
	opt.select(selected)


func _same(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b))
	return str(a) == str(b)


func _resolution_label(r: String) -> String:
	if r == "auto":
		var auto := GameSettings.auto_window_size(service.usable_screen_size())
		return "Automático (%d × %d)" % [auto.x, auto.y]
	var v := GameSettings.parse_resolution(r)
	return "%d × %d (%s)" % [v.x, v.y, _ratio_name(v)]


static func _ratio_name(v: Vector2i) -> String:
	var r := float(v.x) / float(v.y)
	for pair in [[16.0 / 9.0, "16:9"], [16.0 / 10.0, "16:10"], [21.0 / 9.0, "21:9"], [4.0 / 3.0, "4:3"], [1366.0 / 768.0, "16:9"]]:
		if absf(r - pair[0]) < 0.03:
			return pair[1]
	return "%.2f:1" % r


func _update_info() -> void:
	if _info_label == null or not is_instance_valid(_info_label):
		return
	var i: Dictionary = service.display_info()
	var lines := [
		"Plataforma: %s" % i.platform,
		"Janela: %d × %d px · Área de jogo: %d × %d · Escala da interface: %d%%" % [
			i.window.x, i.window.y, i.viewport.x, i.viewport.y, roundi(float(i.ui_scale) * 100.0)],
	]
	if i.screen != Vector2i.ZERO:
		var hz := " · %.0f Hz" % float(i.refresh) if float(i.refresh) > 0.0 else ""
		lines.append("Monitor: %d × %d%s · densidade %.2fx" % [i.screen.x, i.screen.y, hz, float(i.screen_scale)])
	_info_label.text = "\n".join(lines)


func _build_shortcuts() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "Atalhos de teclado"
	title.add_theme_font_size_override("font_size", UiKit.FONT_BODY)
	title.add_theme_font_override("font", DesignTokens.text_font(DesignTokens.WEIGHT_SEMIBOLD))
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", DesignTokens.SPACING_LG)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	for pair in SHORTCUTS:
		var k := Label.new()
		k.text = pair[0]
		k.add_theme_color_override("font_color", DesignTokens.COLOR_ACCENT_CYAN)
		k.add_theme_font_size_override("font_size", UiKit.FONT_SMALL)
		grid.add_child(k)
		var d := Label.new()
		d.text = pair[1]
		d.add_theme_font_size_override("font_size", UiKit.FONT_SMALL)
		d.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_SECONDARY)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(d)
	return box


func _section_index(section: String) -> int:
	for i in _tabs.get_tab_count():
		if str(_tabs.get_tab_control(i).get_meta("section", "")) == section:
			return i
	return -1


# --- tema ---------------------------------------------------------------------------------------------

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = UiKit.FONT_SMALL
	for cls in ["Label", "Button", "OptionButton", "CheckButton", "PopupMenu"]:
		t.set_color("font_color", cls, DesignTokens.COLOR_TEXT_PRIMARY)
	for cls in ["Button", "OptionButton", "CheckButton"]:
		t.set_color("font_hover_color", cls, DesignTokens.COLOR_TEXT_PRIMARY)
		t.set_color("font_pressed_color", cls, DesignTokens.COLOR_TEXT_PRIMARY)
		t.set_color("font_focus_color", cls, DesignTokens.COLOR_TEXT_PRIMARY)
		t.set_color("font_disabled_color", cls, DesignTokens.COLOR_TEXT_MUTED)
	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, DesignTokens.style_button(false, false))
		t.set_stylebox("hover", cls, DesignTokens.style_button(false, true))
		t.set_stylebox("pressed", cls, DesignTokens.style_button(true, false, true))
		t.set_stylebox("disabled", cls, DesignTokens.style_button(false, false))
		t.set_stylebox("focus", cls, _focus_box())
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(st, "CheckButton", empty)
	# Interruptor pintado (UiFrames) ou, sem ele, desenhado em pixels.
	var sw_on: Texture2D = UiFrames.piece("ui_interruptor_ligado")
	var sw_off: Texture2D = UiFrames.piece("ui_interruptor_desligado")
	t.set_icon("checked", "CheckButton", sw_on if sw_on else _switch_icon(true, false))
	t.set_icon("unchecked", "CheckButton", sw_off if sw_off else _switch_icon(false, false))
	t.set_icon("checked_disabled", "CheckButton", sw_on if sw_on else _switch_icon(true, true))
	t.set_icon("unchecked_disabled", "CheckButton", sw_off if sw_off else _switch_icon(false, true))
	t.set_stylebox("focus", "CheckButton", _focus_box())

	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = DesignTokens.COLOR_BG_SURFACE
	panel_sb.set_corner_radius_all(int(DesignTokens.RADIUS_MD))
	panel_sb.set_border_width_all(1)
	panel_sb.border_color = DesignTokens.COLOR_BORDER_SUBTLE
	t.set_stylebox("panel", "TabContainer", panel_sb)
	var tab_sel := StyleBoxFlat.new()
	tab_sel.bg_color = DesignTokens.COLOR_BG_SURFACE
	tab_sel.border_color = DesignTokens.COLOR_ACCENT_PRIMARY
	tab_sel.border_width_bottom = 3
	tab_sel.set_content_margin_all(10)
	tab_sel.content_margin_left = 14
	tab_sel.content_margin_right = 14
	var tab_un := tab_sel.duplicate() as StyleBoxFlat
	tab_un.bg_color = Color(0, 0, 0, 0)
	tab_un.border_width_bottom = 0
	var tab_hover := tab_un.duplicate() as StyleBoxFlat
	tab_hover.bg_color = DesignTokens.COLOR_BG_HOVER
	t.set_stylebox("tab_selected", "TabContainer", DesignTokens.style_tab_selected() if UiFrames.has("ui_aba") else tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_un)
	t.set_stylebox("tab_hovered", "TabContainer", tab_hover)
	t.set_stylebox("tab_focus", "TabContainer", _focus_box())
	t.set_color("font_selected_color", "TabContainer", DesignTokens.COLOR_TEXT_PRIMARY)
	t.set_color("font_unselected_color", "TabContainer", DesignTokens.COLOR_TEXT_SECONDARY)
	t.set_color("font_hovered_color", "TabContainer", DesignTokens.COLOR_TEXT_PRIMARY)

	var popup := StyleBoxFlat.new()
	popup.bg_color = DesignTokens.COLOR_BG_CARD
	popup.border_color = DesignTokens.COLOR_BORDER_STRONG
	popup.set_border_width_all(1)
	popup.set_corner_radius_all(int(DesignTokens.RADIUS_MD))
	popup.set_content_margin_all(6)
	t.set_stylebox("panel", "PopupMenu", popup)
	var popup_hover := StyleBoxFlat.new()
	popup_hover.bg_color = DesignTokens.COLOR_BG_HOVER
	popup_hover.set_corner_radius_all(int(DesignTokens.RADIUS_SM))
	t.set_stylebox("hover", "PopupMenu", popup_hover)
	t.set_constant("v_separation", "PopupMenu", 10)

	t.set_stylebox("slider", "HSlider", DesignTokens.style_bar_track())
	var fill := DesignTokens.style_bar_fill()
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var knob: Texture2D = UiFrames.piece("ui_slider_botao")
	if knob:
		t.set_icon("grabber", "HSlider", knob)
		t.set_icon("grabber_highlight", "HSlider", knob)

	var sep := StyleBoxLine.new()
	sep.color = DesignTokens.COLOR_BORDER_SUBTLE
	t.set_stylebox("separator", "HSeparator", sep)
	return t


## Interruptor desenhado em pixels (o padrão do Godot some no fundo escuro). 2x para telas densas.
static func _switch_icon(on: bool, disabled: bool) -> ImageTexture:
	var w := 88
	var h := 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := DesignTokens.COLOR_ACCENT_YELLOW if on else DesignTokens.COLOR_INK
	var knob := DesignTokens.COLOR_BG_CARD if on else DesignTokens.COLOR_TEXT_MUTED
	if disabled:
		track.a = 0.4
		knob.a = 0.5
	var r := h / 2.0
	var knob_c := Vector2(w - r if on else r, r)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(p.x, r, w - r)
			var d_track := p.distance_to(Vector2(cx, r)) - r
			var d_knob := p.distance_to(knob_c) - (r - 6.0)
			var c := Color(0, 0, 0, 0)
			var a_track := clampf(0.5 - d_track, 0.0, 1.0)
			if a_track > 0.0:
				c = Color(track, track.a * a_track)
			var a_knob := clampf(0.5 - d_knob, 0.0, 1.0)
			if a_knob > 0.0:
				c = c.lerp(Color(knob, 1.0), a_knob * knob.a) if c.a > 0.0 else Color(knob, knob.a * a_knob)
			img.set_pixel(x, y, c)
	img.resize(w / 2, h / 2, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


func _focus_box() -> StyleBox:
	return DesignTokens.style_focus()
