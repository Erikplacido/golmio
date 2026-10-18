class_name AppShell
extends Control
## Casca do app (docs/PLANO_DE_TELAS.md §2): barra superior que só informa (escudo e nome do clube,
## engrenagem), subcabeçalho com Voltar nas telas empilhadas, a área da tela atual e a navegação
## dos cinco destinos, que muda de forma com a largura:
##   compacto  (< COMPACT_MAX px lógicos) ... barra inferior, uma coluna;
##   médio     (< EXPANDED_MIN) ............. trilho à esquerda;
##   expandido ............................... abas na barra superior.
## "Px lógicos" = viewport / Settings.readability_scale(): num celular em retrato o layout de 1100 px
## encolhe, a casca amplia tudo e cai no compacto, como o HUD da partida.
##
## Quem decide o que mostrar é o Router (pilha por aba); a casca só desenha o topo da pilha e guarda
## as telas das pilhas vivas escondidas (trocar de aba e voltar mantém rolagem e estado).

const SETTINGS_HOST_GROUP := "settings_button_host"
const COMPACT_MAX := 600.0
const EXPANDED_MIN := 1024.0
const TOP_H := 60.0
const SUB_H := 52.0

enum Layout { COMPACT, MEDIUM, EXPANDED }

var layout: int = -1
var _frame: Control
var _top: PanelContainer
var _top_row: HBoxContainer
var _club_button: Button
var _crest_slot: Control
var _club_label: Label
var _nav_slot_top: Control
var _sub: PanelContainer
var _sub_title: Label
var _host: Control
var _nav: NavBar
var _k := 1.0
## uid da entrada do Router -> tela
var _screens := {}
var _current_uid := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = DesignTokens.base_theme()
	add_to_group(SETTINGS_HOST_GROUP)   # a engrenagem da barra substitui a flutuante
	add_child(UiFrames.paper_background())
	_frame = Control.new()
	_frame.name = "Frame"
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	_build_parts()
	get_viewport().size_changed.connect(_layout_frame)
	var settings := get_node_or_null("/root/Settings")
	if settings:
		settings.changed.connect(func(key: String, _v: Variant) -> void:
			if key in ["ui_scale", "aspect"]:
				_layout_frame.call_deferred()
		)
	var game := get_node_or_null("/root/Game")
	if game:
		game.changed.connect(_update_top_bar)
	_layout_frame()
	var router := get_node_or_null("/root/Router")
	if router:
		router.attach_shell(self)
	render()


func _process(_delta: float) -> void:
	if not is_equal_approx(_read_k(), _k):
		_layout_frame()


# --- peças ----------------------------------------------------------------------------------

func _build_parts() -> void:
	_top = PanelContainer.new()
	_top.name = "TopBar"
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = DesignTokens.COLOR_BG_SURFACE
	tsb.border_color = DesignTokens.COLOR_INK
	tsb.border_width_bottom = 2
	tsb.content_margin_left = DesignTokens.SPACING_MD
	tsb.content_margin_right = DesignTokens.SPACING_MD
	tsb.content_margin_top = DesignTokens.SPACING_XS
	tsb.content_margin_bottom = DesignTokens.SPACING_XS
	_top.add_theme_stylebox_override("panel", tsb)
	_top.custom_minimum_size.y = TOP_H
	_top_row = UiKit.hbox(DesignTokens.SPACING_MD)
	_top.add_child(_top_row)

	# Escudo e nome: leva ao Clube.
	_club_button = Button.new()
	_club_button.name = "ClubButton"
	_club_button.flat = true
	_club_button.focus_mode = Control.FOCUS_ALL
	_club_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_club_button.custom_minimum_size = Vector2(0, UiKit.TOUCH)
	_club_button.pressed.connect(func() -> void: _switch_tab("club"))
	var club_row := UiKit.hbox(DesignTokens.SPACING_SM)
	club_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	club_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_club_button.add_child(club_row)
	_crest_slot = CenterContainer.new()
	_crest_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	club_row.add_child(_crest_slot)
	_club_label = UiKit.title("", UiKit.FONT_H2)
	_club_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_club_label.size_flags_vertical = Control.SIZE_FILL
	_club_label.clip_text = true
	_club_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_club_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	club_row.add_child(_club_label)
	_top_row.add_child(_club_button)

	_nav_slot_top = UiKit.spacer()
	_nav_slot_top.name = "NavSlot"
	_top_row.add_child(_nav_slot_top)

	var gear := GearButton.new()
	gear.name = "Gear"
	gear.custom_minimum_size = Vector2(UiKit.TOUCH, UiKit.TOUCH)
	gear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiKit.style_button(gear, "secondary")
	_top_row.add_child(gear)

	_sub = PanelContainer.new()
	_sub.name = "SubHeader"
	var ssb := StyleBoxFlat.new()
	ssb.draw_center = false
	ssb.border_color = DesignTokens.COLOR_BORDER_SUBTLE
	ssb.border_width_bottom = 2
	ssb.content_margin_left = DesignTokens.SPACING_MD
	ssb.content_margin_right = DesignTokens.SPACING_MD
	ssb.content_margin_top = DesignTokens.SPACING_XS
	ssb.content_margin_bottom = DesignTokens.SPACING_XS
	_sub.add_theme_stylebox_override("panel", ssb)
	_sub.custom_minimum_size.y = SUB_H
	var sub_row := UiKit.hbox(DesignTokens.SPACING_MD)
	_sub.add_child(sub_row)
	var back := UiKit.button(tr("UI_VOLTAR"), "secondary", "voltar", 42)
	back.name = "Back"
	back.pressed.connect(func() -> void:
		var r := get_node_or_null("/root/Router")
		if r:
			r.back()
	)
	sub_row.add_child(back)
	_sub_title = UiKit.title("", UiKit.FONT_H2)
	_sub_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sub_title.size_flags_vertical = Control.SIZE_FILL
	_sub_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sub_title.clip_text = true
	_sub_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub_row.add_child(_sub_title)

	_host = Control.new()
	_host.name = "ScreenHost"
	_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_host.clip_contents = true
	_host.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_nav = NavBar.new()
	_nav.name = "Nav"
	_nav.tab_pressed.connect(_switch_tab)


func _switch_tab(tab: String) -> void:
	var r := get_node_or_null("/root/Router")
	if r:
		r.switch_tab(tab)


# --- layout ---------------------------------------------------------------------------------

func _read_k() -> float:
	var s := get_node_or_null("/root/Settings")
	return s.readability_scale() if s else 1.0


func _safe() -> Vector4:
	var s := get_node_or_null("/root/Settings")
	return s.safe_margins() if s else Vector4.ZERO


## Classe de layout para uma largura lógica.
static func layout_for(logical_width: float) -> int:
	if logical_width < COMPACT_MAX:
		return Layout.COMPACT
	if logical_width < EXPANDED_MIN:
		return Layout.MEDIUM
	return Layout.EXPANDED


func logical_size() -> Vector2:
	return _frame.size if _frame else size


func _layout_frame() -> void:
	if _frame == null:
		return
	_k = _read_k()
	var vp := get_viewport_rect().size
	var safe := _safe()
	_frame.position = Vector2(safe.x, safe.y)
	_frame.scale = Vector2(_k, _k)
	_frame.size = (vp - Vector2(safe.x + safe.z, safe.y + safe.w)) / _k
	var want := layout_for(_frame.size.x)
	if want != layout:
		_apply_layout(want)


func _apply_layout(p_layout: int) -> void:
	layout = p_layout
	for n in [_top, _sub, _host, _nav]:
		if n.get_parent():
			n.get_parent().remove_child(n)
	for c in _frame.get_children():
		c.queue_free()
	var column := UiKit.vbox(0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_top)
	column.add_child(_sub)
	column.add_child(_host)
	var root: BoxContainer
	match layout:
		Layout.COMPACT:
			_nav.set_mode(NavBar.Mode.BOTTOM)
			root = column
			column.add_child(_nav)
		Layout.MEDIUM:
			_nav.set_mode(NavBar.Mode.RAIL)
			root = UiKit.hbox(0)
			root.add_child(_nav)
			root.add_child(column)
		_:
			_nav.set_mode(NavBar.Mode.TOP)
			root = column
			_nav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_nav.custom_minimum_size.x = 0
			_top_row.add_child(_nav)
			_top_row.move_child(_nav, _nav_slot_top.get_index())
	_nav_slot_top.visible = layout != Layout.EXPANDED
	_nav.size_flags_horizontal = Control.SIZE_EXPAND_FILL if layout != Layout.MEDIUM else Control.SIZE_FILL
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.add_child(root)
	_club_label.visible = layout != Layout.EXPANDED or _frame.size.x >= 1180.0
	_update_top_bar()


# --- telas ----------------------------------------------------------------------------------

## Desenha o topo da pilha do Router (chamado pelo Router a cada navegação).
func render() -> void:
	var router := get_node_or_null("/root/Router")
	if router == null:
		_show_entry({"uid": 0, "route": "home", "params": {}}, 1, "home")
		return
	if router.is_fullscreen():
		return
	_show_entry(router.top(), router.depth(), router.current_tab)
	var live: Dictionary = router.live_uids()
	for uid in _screens.keys():
		if not live.has(uid):
			_screens[uid].queue_free()
			_screens.erase(uid)


func _show_entry(entry: Dictionary, depth: int, tab: String) -> void:
	var uid := int(entry.get("uid", 0))
	var route := str(entry.get("route", "home"))
	var screen: Control = _screens.get(uid)
	var reshown := screen != null
	if screen == null:
		screen = _instantiate(route, entry.get("params", {}))
		if screen == null:
			return
		_screens[uid] = screen
		_host.add_child(screen)
	for u in _screens:
		_screens[u].visible = u == uid
	_current_uid = uid
	if reshown and screen.has_method("on_shown"):
		screen.on_shown()
	_nav.set_active(tab)
	_sub.visible = depth > 1
	var t := ""
	if screen.has_method("screen_title"):
		t = str(screen.screen_title())
	_sub_title.text = (t if t != "" else tr(str(Routes.get_route(route).get("title", "")))).to_upper()


func _instantiate(route: String, p: Dictionary) -> Control:
	var path := str(Routes.get_route(route).get("scene", ""))
	if path == "" or not ResourceLoader.exists(path):
		push_error("AppShell: cena da rota '%s' não existe (%s)" % [route, path])
		return null
	var node := (load(path) as PackedScene).instantiate() as Control
	if node == null:
		return null
	if node.has_method("setup"):
		node.setup(route, p)
	if "embedded" in node:
		node.embedded = true
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return node


## Tela visível agora (o Router pergunta antes de desempilhar).
func current_screen() -> Control:
	return _screens.get(_current_uid)


func _update_top_bar() -> void:
	if _crest_slot == null:
		return
	for c in _crest_slot.get_children():
		c.queue_free()
	var game := get_node_or_null("/root/Game")
	var club: Club = game.club() if game else null
	_crest_slot.add_child(ClubCrest.for_club(club, 34))
	_club_label.text = (club.name if club else tr("CLUBE_SEM_NOME")).to_upper()
	_club_button.tooltip_text = tr("NAV_CLUBE")
	var text_w := DesignTokens.font(true).get_string_size(_club_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.FONT_H2).x
	_club_button.custom_minimum_size.x = 34 + 8 + (minf(text_w + 4.0, 260.0) if _club_label.visible else 0.0)
