class_name MatchReporter
extends RefCounted
## Aplica as consequências de uma partida concluída ao mundo, disparando hooks globais.
## O NÚCLEO não sabe o que acontece (idade, dinheiro, torcida...): cada mecânica ouve e reage.
## No modelo online isto roda no servidor, uma única vez por partida (GDD 2.1).

static func report(registry: MechanicRegistry, world: World, result: Dictionary, date: String) -> void:
	var participants: Array = []
	for side in ["home", "away"]:
		for aid in result.get(side, {}).get("participants", []):
			if world.athletes.has(aid) and not participants.has(aid):
				participants.append(aid)
	var payload := {"world": world, "result": result, "date": date, "participants": participants}
	registry.bus.emit(Hooks.MATCH_PLAYED, payload)
	if result.get("kind", "") == "official":
		registry.bus.emit(Hooks.OFFICIAL_MATCH_PLAYED, payload)


## Idade atual do atleta (quem responde é a mecânica de carreira, se ligada).
static func athlete_age(registry: MechanicRegistry, athlete: Athlete) -> float:
	var base := float(athlete.dna.get("initial_age", 17))
	return float(registry.bus.pipe(Hooks.ATHLETE_AGE, base, {"athlete": athlete}))
