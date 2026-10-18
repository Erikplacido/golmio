extends TestCase
## Determinismo entre plataformas (desktop, mobile, navegador).

const SCAN_DIRS := ["res://core", "res://mechanics"]
## Pastas fora da simulação (I/O, boot) e os únicos arquivos autorizados a usar as APIs cruas.
const SKIP_PREFIXES := ["res://core/boot", "res://core/backend", "res://mechanics/_template"]
const ALLOWED_FILES := ["res://core/util/dmath.gd", "res://core/util/seeded_rng.gd"]
const FORBIDDEN := {
	"(?<!DMath)\\.(length|length_squared|normalized|angle|dot|cross|distance_to|distance_squared_to|angle_to|angle_to_point|direction_to|lerp|slerp|rotated|limit_length|move_toward|bounce|reflect|project)\\(": "método composto do Vector2 (use DMath)",
	"from_angle": "Vector2.from_angle (use DMath.rotated)",
	"(?<![\\w.])(sin|cos|tan|asin|acos|atan|atan2|pow|exp|log|sinh|cosh|tanh|lerpf|lerp_angle|snappedf|smoothstep|move_toward|ease|wrapf|fposmod)\\(": "função de libm/composta (use DMath)",
	"(?<![\\w.])(randf|randi|randf_range|randi_range|randfn|randomize|seed)\\(": "aleatoriedade global (use ctx.rng / ctx.rng_for)",
	"(?<![\\w.])(Time|OS)\\.": "relógio/sistema não é determinístico",
}


func test_codigo_de_simulacao_so_usa_matematica_portavel() -> void:
	var regexes := {}
	for pat in FORBIDDEN:
		var re := RegEx.new()
		re.compile(pat)
		regexes[pat] = re
	for path in _gd_files():
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var code := _strip_comment(lines[i])
			for pat in regexes:
				if regexes[pat].search(code):
					failures.append("%s:%d — %s: %s" % [path, i + 1, FORBIDDEN[pat], code.strip_edges()])


func test_golden_fingerprint() -> void:
	var golden: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/determinism.json"))
	check(golden is Dictionary, "tests/golden/determinism.json ausente — gere com tests/fingerprint.gd -- --write-golden")
	if not (golden is Dictionary):
		return
	var reg := Fixtures.registry()
	var fp := SimFingerprint.compute(reg, int(golden.matches), float(golden.minutes), int(golden.seed))
	if fp.signature.hash != golden.signature_hash:
		failures.append("Regras mudaram (assinatura %s ≠ %s). Se foi intencional, regenere: godot --headless --path . --script res://tests/fingerprint.gd -- --write-golden" % [fp.signature.hash, golden.signature_hash])
		return
	check_eq(fp.fingerprint, golden.fingerprint,
		"simulação divergiu do golden. Mudança intencional no motor? regenere com --write-golden (e suba MatchEngine.ENGINE_VERSION). Não intencional em outra plataforma? há matemática não portável")
	reg.dispose()


func test_seno_deterministico_proximo_do_real() -> void:
	for x in [-10.0, -3.0, -1.0, 0.0, 0.5, 1.0, 2.0, 3.1, 7.0, 100.0]:
		check_near(DMath.dsin(x), sin(x), 1e-6, "dsin(%s)" % x)
		check_near(DMath.dcos(x), cos(x), 1e-6, "dcos(%s)" % x)


func _gd_files() -> Array:
	var out: Array = []
	for d in SCAN_DIRS:
		_walk(d, out)
	return out


func _walk(dir: String, out: Array) -> void:
	for skip in SKIP_PREFIXES:
		if dir.begins_with(skip):
			return
	for f in DirAccess.get_files_at(dir):
		var p := dir.path_join(f)
		if f.ends_with(".gd") and not ALLOWED_FILES.has(p):
			out.append(p)
	for sub in DirAccess.get_directories_at(dir):
		_walk(dir.path_join(sub), out)


func _strip_comment(line: String) -> String:
	var in_str := false
	for i in line.length():
		var ch := line[i]
		if ch == "\"":
			in_str = not in_str
		elif ch == "#" and not in_str:
			return line.substr(0, i)
	return line
