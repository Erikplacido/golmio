class_name PreviewAthletes
extends RefCounted
## Atletas de vitrine (pré-visualização do uniforme na criação do clube, escalação de demonstração):
## gerados pelo athlete_generator oficial com semente fixa, então o rosto só usa peças ativas e
## compatíveis do catálogo, igual a um atleta de verdade. Nada é gravado (commit = false,
## unique = false). Montar a receita à mão (head_001, head_002...) pega cabeças sem soquetes e o
## retrato sai vazio.

const HOOK_GENERATE := "athlete_generator.generate"
const SEED := 20260927

static var _registry: MechanicRegistry = null
static var _cache := {}   # chave -> Array[Athlete]


## `positions` e `tiers` com um item por atleta. Vazio se o gerador não estiver disponível.
static func generate(positions: Array, tiers: Array, seed: int = SEED) -> Array[Athlete]:
	var key := "%s|%s|%d" % [",".join(PackedStringArray(positions)), ",".join(PackedStringArray(tiers)), seed]
	if _cache.has(key):
		return (_cache[key] as Array[Athlete]).duplicate()
	var out: Array[Athlete] = []
	var reg := _generator_registry()
	if reg == null:
		return out
	var res: Variant = reg.bus.decide(HOOK_GENERATE, {
		"world": World.new(), "seed": seed, "count": positions.size(), "tiers": tiers,
		"positions": positions, "origin": {"source": "preview"}, "unique": false, "commit": false,
	})
	if res is Dictionary and bool(res.get("ok", false)):
		for a in res.get("athletes", []):
			if a is Athlete:
				out.append(a)
	else:
		push_warning("PreviewAthletes: gerador falhou: %s" % str(res))
	_cache[key] = out
	return out.duplicate()


## O registro do jogo se ele já tem o gerador ligado; senão um próprio, com o gerador ligado à força
## (o mesmo do protótipo de pacotes).
static func _generator_registry() -> MechanicRegistry:
	var tree := Engine.get_main_loop() as SceneTree
	var app: Node = tree.root.get_node_or_null("App") if tree else null
	if app and app.get("registry") is MechanicRegistry and (app.registry as MechanicRegistry).bus.has_handlers(HOOK_GENERATE):
		return app.registry
	if _registry == null:
		_registry = PackOpeningView.build_registry()
	return _registry if _registry.bus.has_handlers(HOOK_GENERATE) else null
