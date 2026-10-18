class_name GameSettings
extends RefCounted
## Preferências do jogador. Só do cliente: nada aqui entra na simulação nem no save do mundo.
## Modelo puro (testável headless): esquema, padrões por plataforma, validação, opções disponíveis
## em cada plataforma e (de)serialização em ConfigFile. Quem aplica na janela, no motor e no áudio
## é o autoload Settings (settings_service.gd).

const PATH := "user://settings.cfg"
const VERSION := 1

## Resolução de referência do layout (project.godot: display/window/size/viewport_*).
const BASE_SIZE := Vector2i(1100, 720)
## Menor janela útil no desktop (pixels de tela).
const MIN_WINDOW := Vector2i(800, 500)
## Abaixo disto (lado menor, em pixels lógicos do sistema) a tela é tratada como celular.
const PHONE_SHORT_SIDE := 540.0

const RESOLUTION_PRESETS := [
	"1280x720", "1280x800", "1366x768", "1440x900", "1600x900", "1680x1050", "1920x1080",
	"1920x1200", "2560x1080", "2560x1440", "2560x1600", "3440x1440", "3840x2160",
]

## Ordem = ordem das abas no painel.
const SECTIONS := ["display", "performance", "gameplay", "controls", "audio", "accessibility"]

## key -> {section, default, options | min/max}. `default` pode ser sobrescrito por plataforma em
## _platform_default().
const SCHEMA := {
	# Tela
	"window_mode": {"section": "display", "default": "windowed",
		"options": ["windowed", "maximized", "fullscreen", "exclusive_fullscreen"]},
	"resolution": {"section": "display", "default": "auto"},
	"screen": {"section": "display", "default": -1, "min": -1, "max": 15},
	"aspect": {"section": "display", "default": "expand", "options": ["expand", "keep"]},
	"ui_scale": {"section": "display", "default": 0.0,
		"options": [0.0, 0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]},
	"orientation": {"section": "display", "default": "auto", "options": ["auto", "portrait", "landscape"]},
	# Desempenho
	"vsync": {"section": "performance", "default": "on", "options": ["on", "adaptive", "off"]},
	"max_fps": {"section": "performance", "default": 0, "options": [0, 30, 60, 90, 120, 144, 165, 240]},
	"msaa_2d": {"section": "performance", "default": 0, "options": [0, 2, 4]},
	"battery_saver": {"section": "performance", "default": false},
	"show_fps": {"section": "performance", "default": false},
	# Partida
	"match_speed": {"section": "gameplay", "default": 1.0, "options": [0.25, 0.5, 1.0, 2.0, 3.0, 4.0, 5.0]},
	"cutscenes": {"section": "gameplay", "default": true},
	"cutscene_length": {"section": "gameplay", "default": "normal", "options": ["short", "normal", "long"]},
	"auto_replay": {"section": "gameplay", "default": true},
	"pause_on_focus_loss": {"section": "gameplay", "default": true},
	# Controles
	"touch_controls": {"section": "controls", "default": "auto", "options": ["auto", "on", "off"]},
	"key_hints": {"section": "controls", "default": "auto", "options": ["auto", "on", "off"]},
	# Áudio (0..100)
	"volume_master": {"section": "audio", "default": 80, "min": 0, "max": 100},
	"volume_music": {"section": "audio", "default": 70, "min": 0, "max": 100},
	"volume_sfx": {"section": "audio", "default": 80, "min": 0, "max": 100},
	"mute": {"section": "audio", "default": false},
	"mute_unfocused": {"section": "audio", "default": true},
	# Acessibilidade
	"reduce_motion": {"section": "accessibility", "default": false},
	"team_markers": {"section": "accessibility", "default": false},
}

## Teclas que, ao mudar, pedem confirmação com reversão automática (podem deixar a tela inutilizável).
const RISKY_KEYS := ["window_mode", "resolution", "screen"]

const CUTSCENE_LENGTH_FACTOR := {"short": 0.6, "normal": 1.0, "long": 1.5}

## {desktop, web, mobile, touch, screens, os}. Ver detect_platform().
var platform: Dictionary
var _values := {}


func _init(p_platform: Dictionary = {}) -> void:
	platform = p_platform if not p_platform.is_empty() else detect_platform()
	reset()


# --- plataforma ---------------------------------------------------------------------------------------

## Plataforma atual. `mobile` cobre app nativo e navegador de celular/tablet.
static func detect_platform() -> Dictionary:
	var web := OS.has_feature("web")
	var mobile := OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	var headless := DisplayServer.get_name() == "headless"
	return {
		"web": web,
		"mobile": mobile,
		"desktop": not web and not mobile,
		"touch": mobile or (not headless and DisplayServer.is_touchscreen_available()),
		"screens": 1 if headless else DisplayServer.get_screen_count(),
		"os": OS.get_name(),
	}


## A opção existe nesta plataforma? Opções indisponíveis ficam no padrão e somem do painel.
func is_available(key: String) -> bool:
	var desktop := bool(platform.get("desktop", false))
	var web := bool(platform.get("web", false))
	var mobile := bool(platform.get("mobile", false))
	match key:
		"window_mode":
			return desktop or web
		"resolution", "vsync":
			return desktop
		"screen":
			return desktop and int(platform.get("screens", 1)) > 1
		"orientation":
			return mobile
		"msaa_2d":
			return not mobile
	return SCHEMA.has(key)


## Opções válidas de `key` nesta plataforma (vazio para chaves sem lista fechada).
func options(key: String) -> Array:
	if not SCHEMA.has(key) or not SCHEMA[key].has("options"):
		return []
	var opts: Array = SCHEMA[key]["options"]
	if key == "window_mode" and bool(platform.get("web", false)):
		return ["windowed", "fullscreen"]
	return opts


# --- valores ------------------------------------------------------------------------------------------

func get_value(key: String) -> Variant:
	return _values.get(key, default_value(key))


## Grava `value` já validado. Devolve true se mudou.
func set_value(key: String, value: Variant) -> bool:
	if not SCHEMA.has(key):
		push_warning("GameSettings: chave desconhecida '%s'" % key)
		return false
	var clean: Variant = sanitize(key, value)
	if _values.has(key) and _values[key] == clean and typeof(_values[key]) == typeof(clean):
		return false
	_values[key] = clean
	return true


func default_value(key: String) -> Variant:
	var d: Variant = _platform_default(key)
	return d if d != null else SCHEMA[key]["default"]


## Volta tudo (ou só uma seção) ao padrão. Devolve as chaves que mudaram.
func reset(section: String = "") -> Array:
	var changed: Array = []
	for key in SCHEMA:
		if section != "" and SCHEMA[key]["section"] != section:
			continue
		if set_value(key, default_value(key)):
			changed.append(key)
	return changed


func keys_in(section: String) -> Array:
	return SCHEMA.keys().filter(func(k): return SCHEMA[k]["section"] == section)


## Converte e limita `value` ao domínio de `key`; valor inválido vira o padrão.
func sanitize(key: String, value: Variant) -> Variant:
	var spec: Dictionary = SCHEMA[key]
	var def: Variant = default_value(key)
	match typeof(spec["default"]):
		TYPE_BOOL:
			if value is bool:
				return value
			if value is int or value is float:
				return value != 0
			if value is String:
				return value.to_lower() in ["true", "1", "on", "sim"]
			return def
		TYPE_INT:
			if not (value is int or value is float or (value is String and value.is_valid_float())):
				return def
			var n := int(value)
			if spec.has("options"):
				return n if n in options(key) else def
			return clampi(n, int(spec.get("min", n)), int(spec.get("max", n)))
		TYPE_FLOAT:
			if not (value is int or value is float or (value is String and value.is_valid_float())):
				return def
			var f := float(value)
			if spec.has("options"):
				for o in options(key):
					if is_equal_approx(float(o), f):
						return float(o)
				return def
			return clampf(f, float(spec.get("min", f)), float(spec.get("max", f)))
		TYPE_STRING:
			var s := str(value)
			if key == "resolution":
				return s if s == "auto" or parse_resolution(s) != Vector2i.ZERO else def
			if spec.has("options"):
				return s if s in options(key) else def
			return s
	return def


func _platform_default(key: String) -> Variant:
	var mobile := bool(platform.get("mobile", false))
	var web := bool(platform.get("web", false))
	match key:
		"max_fps":
			# Celular: 60 poupa bateria e calor; navegador já segue o requestAnimationFrame.
			return 60 if mobile else null
		"window_mode":
			return "windowed" if web else null
	return null


# --- derivados ----------------------------------------------------------------------------------------

## Escala da interface efetiva. `ui_scale` 0 = automática: celulares e telas de toque pequenas (lado
## menor da janela abaixo de PHONE_SHORT_SIDE em pixels lógicos do sistema) ganham até 120% para o
## texto continuar legível, mas só enquanto a área lógica seguir com a largura de BASE_SIZE (em
## retrato isso dá 100%: ampliar cortaria as telas de várias colunas). Janela pequena no desktop fica
## em 100%: ali o que falta é espaço, não leitura.
func effective_ui_scale(window_size_px: Vector2 = Vector2.ZERO, screen_scale: float = 1.0) -> float:
	var s := float(get_value("ui_scale"))
	if s > 0.0:
		return s
	return auto_ui_scale(platform, window_size_px, screen_scale)


static func auto_ui_scale(p_platform: Dictionary, window_size_px: Vector2, screen_scale: float) -> float:
	if window_size_px == Vector2.ZERO:
		return 1.2 if bool(p_platform.get("mobile", false)) else 1.0
	var short_side := minf(window_size_px.x, window_size_px.y) / maxf(screen_scale, 0.01)
	if bool(p_platform.get("mobile", false)) or (bool(p_platform.get("touch", false)) and short_side < PHONE_SHORT_SIDE):
		# Com aspect "expand", a largura lógica é 1100/f quando a largura limita e
		# 720·(L/A)/f quando a altura limita: f até onde a largura lógica ainda é >= 1100.
		var aspect := window_size_px.x / maxf(window_size_px.y, 1.0)
		var room := float(BASE_SIZE.y) * aspect / float(BASE_SIZE.x)
		return clampf(room, 1.0, 1.2)
	return 1.0


## FPS máximo efetivo (0 = sem limite), já com a economia de bateria.
func effective_max_fps() -> int:
	var fps := int(get_value("max_fps"))
	if bool(get_value("battery_saver")):
		return 30 if fps == 0 or fps > 30 else fps
	return fps


func touch_controls_visible() -> bool:
	return _auto_flag("touch_controls", bool(platform.get("touch", false)))


func key_hints_visible() -> bool:
	return _auto_flag("key_hints", not bool(platform.get("mobile", false)) and not bool(platform.get("touch", false)))


func cutscene_length_factor() -> float:
	return float(CUTSCENE_LENGTH_FACTOR.get(get_value("cutscene_length"), 1.0))


func _auto_flag(key: String, auto_value: bool) -> bool:
	match str(get_value(key)):
		"on": return true
		"off": return false
	return auto_value


## "1920x1080" -> Vector2i(1920, 1080); inválido -> ZERO.
static func parse_resolution(s: String) -> Vector2i:
	var parts := s.to_lower().split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	var v := Vector2i(int(parts[0]), int(parts[1]))
	return v if v.x >= MIN_WINDOW.x and v.y >= MIN_WINDOW.y else Vector2i.ZERO


## Presets que cabem na área útil do monitor (sempre inclui "auto" e o valor atual).
func resolution_options(usable: Vector2i) -> Array:
	var out: Array = ["auto"]
	for r in RESOLUTION_PRESETS:
		var v := parse_resolution(r)
		if usable == Vector2i.ZERO or (v.x <= usable.x and v.y <= usable.y):
			out.append(r)
	var cur := str(get_value("resolution"))
	if not cur in out:
		out.append(cur)
	return out


## Janela "automática": a maior escala de BASE_SIZE que ocupa até 85% da área útil.
static func auto_window_size(usable: Vector2i) -> Vector2i:
	if usable == Vector2i.ZERO:
		return BASE_SIZE
	var k := minf(usable.x * 0.85 / BASE_SIZE.x, usable.y * 0.85 / BASE_SIZE.y)
	var size := Vector2i(roundi(BASE_SIZE.x * k), roundi(BASE_SIZE.y * k))
	return Vector2i(maxi(size.x, MIN_WINDOW.x), maxi(size.y, MIN_WINDOW.y))


# --- persistência -------------------------------------------------------------------------------------

func to_config() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", VERSION)
	for key in SCHEMA:
		cfg.set_value(SCHEMA[key]["section"], key, get_value(key))
	return cfg


## Lê um ConfigFile. Chaves ausentes ou inválidas ficam no padrão; chaves desconhecidas são ignoradas.
func from_config(cfg: ConfigFile) -> void:
	reset()
	for key in SCHEMA:
		var section: String = SCHEMA[key]["section"]
		if cfg.has_section_key(section, key):
			set_value(key, cfg.get_value(section, key))


func load_file(path: String = PATH) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		reset()
		return false
	from_config(cfg)
	return true


func save_file(path: String = PATH) -> bool:
	return to_config().save(path) == OK


func to_dict() -> Dictionary:
	var d := {}
	for key in SCHEMA:
		d[key] = get_value(key)
	return d
