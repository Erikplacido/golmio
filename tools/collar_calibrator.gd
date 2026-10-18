class_name CollarCalibrator
extends Control
## Ferramenta visual de calibração individual de golas modulares (PNG).
## Permite ajustar largura, posição vertical (topo), escala e offsets [X, Y]
## de cada modelo de gola separadamente, sem precisar da interface HTML antiga.
##
## Como rodar no Godot:
##   godot --path . res://tools/collar_calibrator.tscn
## Ou via linha de comando para gerar snapshot comparativo:
##   godot --path . --script res://tools/collar_calibrator.gd -- --out=/tmp/golas.png

const PART_ANCHORS_RES := "res://data/portraits/part_anchors.json"
const VISUAIS_PART_ANCHORS := "../visuais/part_anchors.json"

const COLLAR_DEFS := [
	{"id": "collar_001", "file": "Caricatura retrô com gola redonda.png", "label": "1. Redonda"},
	{"id": "collar_002", "file": "Caricatura vintage com gola de futebol.png", "label": "2. Gola V"},
	{"id": "collar_003", "file": "Retrato esportivo com gola polo retrô.png", "label": "3. Polo Retrô"},
	{"id": "collar_004", "file": "Retrato retrô com gola mandarim azul-marinho.png", "label": "4. Mandarim"},
]

var _catalog: PortraitCatalog
var _active_collar_idx: int = 0
var _active_body_id: String = ""
var _zoom_level: float = 1.2
var _show_guides: bool = true

# Nós de interface
var _btn_collars: Array[Button] = []
var _body_select: OptionButton
var _slider_width: HSlider
var _spin_width: SpinBox
var _slider_top: HSlider
var _spin_top: SpinBox
var _slider_scale: HSlider
var _spin_scale: SpinBox
var _slider_off_x: HSlider
var _spin_off_x: SpinBox
var _slider_off_y: HSlider
var _spin_off_y: SpinBox
var _lbl_status: Label
var _json_preview: TextEdit

# Pré-visualização
var _preview_renderer: PortraitRenderer
var _preview_container: Control
var _guides_overlay: Control
var _updating_controls: bool = false

# Dados em edição carregados do part_anchors.json
var _all_anchors: Dictionary = {}
var _collars_data: Dictionary = {}


func _ready() -> void:
	_catalog = PortraitCatalog.shared()
	_load_anchors()
	_setup_ui()
	_select_collar(0)


func _load_anchors() -> void:
	var path := ProjectSettings.globalize_path(PART_ANCHORS_RES)
	if FileAccess.file_exists(path):
		var text := FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			_all_anchors = parsed
	if not _all_anchors.has("parts"):
		_all_anchors["parts"] = {}
	if not _all_anchors["parts"].has("collar"):
		_all_anchors["parts"]["collar"] = {}
	_collars_data = _all_anchors["parts"]["collar"]

	# Garante que as 4 golas existam no dicionário
	for item in COLLAR_DEFS:
		var f: String = item["file"]
		if not _collars_data.has(f):
			_collars_data[f] = {
				"width_factor": PortraitLayout.COLLAR_WIDTH_FACTOR,
				"top_factor": PortraitLayout.COLLAR_TOP_FACTOR,
				"scale": 1.0,
				"offset": [0.0, 0.0]
			}


func _setup_ui() -> void:
	# Layout principal: Split em 2 colunas (Controles à esquerda, Prévia à direita)
	var bg := ColorRect.new()
	bg.color = DesignTokens.COLOR_PAPER
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_preset(PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 0)
	add_child(root_vbox)

	# Barra de topo
	var top_bar := PanelContainer.new()
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = DesignTokens.COLOR_PAPER_SURFACE
	top_style.border_width_bottom = 2
	top_style.border_color = DesignTokens.COLOR_INK
	top_style.content_margin_left = 16
	top_style.content_margin_right = 16
	top_style.content_margin_top = 10
	top_style.content_margin_bottom = 10
	top_bar.add_theme_stylebox_override("panel", top_style)
	root_vbox.add_child(top_bar)

	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 16)
	top_bar.add_child(top_hbox)

	var title := Label.new()
	title.text = "CALIBRADOR INDIVIDUAL DE GOLAS"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", DesignTokens.COLOR_INK)
	top_hbox.add_child(title)

	var sub := Label.new()
	sub.text = "(Regulagem independente de cada colarinho PNG — Salva em part_anchors.json)"
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_SECONDARY)
	top_hbox.add_child(sub)

	top_hbox.add_spacer(false)

	var btn_save_top := Button.new()
	btn_save_top.text = "💾 Salvar Calibração (Ctrl+S)"
	btn_save_top.custom_minimum_size = Vector2(210, 36)
	btn_save_top.pressed.connect(_save_all)
	top_hbox.add_child(btn_save_top)

	# Área de trabalho: Split horizontal
	var main_hbox := HBoxContainer.new()
	main_hbox.size_flags_horizontal = SIZE_EXPAND_FILL
	main_hbox.size_flags_vertical = SIZE_EXPAND_FILL
	main_hbox.add_theme_constant_override("separation", 0)
	root_vbox.add_child(main_hbox)

	# 1. Painel Esquerdo: Controles de Calibração
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(440, 0)
	left_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	main_hbox.add_child(left_scroll)

	var left_box := VBoxContainer.new()
	left_box.size_flags_horizontal = SIZE_EXPAND_FILL
	left_box.add_theme_constant_override("separation", 16)
	left_box.set("theme_override_constants/margin_left", 16)
	left_box.set("theme_override_constants/margin_right", 16)
	left_box.set("theme_override_constants/margin_top", 16)
	left_box.set("theme_override_constants/margin_bottom", 16)
	left_scroll.add_child(left_box)

	# Card: Escolha da Gola
	var card_col := _create_section_card("1. SELECIONE A GOLA PARA REGULAR", left_box)
	var col_grid := GridContainer.new()
	col_grid.columns = 2
	col_grid.add_theme_constant_override("h_separation", 8)
	col_grid.add_theme_constant_override("v_separation", 8)
	card_col.add_child(col_grid)

	_btn_collars.clear()
	for i in range(COLLAR_DEFS.size()):
		var def: Dictionary = COLLAR_DEFS[i]
		var btn := Button.new()
		btn.text = def["label"]
		btn.custom_minimum_size = Vector2(0, 40)
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		btn.pressed.connect(func(): _select_collar(i))
		col_grid.add_child(btn)
		_btn_collars.append(btn)

	# Card: Biotipo / Torso de Teste
	var card_body := _create_section_card("2. BIOTIPO DO JOGADOR (TORSO DE TESTE)", left_box)
	_body_select = OptionButton.new()
	_body_select.custom_minimum_size = Vector2(0, 36)
	var active_bodies: Array = _catalog.ids_with_status("body", "active")
	for b_id in active_bodies:
		_body_select.add_item(b_id + " (" + _catalog.file_of("body", b_id) + ")")
	if not active_bodies.is_empty():
		_active_body_id = active_bodies[0]
	_body_select.item_selected.connect(func(idx: int):
		if idx >= 0 and idx < active_bodies.size():
			_active_body_id = active_bodies[idx]
			_update_preview()
	)
	card_body.add_child(_body_select)

	# Card: Sliders de Calibração
	var card_sliders := _create_section_card("3. REGULAGEM DA GOLA SELECIONADA", left_box)

	# Largura (width_factor)
	var res_w := _create_slider_row("Largura vs Pescoço (width_factor):", 0.5, 2.5, 0.01, 1.25)
	_slider_width = res_w.slider
	_spin_width = res_w.spin
	_slider_width.value_changed.connect(_on_slider_changed)
	_spin_width.value_changed.connect(func(v): _slider_width.value = v)
	card_sliders.add_child(res_w.box)

	# Topo vertical (top_factor)
	var res_t := _create_slider_row("Posição Vertical / Topo (top_factor):", -0.4, 0.6, 0.01, 0.16)
	_slider_top = res_t.slider
	_spin_top = res_t.spin
	_slider_top.value_changed.connect(_on_slider_changed)
	_spin_top.value_changed.connect(func(v): _slider_top.value = v)
	card_sliders.add_child(res_t.box)

	# Escala Geral (scale)
	var res_s := _create_slider_row("Escala Extra (scale):", 0.5, 2.0, 0.01, 1.0)
	_slider_scale = res_s.slider
	_spin_scale = res_s.spin
	_slider_scale.value_changed.connect(_on_slider_changed)
	_spin_scale.value_changed.connect(func(v): _slider_scale.value = v)
	card_sliders.add_child(res_s.box)

	# Deslocamento Horizontal (offset_x)
	var res_ox := _create_slider_row("Ajuste Fino X (offset_x em px):", -80.0, 80.0, 0.5, 0.0)
	_slider_off_x = res_ox.slider
	_spin_off_x = res_ox.spin
	_slider_off_x.value_changed.connect(_on_slider_changed)
	_spin_off_x.value_changed.connect(func(v): _slider_off_x.value = v)
	card_sliders.add_child(res_ox.box)

	# Deslocamento Vertical (offset_y)
	var res_oy := _create_slider_row("Ajuste Fino Y (offset_y em px):", -80.0, 80.0, 0.5, 0.0)
	_slider_off_y = res_oy.slider
	_spin_off_y = res_oy.spin
	_slider_off_y.value_changed.connect(_on_slider_changed)
	_spin_off_y.value_changed.connect(func(v): _slider_off_y.value = v)
	card_sliders.add_child(res_oy.box)

	# Botões de ação locais
	var act_hbox := HBoxContainer.new()
	act_hbox.add_theme_constant_override("separation", 8)
	card_sliders.add_child(act_hbox)

	var btn_reset := Button.new()
	btn_reset.text = "↺ Restaurar Padrão"
	btn_reset.size_flags_horizontal = SIZE_EXPAND_FILL
	btn_reset.pressed.connect(_reset_current_collar)
	act_hbox.add_child(btn_reset)

	var btn_save := Button.new()
	btn_save.text = "💾 Gravar JSON"
	btn_save.size_flags_horizontal = SIZE_EXPAND_FILL
	btn_save.pressed.connect(_save_all)
	act_hbox.add_child(btn_save)

	_lbl_status = Label.new()
	_lbl_status.text = "Pronto para calibrar."
	_lbl_status.add_theme_font_size_override("font_size", 12)
	_lbl_status.add_theme_color_override("font_color", DesignTokens.COLOR_ACCENT_BLUE)
	card_sliders.add_child(_lbl_status)

	# Card: JSON preview
	var card_json := _create_section_card("4. PREVIEW DO JSON GERADO", left_box)
	_json_preview = TextEdit.new()
	_json_preview.custom_minimum_size = Vector2(0, 110)
	_json_preview.editable = false
	card_json.add_child(_json_preview)

	# Divisória vertical
	var div := ColorRect.new()
	div.color = DesignTokens.COLOR_INK
	div.custom_minimum_size = Vector2(2, 0)
	main_hbox.add_child(div)

	# 2. Painel Direito: Pré-visualização do Jogador
	var right_box := VBoxContainer.new()
	right_box.size_flags_horizontal = SIZE_EXPAND_FILL
	right_box.size_flags_vertical = SIZE_EXPAND_FILL
	main_hbox.add_child(right_box)

	# Barra de ferramentas da prévia
	var tool_bar := HBoxContainer.new()
	tool_bar.add_theme_constant_override("separation", 16)
	tool_bar.set("theme_override_constants/margin_left", 16)
	tool_bar.set("theme_override_constants/margin_top", 10)
	tool_bar.set("theme_override_constants/margin_bottom", 10)
	right_box.add_child(tool_bar)

	var check_guides := CheckBox.new()
	check_guides.text = "Mostrar Linhas Guia da Gola"
	check_guides.button_pressed = _show_guides
	check_guides.toggled.connect(func(v: bool):
		_show_guides = v
		_guides_overlay.queue_redraw()
	)
	tool_bar.add_child(check_guides)

	var lbl_zoom := Label.new()
	lbl_zoom.text = "Zoom:"
	tool_bar.add_child(lbl_zoom)

	for z in [1.0, 1.25, 1.5, 2.0]:
		var bz := Button.new()
		bz.text = "%dx" % int(z) if z == 1.0 or z == 2.0 else "%.2fx" % z
		bz.pressed.connect(func():
			_zoom_level = z
			_update_preview()
		)
		tool_bar.add_child(bz)

	# Contêiner centralizado da prévia
	var center_cont := CenterContainer.new()
	center_cont.size_flags_horizontal = SIZE_EXPAND_FILL
	center_cont.size_flags_vertical = SIZE_EXPAND_FILL
	right_box.add_child(center_cont)

	_preview_container = Control.new()
	_preview_container.custom_minimum_size = Vector2(400, 520)
	center_cont.add_child(_preview_container)

	_preview_renderer = PortraitRenderer.new()
	_preview_container.add_child(_preview_renderer)

	_guides_overlay = Control.new()
	_guides_overlay.set_anchors_preset(PRESET_FULL_RECT)
	_guides_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	_guides_overlay.draw.connect(_on_draw_guides)
	_preview_container.add_child(_guides_overlay)


func _create_section_card(title_text: String, parent: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = DesignTokens.COLOR_PAPER_SURFACE
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = DesignTokens.COLOR_INK
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var lbl := Label.new()
	lbl.text = title_text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", DesignTokens.COLOR_ACCENT_BLUE)
	vbox.add_child(lbl)

	return vbox


func _create_slider_row(label_text: String, min_v: float, max_v: float, step_v: float, def_v: float) -> Dictionary:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", DesignTokens.COLOR_INK)
	row.add_child(lbl)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.value = def_v
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.size_flags_vertical = SIZE_SHRINK_CENTER
	hbox.add_child(slider)

	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step_v
	spin.value = def_v
	spin.custom_minimum_size = Vector2(80, 0)
	hbox.add_child(spin)

	return {"box": row, "slider": slider, "spin": spin}


func _select_collar(idx: int) -> void:
	_active_collar_idx = clampi(idx, 0, COLLAR_DEFS.size() - 1)
	for i in range(_btn_collars.size()):
		var b := _btn_collars[i]
		if i == _active_collar_idx:
			b.add_theme_color_override("font_color", DesignTokens.COLOR_ACCENT_YELLOW)
		else:
			b.remove_theme_color_override("font_color")

	var f: String = COLLAR_DEFS[_active_collar_idx]["file"]
	var cal: Dictionary = _collars_data.get(f, {})

	_updating_controls = true
	_slider_width.value = float(cal.get("width_factor", PortraitLayout.COLLAR_WIDTH_FACTOR))
	_spin_width.value = _slider_width.value

	_slider_top.value = float(cal.get("top_factor", PortraitLayout.COLLAR_TOP_FACTOR))
	_spin_top.value = _slider_top.value

	_slider_scale.value = float(cal.get("scale", 1.0))
	_spin_scale.value = _slider_scale.value

	var off: Array = cal.get("offset", [0.0, 0.0])
	_slider_off_x.value = float(off[0]) if off.size() >= 1 else 0.0
	_spin_off_x.value = _slider_off_x.value
	_slider_off_y.value = float(off[1]) if off.size() >= 2 else 0.0
	_spin_off_y.value = _slider_off_y.value
	_updating_controls = false

	_update_preview()
	_update_json_preview()


func _on_slider_changed(_v: float) -> void:
	if _updating_controls:
		return
	_spin_width.value = _slider_width.value
	_spin_top.value = _slider_top.value
	_spin_scale.value = _slider_scale.value
	_spin_off_x.value = _slider_off_x.value
	_spin_off_y.value = _slider_off_y.value

	var f: String = COLLAR_DEFS[_active_collar_idx]["file"]
	var current: Dictionary = {
		"width_factor": snappedf(_slider_width.value, 0.001),
		"top_factor": snappedf(_slider_top.value, 0.001),
		"scale": snappedf(_slider_scale.value, 0.001),
		"offset": [snappedf(_slider_off_x.value, 0.1), snappedf(_slider_off_y.value, 0.1)]
	}
	_collars_data[f] = current

	# Atualiza o catálogo em memória imediatamente para o preview refletir
	if not _catalog.part_anchors.has("parts"):
		_catalog.part_anchors["parts"] = {}
	_catalog.part_anchors["parts"]["collar"] = _collars_data

	_lbl_status.text = "Modificado (não gravado em disco)."
	_lbl_status.add_theme_color_override("font_color", DesignTokens.COLOR_ACCENT_RED)
	_update_preview()
	_update_json_preview()


func _reset_current_collar() -> void:
	_updating_controls = true
	_slider_width.value = PortraitLayout.COLLAR_WIDTH_FACTOR
	_slider_top.value = PortraitLayout.COLLAR_TOP_FACTOR
	_slider_scale.value = 1.0
	_slider_off_x.value = 0.0
	_slider_off_y.value = 0.0
	_updating_controls = false
	_on_slider_changed(0.0)


func _update_preview() -> void:
	var collar_file: String = COLLAR_DEFS[_active_collar_idx]["file"]
	var face: Dictionary = {
		"body": _active_body_id if _active_body_id != "" else "body_001",
		"head": "head_001",
		"eye": "eye_001",
		"nose": "nose_001",
		"mouth": "mouth_001",
		"hair": "hair_001",
	}
	var kit: Dictionary = {
		"pattern": "listras_verticais",
		"colors": ["#1d4ed8", "#ffffff", "#facc15"],
		"collar": collar_file,
		"collar_color": 1,
		"collar_trim_color": 2,
		"crest": true,
		"sigla": "FTB"
	}
	_preview_renderer.setup(face, kit, _catalog)
	_preview_renderer.fit_size(Vector2(360, 480) * _zoom_level)
	_guides_overlay.queue_redraw()


func _update_json_preview() -> void:
	var f: String = COLLAR_DEFS[_active_collar_idx]["file"]
	var data: Dictionary = _collars_data.get(f, {})
	_json_preview.text = JSON.stringify({f: data}, "  ")


func _on_draw_guides() -> void:
	if not _show_guides or _preview_renderer == null:
		return
	var body_node := _preview_renderer.find_layer("body")
	if body_node == null:
		return
	var collar_node := body_node.get_node_or_null("collar") as LayerNode
	if collar_node == null:
		return

	# Calcula os pontos no espaço de tela do overlay
	var body_xform := body_node.get_global_transform()
	var overlay_xform := _guides_overlay.get_global_transform().affine_inverse()

	# Caixa desenhada da gola
	var col_rect := Rect2(Vector2.ZERO, collar_node.size)
	var xf := overlay_xform * (collar_node.get_global_transform())
	var p0 := xf * col_rect.position
	var p1 := xf * (col_rect.position + Vector2(col_rect.size.x, 0))
	var p2 := xf * (col_rect.position + col_rect.size)
	var p3 := xf * (col_rect.position + Vector2(0, col_rect.size.y))

	_guides_overlay.draw_line(p0, p1, Color("#00d2d3", 0.8), 2.0)
	_guides_overlay.draw_line(p1, p2, Color("#00d2d3", 0.8), 2.0)
	_guides_overlay.draw_line(p2, p3, Color("#00d2d3", 0.8), 2.0)
	_guides_overlay.draw_line(p3, p0, Color("#00d2d3", 0.8), 2.0)

	# Ponto central do pescoço
	var cal := _catalog.body_calibration(_active_body_id)
	var col_info: Dictionary = cal.get("collar", {})
	var left: Array = col_info.get("left", [0.38, 0.0])
	var right: Array = col_info.get("right", [0.62, 0.0])
	var neck_l := overlay_xform * (body_xform * (Vector2(left[0], left[1]) * body_node.size))
	var neck_r := overlay_xform * (body_xform * (Vector2(right[0], right[1]) * body_node.size))

	_guides_overlay.draw_line(neck_l, neck_r, Color("#fec12e", 0.9), 3.0)
	_guides_overlay.draw_circle(neck_l, 4.0, Color("#fec12e"))
	_guides_overlay.draw_circle(neck_r, 4.0, Color("#fec12e"))


func _save_all() -> void:
	_all_anchors["parts"]["collar"] = _collars_data
	var json_text := JSON.stringify(_all_anchors, "  ") + "\n"

	var paths_to_save := [
		ProjectSettings.globalize_path(PART_ANCHORS_RES),
		ProjectSettings.globalize_path(VISUAIS_PART_ANCHORS)
	]

	var saved_count := 0
	for p in paths_to_save:
		if FileAccess.file_exists(p) or p.contains("jogo/data"):
			var file := FileAccess.open(p, FileAccess.WRITE)
			if file != null:
				file.store_string(json_text)
				file.close()
				saved_count += 1

	# Atualiza o catálogo compartilhado
	PortraitCatalog.reset_shared()
	_catalog = PortraitCatalog.shared()

	_lbl_status.text = "✅ Salvo com sucesso em %d arquivo(s)!" % saved_count
	_lbl_status.add_theme_color_override("font_color", DesignTokens.COLOR_ACCENT_EMERALD)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_S and (event.ctrl_pressed or event.meta_pressed):
			_save_all()
			get_viewport().set_input_as_handled()
