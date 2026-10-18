class_name TeamSetup
extends RefCounted
## O que o técnico entrega antes do "Play" (GDD 2.3). Também é o formato do snapshot defensivo
## que o servidor guarda para outros jogadores enfrentarem.

var club_id: String = ""
var name: String = ""
var short_name: String = ""
var color: Color = Color.WHITE
var slots: Array = []          # 11 x {role: GK|DEF|MID|FWD, x: 0..1, y: 0..1} no referencial "atacando para a direita"
var lineup: Array = []         # 11 Athlete, na mesma ordem de slots
var bench: Array = []          # até ruleset.core.bench_size Athlete
var shirts: Dictionary = {}    # athlete_id -> número
## Livre para mecânicas: "mentality", "auto_subs", "penalty_order"... Cada mecânica documenta suas chaves.
var tactics: Dictionary = {}


func shirt_of(a: Athlete, fallback: int) -> int:
	return int(shirts.get(a.id, fallback))


## Validação do núcleo + mecânicas (hook LINEUP_VALIDATE).
func validate(ruleset: Ruleset = null, bus: HookBus = null) -> PackedStringArray:
	var errs: Array = []
	var lineup_size := 11 if ruleset == null else int(ruleset.core_param("lineup_size"))
	var bench_size := 5 if ruleset == null else int(ruleset.core_param("bench_size"))
	if slots.size() != lineup_size:
		errs.append("A formação precisa de %d posições (tem %d)." % [lineup_size, slots.size()])
	if lineup.size() != lineup_size:
		errs.append("Escale %d titulares (tem %d)." % [lineup_size, lineup.size()])
	if bench.size() > bench_size:
		errs.append("No máximo %d reservas (tem %d)." % [bench_size, bench.size()])
	var seen := {}
	for a in lineup + bench:
		if seen.has(a.id):
			errs.append("Atleta repetido: %s." % a.name)
		seen[a.id] = true
		if not a.is_active():
			errs.append("%s está aposentado." % a.name)
	var gk_slots := slots.filter(func(s): return s.get("role") == "GK").size()
	if gk_slots != 1:
		errs.append("A formação precisa de exatamente 1 goleiro (tem %d)." % gk_slots)
	if bus != null:
		errs = bus.pipe(Hooks.LINEUP_VALIDATE, errs, {"team_setup": self})
	return PackedStringArray(errs)
