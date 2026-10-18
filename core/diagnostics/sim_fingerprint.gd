class_name SimFingerprint
extends RefCounted
## Impressão digital de um conjunto fixo de partidas. Mesma impressão em duas plataformas
## = simulação idêntica bit a bit. Usada por testes, pela cena de diagnóstico (inclusive no
## navegador) e, no futuro, para validar builds antes de publicar.

const DEFAULT_SEED := 777


## Retorna {"matches": [{seed, checksum, score}], "fingerprint": String, "signature": Dictionary}.
static func compute(registry: MechanicRegistry, matches: int = 3, minutes: float = 90.0, first_seed: int = DEFAULT_SEED) -> Dictionary:
	var list: Array = []
	var joined := PackedStringArray()
	for i in matches:
		var e := MatchEngine.create(DemoData.match_setup(first_seed + i, minutes, "official"), registry)
		var r := e.run_to_end()
		list.append({"seed": first_seed + i, "checksum": r.checksum, "score": "%d x %d" % [r.home.goals, r.away.goals]})
		joined.append(r.checksum)
		e.dispose()
	return {
		"matches": list,
		"fingerprint": combine(joined),
		"signature": registry.signature(),
	}


## Combina os checksums das partidas numa impressão única.
static func combine(checksums: PackedStringArray) -> String:
	return "|".join(checksums).sha256_text().substr(0, 16)
