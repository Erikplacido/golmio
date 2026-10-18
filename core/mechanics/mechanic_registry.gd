class_name MechanicRegistry
extends RefCounted
## Descobre as mecânicas em res://mechanics/*, aplica o ruleset (liga/desliga + parâmetros),
## resolve dependências/conflitos e instala os hooks.
##
## Adicionar mecânica  = criar a pasta res://mechanics/<id>/mechanic.gd (nada mais a registrar).
## Desligar mecânica   = "enabled": false no ruleset.
## Remover mecânica    = apagar a pasta; saves antigos continuam válidos (dados em ext ficam dormentes).

const DEFAULT_DIR := "res://mechanics"

var available: Dictionary = {}      # id -> Mechanic (todas as descobertas)
var enabled: Array = []             # Mechanic ativas, em ordem de dependência
var ruleset: Ruleset = Ruleset.from_dict({})
var bus: HookBus = HookBus.new()    # bus global (mundo, carreira, economia)
var warnings: PackedStringArray = []
var errors: PackedStringArray = []
var _enabled_ids: Dictionary = {}
var _discovery_warnings: PackedStringArray = []
var _discovery_errors: PackedStringArray = []


func discover(dir: String = DEFAULT_DIR) -> void:
	var subdirs := Array(DirAccess.get_directories_at(dir))
	subdirs.sort()
	for sub in subdirs:
		if sub.begins_with("_") or sub.begins_with("."):
			continue  # _template, _rascunhos etc. nunca são carregados
		var path := dir.path_join(sub).path_join("mechanic.gd")
		if not ResourceLoader.exists(path):
			_discovery_warn("Pasta '%s' sem mechanic.gd — ignorada." % sub)
			continue
		var script: Script = load(path)
		var inst: Variant = script.new() if script else null
		if not (inst is Mechanic):
			_discovery_error("%s não estende Mechanic." % path)
			continue
		var m: Mechanic = inst
		if m.id.is_empty():
			m.id = sub
		if m.id != sub:
			_discovery_error("Mecânica '%s' está na pasta '%s': id e pasta devem ser iguais." % [m.id, sub])
			continue
		register(m)


## Registro manual (útil em testes ou para mecânicas vindas de outro lugar).
func register(m: Mechanic) -> void:
	if available.has(m.id):
		_discovery_error("Mecânica duplicada: %s" % m.id)
		return
	if not Mechanic.LAYERS.has(m.layer):
		_discovery_warn("Mecânica '%s' com camada desconhecida '%s'." % [m.id, m.layer])
	if not Mechanic.STAGES.has(m.stage):
		_discovery_warn("Mecânica '%s' com estágio desconhecido '%s'." % [m.id, m.stage])
	if m.stage == "experimental" and m.enabled_by_default:
		_discovery_warn("Mecânica experimental '%s' não pode nascer ligada (enabled_by_default)." % m.id)
	available[m.id] = m


func _discovery_warn(msg: String) -> void:
	_discovery_warnings.append(msg)
	warnings.append(msg)


func _discovery_error(msg: String) -> void:
	_discovery_errors.append(msg)
	errors.append(msg)


func apply_ruleset(rs: Ruleset) -> void:
	ruleset = rs
	warnings = _discovery_warnings.duplicate()
	errors = _discovery_errors.duplicate()
	var want: Dictionary = {}
	for mid in available:
		if rs.is_enabled(mid, available[mid].enabled_by_default):
			want[mid] = true
	for mid in rs.mechanics:
		if not available.has(mid) and rs.is_enabled(mid, false):
			warnings.append("Ruleset '%s' liga '%s', mas essa mecânica não existe (removida?). Ignorada." % [rs.id, mid])

	# Conflitos: quem DECLARA o conflito cede (a mecânica estabelecida permanece).
	# Se as duas se declaram incompatíveis, a de id alfabeticamente maior cede.
	var ids := want.keys()
	ids.sort()
	for mid in ids:
		if not want.has(mid):
			continue
		for other in available[mid].conflicts_with:
			if not want.has(other):
				continue
			var loser: String = mid
			if available[other].conflicts_with.has(mid) and other > mid:
				loser = other
			want.erase(loser)
			errors.append("Conflito: '%s' e '%s' não podem ficar ligadas juntas; '%s' foi desligada." % [mid, other, loser])
			if loser == mid:
				break

	# Dependências: desliga em cascata quem depende de algo ausente/desligado.
	var changed := true
	while changed:
		changed = false
		for mid in want.keys():
			for dep in available[mid].depends_on:
				if not want.has(dep):
					want.erase(mid)
					warnings.append("'%s' desligada: depende de '%s', que está desligada ou não existe." % [mid, dep])
					changed = true
					break

	for mid in want:
		if available[mid].stage == "deprecated":
			warnings.append("'%s' está deprecada e ainda ligada no ruleset '%s': planeje a remoção." % [mid, rs.id])

	enabled = _topological_order(want)
	_enabled_ids.clear()
	for m in enabled:
		_enabled_ids[m.id] = true
		m.params = rs.params_for(m.id, m.default_params)
		m.registry = self

	bus = HookBus.new(known_hooks())
	for m in enabled:
		m.install(bus)


## Quebra os ciclos registro <-> mecânicas <-> bus. Chame ao descartar o registro (ex.: ao sair do jogo).
func dispose() -> void:
	for mid in available:
		available[mid].registry = null
	available.clear()
	enabled.clear()
	_enabled_ids.clear()
	bus = HookBus.new()


func is_enabled(mechanic_id: String) -> bool:
	return _enabled_ids.has(mechanic_id)


func get_mechanic(mechanic_id: String) -> Mechanic:
	return available.get(mechanic_id) if is_enabled(mechanic_id) else null


func enabled_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for m in enabled:
		out.append(m.id)
	return out


## Hooks válidos = núcleo + os declarados por QUALQUER mecânica descoberta (ligada ou não).
## Assim, ouvir um hook de uma mecânica desligada é inofensivo (só não dispara).
func known_hooks() -> Dictionary:
	var known := Hooks.CATALOG.duplicate()
	for mid in available:
		for h in available[mid].provides_hooks:
			known[str(h)] = available[mid].provides_hooks[h]
	return known


## Cria o bus da partida e deixa cada mecânica ligada registrar seus hooks.
func setup_match(ctx: MatchContext) -> void:
	ctx.bus = HookBus.new(known_hooks())
	for m in enabled:
		m.setup_match(ctx)


## Identifica exatamente quais regras produziram um resultado (vai junto de cada partida).
func signature() -> Dictionary:
	var mech := {}
	for m in enabled:
		mech[m.id] = {"v": m.version, "params": m.params}
	var core_and_mech := {"engine": MatchEngine.ENGINE_VERSION, "core": ruleset.core, "mechanics": mech}
	return {
		"engine": MatchEngine.ENGINE_VERSION,
		"ruleset": ruleset.id,
		"ruleset_version": ruleset.version,
		"mechanics": enabled_ids(),
		"hash": JSON.stringify(core_and_mech, "", true).sha256_text().substr(0, 16),
	}


func _topological_order(want: Dictionary) -> Array:
	var ids := want.keys()
	ids.sort()
	var out: Array = []
	var state: Dictionary = {}  # 1 = visitando, 2 = pronto
	for mid in ids:
		_visit(mid, want, state, out)
	return out


func _visit(mid: String, want: Dictionary, state: Dictionary, out: Array) -> void:
	if state.get(mid, 0) == 2:
		return
	if state.get(mid, 0) == 1:
		errors.append("Dependência circular envolvendo '%s'." % mid)
		return
	state[mid] = 1
	var deps: Array = available[mid].depends_on.duplicate()
	deps.sort()
	for dep in deps:
		if want.has(dep):
			_visit(dep, want, state, out)
	state[mid] = 2
	out.append(available[mid])
