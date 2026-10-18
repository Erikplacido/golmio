class_name TestSettings
extends TestCase
## Preferências do jogador (GameSettings): padrões por plataforma, validação, opções disponíveis,
## derivados (escala, FPS, controles de toque) e ida e volta em ConfigFile.

const DESKTOP := {"desktop": true, "web": false, "mobile": false, "touch": false, "screens": 2, "os": "macOS"}
const WEB_DESKTOP := {"desktop": false, "web": true, "mobile": false, "touch": false, "screens": 1, "os": "Web"}
const WEB_PHONE := {"desktop": false, "web": true, "mobile": true, "touch": true, "screens": 1, "os": "Web"}
const PHONE := {"desktop": false, "web": false, "mobile": true, "touch": true, "screens": 1, "os": "Android"}


func test_padroes_por_plataforma() -> void:
	var d := GameSettings.new(DESKTOP)
	check_eq(d.get_value("window_mode"), "windowed", "desktop abre em janela")
	check_eq(d.get_value("max_fps"), 0, "desktop sem limite (V-Sync segura)")
	check_eq(d.get_value("aspect"), "expand", "preencher a tela por padrão")
	var p := GameSettings.new(PHONE)
	check_eq(p.get_value("max_fps"), 60, "celular limita a 60")
	check_eq(p.get_value("orientation"), "auto", "celular gira com o aparelho")


func test_opcoes_disponiveis_por_plataforma() -> void:
	var d := GameSettings.new(DESKTOP)
	check(d.is_available("resolution") and d.is_available("vsync") and d.is_available("screen"), "desktop tem janela, V-Sync e monitor")
	check(not d.is_available("orientation"), "desktop não tem orientação")
	check(not GameSettings.new(DESKTOP.merged({"screens": 1}, true)).is_available("screen"), "um monitor: sem seletor")
	var w := GameSettings.new(WEB_DESKTOP)
	check(w.is_available("window_mode"), "navegador alterna tela cheia")
	check(not w.is_available("resolution") and not w.is_available("vsync"), "navegador não controla tamanho nem V-Sync")
	check_eq(w.options("window_mode"), ["windowed", "fullscreen"], "navegador: só janela e tela cheia")
	var wp := GameSettings.new(WEB_PHONE)
	check(wp.is_available("orientation"), "navegador do celular tem orientação")
	var p := GameSettings.new(PHONE)
	check(not p.is_available("window_mode") and not p.is_available("msaa_2d"), "app de celular é sempre tela cheia, sem MSAA")


func test_valores_invalidos_viram_padrao_ou_sao_limitados() -> void:
	var s := GameSettings.new(DESKTOP)
	s.set_value("window_mode", "janela_magica")
	check_eq(s.get_value("window_mode"), "windowed", "opção inexistente")
	s.set_value("max_fps", 75)
	check_eq(s.get_value("max_fps"), 0, "FPS fora da lista")
	s.set_value("max_fps", "144")
	check_eq(s.get_value("max_fps"), 144, "texto numérico aceito")
	s.set_value("volume_music", 250)
	check_eq(s.get_value("volume_music"), 100, "volume limitado a 100")
	s.set_value("volume_sfx", -3)
	check_eq(s.get_value("volume_sfx"), 0, "volume limitado a 0")
	s.set_value("ui_scale", "1.5")
	check_near(float(s.get_value("ui_scale")), 1.5, 0.001, "escala de texto")
	s.set_value("ui_scale", 1.33)
	check_near(float(s.get_value("ui_scale")), 0.0, 0.001, "escala fora da lista volta ao automático")
	s.set_value("resolution", "320x200")
	check_eq(s.get_value("resolution"), "auto", "resolução menor que o mínimo")
	s.set_value("resolution", "1920x1080")
	check_eq(s.get_value("resolution"), "1920x1080", "resolução válida")
	s.set_value("cutscenes", "off")
	check_eq(s.get_value("cutscenes"), false, "booleano em texto")
	check(not s.set_value("nao_existe", 1), "chave desconhecida é ignorada")


func test_set_value_informa_mudanca() -> void:
	var s := GameSettings.new(DESKTOP)
	check(s.set_value("show_fps", true), "mudou")
	check(not s.set_value("show_fps", true), "mesmo valor não conta")


func test_reset_por_secao() -> void:
	var s := GameSettings.new(DESKTOP)
	s.set_value("show_fps", true)
	s.set_value("mute", true)
	var changed := s.reset("audio")
	check_eq(changed, ["mute"], "só a seção pedida")
	check_eq(s.get_value("show_fps"), true, "outra seção intacta")


func test_ida_e_volta_em_config_file() -> void:
	var s := GameSettings.new(DESKTOP)
	s.set_value("window_mode", "fullscreen")
	s.set_value("ui_scale", 1.25)
	s.set_value("volume_master", 35)
	s.set_value("team_markers", true)
	var cfg := s.to_config()
	cfg.set_value("display", "lixo", 123)
	cfg.set_value("audio", "volume_sfx", "muito alto")
	var back := GameSettings.new(DESKTOP)
	back.from_config(cfg)
	check_eq(back.get_value("window_mode"), "fullscreen", "modo")
	check_near(float(back.get_value("ui_scale")), 1.25, 0.001, "escala")
	check_eq(back.get_value("volume_master"), 35, "volume")
	check_eq(back.get_value("team_markers"), true, "marcadores")
	check_eq(back.get_value("volume_sfx"), 80, "valor inválido no arquivo volta ao padrão")

	var path := "user://test_settings_tmp.cfg"
	check(s.save_file(path), "salva")
	var loaded := GameSettings.new(DESKTOP)
	check(loaded.load_file(path), "carrega")
	check_eq(loaded.to_dict(), s.to_dict(), "arquivo preserva tudo")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(not GameSettings.new(DESKTOP).load_file("user://nao_existe.cfg"), "sem arquivo: padrões")


func test_escala_automatica() -> void:
	check_near(GameSettings.auto_ui_scale(DESKTOP, Vector2(1920, 1080), 1.0), 1.0, 0.001, "monitor comum")
	check_near(GameSettings.auto_ui_scale(DESKTOP, Vector2(2880, 1800), 2.0), 1.0, 0.001, "retina em pontos")
	check_near(GameSettings.auto_ui_scale(DESKTOP, Vector2(800, 500), 1.0), 1.0, 0.001, "janela pequena no desktop")
	check_near(GameSettings.auto_ui_scale(DESKTOP.merged({"touch": true}, true), Vector2(1000, 500), 1.0), 1.2, 0.001, "tela de toque pequena")
	check_near(GameSettings.auto_ui_scale(DESKTOP.merged({"touch": true}, true), Vector2(800, 500), 1.0), 720.0 * 1.6 / 1100.0, 0.001, "só o que a largura comporta")
	check_near(GameSettings.auto_ui_scale(PHONE, Vector2(2400, 1080), 3.0), 1.2, 0.001, "celular em paisagem")
	check_near(GameSettings.auto_ui_scale(PHONE, Vector2(1080, 2400), 3.0), 1.0, 0.001, "celular em retrato não corta o layout")
	check_near(GameSettings.auto_ui_scale(PHONE, Vector2(2048, 1536), 2.0), 1.0, 0.001, "tablet 4:3 já está no limite")
	var s := GameSettings.new(DESKTOP)
	s.set_value("ui_scale", 1.5)
	check_near(s.effective_ui_scale(Vector2(800, 500), 1.0), 1.5, 0.001, "escala manual vence")


func test_fps_e_economia_de_bateria() -> void:
	var s := GameSettings.new(DESKTOP)
	check_eq(s.effective_max_fps(), 0, "sem limite")
	s.set_value("battery_saver", true)
	check_eq(s.effective_max_fps(), 30, "economia limita a 30")
	s.set_value("max_fps", 30)
	check_eq(s.effective_max_fps(), 30, "limite menor é mantido")


func test_controles_de_toque_e_dicas() -> void:
	var d := GameSettings.new(DESKTOP)
	check(not d.touch_controls_visible() and d.key_hints_visible(), "desktop: teclado")
	var p := GameSettings.new(PHONE)
	check(p.touch_controls_visible() and not p.key_hints_visible(), "celular: toque")
	d.set_value("touch_controls", "on")
	p.set_value("key_hints", "on")
	check(d.touch_controls_visible() and p.key_hints_visible(), "forçados")


func test_resolucoes() -> void:
	check_eq(GameSettings.parse_resolution("1920x1080"), Vector2i(1920, 1080), "parse")
	check_eq(GameSettings.parse_resolution("abc"), Vector2i.ZERO, "inválida")
	var s := GameSettings.new(DESKTOP)
	var opts := s.resolution_options(Vector2i(1440, 875))
	check(opts.has("auto") and opts.has("1366x768"), "auto e as que cabem")
	check(not opts.has("1920x1080"), "esconde as que não cabem")
	var auto := GameSettings.auto_window_size(Vector2i(1920, 1050))
	check(auto.x <= 1920 * 0.86 and auto.y <= 1050 * 0.86, "automática ocupa até ~85%")
	check_near(float(auto.x) / auto.y, 1100.0 / 720.0, 0.01, "automática mantém a proporção de base")
	check_eq(GameSettings.auto_window_size(Vector2i(700, 400)), GameSettings.MIN_WINDOW, "nunca menor que o mínimo")


func test_duracao_das_vinhetas() -> void:
	var s := GameSettings.new(DESKTOP)
	check_near(s.cutscene_length_factor(), 1.0, 0.001, "normal")
	s.set_value("cutscene_length", "short")
	check(s.cutscene_length_factor() < 1.0, "curta")
	s.set_value("cutscene_length", "long")
	check(s.cutscene_length_factor() > 1.0, "longa")


## Velocidade da partida aceita ½× e lê saves antigos (inteiros) sem perder o valor.
func test_velocidade_meia() -> void:
	var s := GameSettings.new(DESKTOP)
	check_eq(s.get_value("match_speed"), 1.0, "padrão 1×")
	s.set_value("match_speed", 0.5)
	check_eq(s.get_value("match_speed"), 0.5, "½× aceito")
	s.set_value("match_speed", 3)
	check_eq(s.get_value("match_speed"), 3.0, "inteiro antigo vira 3.0")
	s.set_value("match_speed", 0.25)
	check_eq(s.get_value("match_speed"), 0.25, "¼× aceito")
	s.set_value("match_speed", 0.1)
	check_eq(s.get_value("match_speed"), 1.0, "fora das opções volta ao padrão")
	check_eq(MatchSpeedBar.label_for(0.25), "¼×")
	check_eq(MatchSpeedBar.label_for(0.5), "½×")
	check_eq(MatchSpeedBar.label_for(2.0), "2×")
