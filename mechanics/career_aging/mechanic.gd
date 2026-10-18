extends Mechanic
## Ciclo biológico (GDD 2.1 e 6): cada ENTRADA EM CAMPO em jogo oficial = 1 dia de carreira.
## 25 dias = 1 ano. Crescimento +1 nos aniversários 18..27, platô 28..37, declínio -1,5 em 38..45,
## aposentadoria aos 45. Dados em athlete.ext["career_aging"] = {days, last_official_date}.


func _init() -> void:
	id = "career_aging"
	title = "Ciclo biológico de carreira"
	description = "Envelhecimento por participação em jogos oficiais, crescimento, platô, declínio e aposentadoria."
	version = 1
	data_version = 1
	layer = "career"
	enabled_by_default = true
	default_params = {
		"start_age": 17,
		"days_per_year": 25,
		"stages": [
			{"from_age": 18, "to_age": 27, "delta": 1.0},     # crescimento
			{"from_age": 38, "to_age": 45, "delta": -1.5},    # declínio (28..37 = platô)
		],
		"retire_age": 45,
		"affected": ["pace", "physical", "passing", "finishing", "tackling", "positioning",
			"reflexes", "elasticity", "stamina"],
	}


func install(bus: HookBus) -> void:
	bus.on(Hooks.OFFICIAL_MATCH_PLAYED, _on_official, id)
	bus.on(Hooks.ATHLETE_AGE, _on_age_query, id)


func days_of(a: Athlete) -> int:
	return int(a.ext.get(id, {}).get("days", 0))


func age_of(a: Athlete) -> float:
	var start := float(a.dna.get("initial_age", param("start_age")))
	return start + float(days_of(a)) / float(param("days_per_year"))


func _on_age_query(_value: float, payload: Dictionary) -> float:
	return age_of(payload.athlete)


func _on_official(payload: Dictionary) -> void:
	var world: World = payload.world
	var date := str(payload.date)
	var per_year := int(param("days_per_year"))
	for aid in payload.participants:
		var a: Athlete = world.athletes.get(aid)
		if a == null or not a.is_active():
			continue
		var d := a.ext_for(id)
		# Um dia por atleta por data, mesmo se trocar de clube no mesmo dia (GDD 5.4).
		if str(d.get("last_official_date", "")) == date:
			continue
		d["last_official_date"] = date
		d["days"] = int(d.get("days", 0)) + 1
		if int(d.days) % per_year == 0:
			var age := int(round(age_of(a)))
			_apply_birthday(a, age)
			registry.bus.emit(Hooks.ATHLETE_BIRTHDAY, {"athlete": a, "age": age})
			if age >= int(param("retire_age")):
				a.status = "retired"
				registry.bus.emit(Hooks.ATHLETE_RETIRED, {"athlete": a})


func _apply_birthday(a: Athlete, age: int) -> void:
	var delta := 0.0
	for s in param("stages"):
		if age >= int(s.from_age) and age <= int(s.to_age):
			delta += float(s.delta)
	if delta == 0.0:
		return
	var lo := AttributeCatalog.min_value()
	var hi := AttributeCatalog.max_value()
	for k in param("affected"):
		if a.attributes.has(k):
			a.attributes[k] = clampf(float(a.attributes[k]) + delta, lo, hi)
