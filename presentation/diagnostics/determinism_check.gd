extends Control
## Roda as mesmas partidas do tests/fingerprint.gd (3 x 90 min, sementes 777+) e mostra a impressão
## digital. Mesma impressão que no desktop = simulação idêntica nesta plataforma.
## Processa em fatias por quadro para não congelar a página no navegador.

const MATCHES := 3
const MINUTES := 90.0
const TICKS_PER_FRAME := 1500

var _label: Label
var _engine: MatchEngine
var _index := 0
var _checksums := PackedStringArray()
var _lines := PackedStringArray()
var _t0 := 0


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(40, 40)
	_label.add_theme_font_size_override("font_size", UiKit.FONT_TITLE)
	add_child(_label)
	_t0 = Time.get_ticks_msec()
	_lines.append("FOTEBA — diagnóstico de determinismo (%s)" % _platform())
	_lines.append("assinatura %s" % App.registry.signature().hash)
	_start_next()


func _process(_delta: float) -> void:
	if _engine == null:
		return
	for i in TICKS_PER_FRAME:
		if _engine.is_finished():
			break
		_engine.step()
	var pct := 100.0 * _engine.ctx.tick / _engine.total_regular_ticks()
	if _engine.is_finished():
		var r := _engine.result
		_checksums.append(r.checksum)
		_lines.append("semente %d: checksum %s  placar %d x %d" % [SimFingerprint.DEFAULT_SEED + _index, r.checksum, r.home.goals, r.away.goals])
		print(_lines[-1])
		_engine.dispose()
		_engine = null
		_index += 1
		if _index < MATCHES:
			_start_next()
		else:
			var fp := SimFingerprint.combine(_checksums)
			_lines.append("FINGERPRINT %s   (%.1f s)" % [fp, (Time.get_ticks_msec() - _t0) / 1000.0])
			print(_lines[-1])
	_label.text = "\n".join(_lines) + ("" if _engine == null else "\npartida %d: %.0f%%" % [_index + 1, pct])


func _start_next() -> void:
	_engine = MatchEngine.create(DemoData.match_setup(SimFingerprint.DEFAULT_SEED + _index, MINUTES, "official"), App.registry)


func _platform() -> String:
	return "%s / %s" % [OS.get_name(), Engine.get_architecture_name()]


func _exit_tree() -> void:
	if _engine:
		_engine.dispose()
