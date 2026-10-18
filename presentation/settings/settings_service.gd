extends Node
## Autoload "Settings": carrega as preferências (GameSettings), aplica na janela, no motor e no
## áudio, salva em user://settings.cfg e mantém o overlay global (painel de configurações, botão de
## engrenagem flutuante e contador de FPS).
##
## Telas leem com `Settings.get_value(key)` e escutam `Settings.changed`. Uma tela que tem o seu
## próprio botão de opções entra no grupo HOST_GROUP e o botão flutuante some.
##
## Atalhos globais: F10 abre/fecha o painel · F11 ou Alt+Enter alterna tela cheia · Esc fecha o painel.
##
## Linha de comando (desenvolvimento, nada é salvo):
##   -- --set=ui_scale=1.5,aspect=keep   sobrescreve preferências nesta execução
##   -- --shot=/tmp/tela.png [--shot-delay=1.5] [--shot-panel=display]   captura a tela e sai
##   -- --keep-window                     não mexe no modo/tamanho da janela (ex.: tools/screens_snapshot)

signal changed(key: String, value: Variant)
signal panel_toggled(open: bool)

const HOST_GROUP := "settings_button_host"
const PanelScript := preload("res://presentation/settings/settings_panel.gd")
const SAVE_DELAY := 0.4

var settings: GameSettings
var platform: Dictionary

var _overlay: CanvasLayer
var _gear: GearButton
var _fps_label: Label
var _panel: Control
var _pause_reasons := {}
var _save_timer: Timer
var _persist := true
var _manage_window := true
var _pending_web_fullscreen := false
var _focused := true
var _applying_scale := false
var _rotate_hint: PanelContainer
var _rotate_dismissed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	platform = GameSettings.detect_platform()
	settings = GameSettings.new(platform)
	settings.load_file()
	_apply_cmdline_overrides()
	# Editor com jogo embutido, capturas e headless: não mexe no modo/tamanho da janela.
	_manage_window = _is_display_real() and not Engine.is_embedded_in_editor() and _arg("shot") == "" \
		and not OS.get_cmdline_user_args().has("--keep-window")

	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY
	_save_timer.timeout.connect(save_now)
	add_child(_save_timer)

	_ensure_audio_buses()
	_build_overlay()
	apply_all()
	get_tree().root.size_changed.connect(_on_root_resized)
	if _arg("shot") != "":
		_run_snapshot.call_deferred(_arg("shot"))


func _exit_tree() -> void:
	if _save_timer and not _save_timer.is_stopped():
		save_now()


# --- API ----------------------------------------------------------------------------------------------

func get_value(key: String) -> Variant:
	return settings.get_value(key)


## Grava, aplica, avisa (`changed`) e agenda o salvamento.
func set_value(key: String, value: Variant) -> void:
	if not settings.set_value(key, value):
		return
	_apply(key)
	changed.emit(key, settings.get_value(key))
	_schedule_save()


func reset_section(section: String) -> void:
	for key in settings.reset(section):
		_apply(key)
		changed.emit(key, settings.get_value(key))
	_schedule_save()


func save_now() -> void:
	if _persist:
		settings.save_file()


func is_panel_open() -> bool:
	return _panel != null and _panel.visible


func open_panel(tab: String = "") -> void:
	if _panel == null:
		return
	_panel.open(tab)
	_set_pause("menu", true)
	_update_gear()
	panel_toggled.emit(true)


func close_panel() -> void:
	if not is_panel_open():
		return
	_panel.close()
	_set_pause("menu", false)
	_update_gear()
	panel_toggled.emit(false)


func toggle_fullscreen() -> void:
	var fs := str(get_value("window_mode")) in ["fullscreen", "exclusive_fullscreen"]
	set_value("window_mode", "windowed" if fs else "fullscreen")


## Margens seguras (entalhe/ilha/barras do sistema) em pixels lógicos do viewport: x=esq, y=topo,
## z=dir, w=base. Zero fora do celular.
func safe_margins() -> Vector4:
	if not bool(platform.get("mobile", false)) or not _is_display_real():
		return Vector4.ZERO
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var win := Rect2(Vector2(DisplayServer.window_get_position()), Vector2(DisplayServer.window_get_size()))
	if safe.size == Vector2.ZERO or win.size == Vector2.ZERO:
		return Vector4.ZERO
	# Pixels da janela -> pixels lógicos do viewport (a escala do stretch é uniforme).
	var k := 1.0 / maxf(get_tree().root.get_final_transform().get_scale().x, 0.01)
	return Vector4(
		maxf(safe.position.x - win.position.x, 0.0) * k,
		maxf(safe.position.y - win.position.y, 0.0) * k,
		maxf(win.end.x - safe.end.x, 0.0) * k,
		maxf(win.end.y - safe.end.y, 0.0) * k)


func touch_controls_visible() -> bool:
	return settings.touch_controls_visible()


func key_hints_visible() -> bool:
	return settings.key_hints_visible()


## Escala da interface em uso agora (resolve "automática").
func current_ui_scale() -> float:
	return settings.effective_ui_scale(_window_px(), _screen_scale())


## Fator extra para um elemento ficar legível/tocável: quanto ampliar para que 1 px lógico valha
## pelo menos `min_css` px do sistema (pt no iOS, dp no Android, px CSS no navegador). Com 1.0, os
## tokens valem o que dizem: texto 16 = 16 pt, alvo de toque 48 = 48 dp (Material/HIG). 1.0 em
## monitores comuns; ~2.8 num celular em retrato, onde o layout de 1100 px encolhe para ~390 pt e a
## largura lógica fica em ~360-430 px (as telas compactas são desenhadas para caber em 360).
func readability_scale(min_css: float = 1.0, max_k: float = 3.0) -> float:
	if not _is_display_real():
		return 1.0
	var css := get_tree().root.get_final_transform().get_scale().x / maxf(_screen_scale(), 0.01)
	return clampf(min_css / maxf(css, 0.01), 1.0, max_k)


## Quanto a escala "automática" daria nesta janela.
func auto_ui_scale() -> float:
	return GameSettings.auto_ui_scale(platform, _window_px(), _screen_scale())


## Resumo da tela para o painel e para relatos de bug.
func display_info() -> Dictionary:
	var root := get_tree().root
	var info := {
		"platform": _platform_name(),
		"window": Vector2i(_window_px()),
		"viewport": Vector2i(root.get_visible_rect().size),
		"ui_scale": current_ui_scale(),
		"screen_scale": _screen_scale(),
		"screen": Vector2i.ZERO,
		"refresh": 0.0,
	}
	if _is_display_real():
		var scr := DisplayServer.window_get_current_screen()
		info["screen"] = DisplayServer.screen_get_size(scr)
		info["refresh"] = DisplayServer.screen_get_refresh_rate(scr)
	return info


func screen_options() -> Array:
	var out: Array = []
	if not _is_display_real():
		return out
	for i in DisplayServer.get_screen_count():
		out.append({"index": i, "size": DisplayServer.screen_get_size(i)})
	return out


func usable_screen_size() -> Vector2i:
	if not _is_display_real():
		return Vector2i.ZERO
	return DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size


# --- aplicação ----------------------------------------------------------------------------------------

func apply_all() -> void:
	for key in ["window_mode", "aspect", "orientation", "vsync", "max_fps", "msaa_2d", "show_fps",
			"volume_master"]:
		_apply(key)


func _apply(key: String) -> void:
	match key:
		"window_mode", "resolution", "screen":
			_apply_window()
		"aspect", "ui_scale":
			_apply_scaling()
		"orientation":
			_apply_orientation()
		"vsync":
			_apply_vsync()
		"max_fps", "battery_saver":
			Engine.max_fps = settings.effective_max_fps()
			OS.low_processor_usage_mode = bool(get_value("battery_saver"))
		"msaa_2d":
			_apply_msaa()
		"show_fps":
			if _fps_label:
				_fps_label.visible = bool(get_value("show_fps"))
		"volume_master", "volume_music", "volume_sfx", "mute", "mute_unfocused":
			_apply_audio()
		"pause_on_focus_loss":
			if not bool(get_value("pause_on_focus_loss")):
				_set_pause("focus", false)
		"touch_controls":
			_update_gear()


func _apply_window() -> void:
	if not _manage_window:
		return
	var mode := str(get_value("window_mode"))
	if bool(platform.get("web", false)):
		var want_fs := mode == "fullscreen"
		var is_fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		if want_fs != is_fs:
			# O navegador só aceita tela cheia em resposta a um gesto; ao abrir o jogo, espera o 1º toque.
			if want_fs and Engine.get_process_frames() < 2:
				_pending_web_fullscreen = true
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want_fs else DisplayServer.WINDOW_MODE_WINDOWED)
		_apply_orientation()
		return
	if not bool(platform.get("desktop", false)):
		return

	var screen := int(get_value("screen"))
	if screen >= 0 and screen < DisplayServer.get_screen_count() and screen != DisplayServer.window_get_current_screen():
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_current_screen(screen)

	DisplayServer.window_set_min_size(GameSettings.MIN_WINDOW)
	match mode:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"exclusive_fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"maximized":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		_:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
			var size := GameSettings.parse_resolution(str(get_value("resolution")))
			if size == Vector2i.ZERO:
				size = GameSettings.auto_window_size(usable.size)
			size = size.min(usable.size).max(GameSettings.MIN_WINDOW)
			DisplayServer.window_set_size(size)
			DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)
	_apply_scaling.call_deferred()


func _apply_scaling() -> void:
	if _applying_scale:
		return
	_applying_scale = true
	var root := get_tree().root
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP if str(get_value("aspect")) == "keep" \
		else Window.CONTENT_SCALE_ASPECT_EXPAND
	var s := current_ui_scale()
	if not is_equal_approx(root.content_scale_factor, s):
		root.content_scale_factor = s
	_applying_scale = false


func _apply_orientation() -> void:
	if not bool(platform.get("mobile", false)):
		return
	var o := str(get_value("orientation"))
	if bool(platform.get("web", false)):
		# Só vale com a página em tela cheia (Android/Chrome); no iOS o navegador ignora.
		var js := "screen.orientation && screen.orientation.unlock && screen.orientation.unlock()" if o == "auto" \
			else "screen.orientation && screen.orientation.lock && screen.orientation.lock('%s').catch(function(){})" % o
		JavaScriptBridge.eval(js, true)
		return
	var map := {
		"landscape": DisplayServer.SCREEN_SENSOR_LANDSCAPE,
		"portrait": DisplayServer.SCREEN_SENSOR_PORTRAIT,
		"auto": DisplayServer.SCREEN_SENSOR,
	}
	DisplayServer.screen_set_orientation(map.get(o, DisplayServer.SCREEN_SENSOR))


func _apply_vsync() -> void:
	if not bool(platform.get("desktop", false)) or not _is_display_real():
		return
	var map := {
		"on": DisplayServer.VSYNC_ENABLED,
		"adaptive": DisplayServer.VSYNC_ADAPTIVE,
		"off": DisplayServer.VSYNC_DISABLED,
	}
	DisplayServer.window_set_vsync_mode(map.get(str(get_value("vsync")), DisplayServer.VSYNC_ENABLED))


func _apply_msaa() -> void:
	var map := {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X}
	get_tree().root.msaa_2d = map.get(int(get_value("msaa_2d")), Viewport.MSAA_DISABLED)


## Barramentos Master, Music e SFX. Sons novos devem tocar em "Music" ou "SFX".
func _ensure_audio_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func _apply_audio() -> void:
	var pairs := [["Master", "volume_master"], ["Music", "volume_music"], ["SFX", "volume_sfx"]]
	for pair in pairs:
		var idx := AudioServer.get_bus_index(pair[0])
		if idx == -1:
			continue
		var v := float(get_value(pair[1])) / 100.0
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(idx, v <= 0.0)
	var muted := bool(get_value("mute")) or (not _focused and bool(get_value("mute_unfocused")))
	AudioServer.set_bus_mute(0, muted or float(get_value("volume_master")) <= 0.0)


# --- pausa e foco -------------------------------------------------------------------------------------

func _set_pause(reason: String, on: bool) -> void:
	if on:
		_pause_reasons[reason] = true
	else:
		_pause_reasons.erase(reason)
	get_tree().paused = not _pause_reasons.is_empty()


func _notification(what: int) -> void:
	if settings == null or not is_inside_tree():
		return
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			_focused = false
			if bool(get_value("pause_on_focus_loss")):
				_set_pause("focus", true)
			_apply_audio()
			if not _save_timer.is_stopped():
				save_now()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			_focused = true
			_set_pause("focus", false)
			_apply_audio()
		NOTIFICATION_WM_CLOSE_REQUEST:
			if not _save_timer.is_stopped():
				save_now()


func _input(event: InputEvent) -> void:
	if _pending_web_fullscreen and (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		_pending_web_fullscreen = false
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_apply_orientation()
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := event as InputEventKey
	if k.keycode == KEY_F10:
		if is_panel_open():
			close_panel()
		else:
			open_panel()
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_F11 or (k.keycode == KEY_ENTER and k.alt_pressed):
		if settings.is_available("window_mode"):
			toggle_fullscreen()
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_ESCAPE and is_panel_open():
		close_panel()
		get_viewport().set_input_as_handled()


func _on_root_resized() -> void:
	# Saída de tela cheia pelo próprio sistema/navegador (Esc, gesto): sincroniza a preferência.
	if _manage_window and settings.is_available("window_mode"):
		var mode := DisplayServer.window_get_mode()
		var pref := str(get_value("window_mode"))
		var fs_pref := pref in ["fullscreen", "exclusive_fullscreen"]
		var fs_now := mode in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
		if fs_pref and not fs_now and not _pending_web_fullscreen:
			if settings.set_value("window_mode", "windowed"):
				changed.emit("window_mode", "windowed")
				_schedule_save()
	if float(get_value("ui_scale")) <= 0.0:
		_apply_scaling.call_deferred()


# --- overlay ------------------------------------------------------------------------------------------

func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_overlay)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(root)

	_fps_label = Label.new()
	_fps_label.position = Vector2(8, 4)
	_fps_label.add_theme_font_size_override("font_size", UiKit.FONT_CAPTION)
	_fps_label.add_theme_color_override("font_color", DesignTokens.COLOR_ACCENT_EMERALD)
	_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps_label.add_theme_constant_override("outline_size", 4)
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.visible = false
	root.add_child(_fps_label)

	_gear = GearButton.new()
	_gear.add_theme_stylebox_override("normal", _gear_style(0.55))
	_gear.add_theme_stylebox_override("hover", _gear_style(0.85))
	_gear.add_theme_stylebox_override("pressed", _gear_style(0.95))
	_gear.custom_minimum_size = Vector2(44, 44)
	_gear.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_gear.offset_left = -56
	_gear.offset_right = -12
	_gear.offset_top = 12
	_gear.offset_bottom = 56
	root.add_child(_gear)

	_rotate_hint = _build_rotate_hint()
	root.add_child(_rotate_hint)

	_panel = PanelScript.new()
	_panel.service = self
	_panel.visible = false
	root.add_child(_panel)


## Aviso para girar o aparelho: só quando o jogador travou em paisagem e o navegador do celular não
## conseguiu travar (fora de tela cheia). No padrão "auto" o jogo segue o aparelho.
func _build_rotate_hint() -> PanelContainer:
	var hint := PanelContainer.new()
	var sb := DesignTokens.style_card(DesignTokens.RADIUS_LG, DesignTokens.COLOR_ACCENT_GOLD)
	hint.add_theme_stylebox_override("panel", sb)
	hint.visible = false
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", DesignTokens.SPACING_MD)
	hint.add_child(box)
	var lbl := Label.new()
	lbl.text = "Você travou o jogo em paisagem: gire o aparelho para a horizontal."
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size.x = 140
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.add_theme_font_size_override("font_size", UiKit.FONT_BODY)
	lbl.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_PRIMARY)
	box.add_child(lbl)
	if bool(platform.get("web", false)):
		var fs := Button.new()
		fs.text = "Tela cheia"
		fs.custom_minimum_size = Vector2(96, 44)
		fs.add_theme_stylebox_override("normal", DesignTokens.style_button(true))
		fs.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_PRIMARY)
		fs.pressed.connect(func(): set_value("window_mode", "fullscreen"))
		box.add_child(fs)
	var ok := Button.new()
	ok.text = "OK"
	ok.custom_minimum_size = Vector2(56, 44)
	ok.add_theme_stylebox_override("normal", DesignTokens.style_button(false))
	ok.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_PRIMARY)
	ok.pressed.connect(func():
		_rotate_dismissed = true
		_rotate_hint.visible = false
	)
	box.add_child(ok)
	return hint


func _update_rotate_hint() -> void:
	var vp := get_tree().root.get_visible_rect().size
	var show := bool(platform.get("mobile", false)) and not _rotate_dismissed and vp.y > vp.x \
		and str(get_value("orientation")) == "landscape" and not is_panel_open()
	_rotate_hint.visible = show
	if not show:
		return
	var k := readability_scale()
	var w := minf(vp.x / k - 24.0, 560.0)
	w = maxf(w, _rotate_hint.get_combined_minimum_size().x)
	_rotate_hint.scale = Vector2(k, k)
	_rotate_hint.size = Vector2(w, 0)
	_rotate_hint.position = Vector2((vp.x - w * k) / 2.0, 16.0 + safe_margins().y)


func _gear_style(alpha: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(DesignTokens.COLOR_BG_CARD, alpha)
	s.border_color = Color(DesignTokens.COLOR_BORDER_STRONG, alpha)
	s.set_border_width_all(1)
	s.set_corner_radius_all(22)
	return s


func _process(_delta: float) -> void:
	if _fps_label.visible:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	_update_gear()


func _update_gear() -> void:
	if _gear == null:
		return
	var host := get_tree().get_first_node_in_group(HOST_GROUP)
	_gear.visible = host == null and not is_panel_open()
	var m := safe_margins()
	var k := readability_scale()
	_gear.scale = Vector2(k, k)
	# Tamanho fixo de 44; a escala amplia a partir do canto superior esquerdo.
	_gear.offset_left = -12.0 - m.z - 44.0 * k
	_gear.offset_right = _gear.offset_left + 44.0
	_gear.offset_top = 12.0 + m.y
	_gear.offset_bottom = _gear.offset_top + 44.0
	_update_rotate_hint()


# --- utilidades ---------------------------------------------------------------------------------------

func _schedule_save() -> void:
	if _persist:
		_save_timer.start()


func _apply_cmdline_overrides() -> void:
	var raw := _arg("set")
	if raw == "":
		return
	_persist = false
	for pair in raw.split(",", false):
		var kv := pair.split("=", true, 1)
		if kv.size() == 2 and GameSettings.SCHEMA.has(kv[0]):
			settings.set_value(kv[0], kv[1])


func _run_snapshot(path: String) -> void:
	_persist = false
	var tab := _arg("shot-panel")
	if tab != "":
		open_panel(tab)
	var delay := float(_arg("shot-delay")) if _arg("shot-delay") != "" else 1.0
	await get_tree().create_timer(delay, true).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("[Settings] captura %dx%d (janela %s, área lógica %s, escala %.2f) salva em %s (%s)" % [img.get_width(),
		img.get_height(), DisplayServer.window_get_size(), get_tree().root.get_visible_rect().size,
		get_tree().root.content_scale_factor, path, error_string(err)])
	get_tree().quit(0 if err == OK else 1)


func _arg(name: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	return ""


func _is_display_real() -> bool:
	return DisplayServer.get_name() != "headless"


func _window_px() -> Vector2:
	if not _is_display_real():
		return Vector2(GameSettings.BASE_SIZE)
	return Vector2(DisplayServer.window_get_size())


## Pixels físicos por pt/dp (2.0 num Mac Retina, 3.0 num iPhone, 2.625 num Android de 420 dpi).
## No Android o Godot limita screen_get_scale() a tela/800 px para "não cortar" (num 1080x2400 de
## 420 dpi devolve 1.35 em vez de 2.625): a escala de leitura achava que era quase um desktop, o
## texto saía com metade do tamanho e a casca caía no trilho de tablet. Lá a densidade vem do dpi
## (dp = px × 160 / dpi, a definição do Android).
func _screen_scale() -> float:
	if not _is_display_real():
		return 1.0
	var screen := DisplayServer.window_get_current_screen()
	var scale := DisplayServer.screen_get_scale(screen)
	if OS.get_name() == "Android":
		var dpi := DisplayServer.screen_get_dpi(screen)
		if dpi > 0:
			scale = maxf(scale, float(dpi) / 160.0)
	return scale


func _platform_name() -> String:
	var kind := "celular/tablet" if platform.get("mobile", false) else "desktop"
	if platform.get("web", false):
		kind += " · navegador"
	return "%s (%s)" % [kind, platform.get("os", "?")]
