class_name Fixtures
extends RefCounted
## Atalhos para montar registro/ruleset/partidas nos testes.

const SHORT_MINUTES := 8.0


static func registry(ruleset_path: String = "res://rulesets/default.json") -> MechanicRegistry:
	var reg := MechanicRegistry.new()
	reg.discover()
	reg.apply_ruleset(Ruleset.load_file(ruleset_path))
	return reg


## Registro com exatamente as mecânicas pedidas ligadas (as demais desligadas).
static func registry_with(ids: Array, params: Dictionary = {}) -> MechanicRegistry:
	var mech := {}
	for mid in ids:
		mech[mid] = {"enabled": true, "params": params.get(mid, {})}
	var reg := MechanicRegistry.new()
	reg.discover()
	reg.apply_ruleset(Ruleset.from_dict({"id": "test", "unlisted_mechanics": "off", "mechanics": mech}))
	return reg


static func engine(reg: MechanicRegistry, rng_seed: int = 1, minutes: float = SHORT_MINUTES, knockout: bool = false) -> MatchEngine:
	var setup := DemoData.match_setup(rng_seed, minutes)
	setup.knockout = knockout
	return MatchEngine.create(setup, reg)


## Avança até a bola estar rolando (sem bola parada pendente).
static func until_live(e: MatchEngine) -> void:
	var guard := 0
	while not e.ctx.restart.is_empty() and guard < 500:
		e.step()
		guard += 1
