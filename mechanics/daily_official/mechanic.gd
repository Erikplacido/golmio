extends Mechanic
## Campeonato Oficial diário (GDD 2.1): no máximo `per_day` jogos oficiais por clube em cada dia
## real (data do servidor, UTC). O oficial é o único jogo que conta dia de carreira: quem envelhece
## é a career_aging, que ouve OFFICIAL_MATCH_PLAYED; esta mecânica só conta e libera a vaga do dia.
## Dados em club.ext["daily_official"] = {"date": data do último oficial, "count": oficiais nela}.
## Oferece `daily_official.status` para a interface (Início, Pré-jogo) e o servidor validarem.


func _init() -> void:
	id = "daily_official"
	title = "Jogo oficial diário"
	description = "Um jogo do Campeonato Oficial por dia real, o único que conta dia de carreira (GDD 2.1)."
	version = 1
	data_version = 1
	layer = "meta"
	stage = "experimental"
	enabled_by_default = false
	default_params = {
		"per_day": 1,   # oficiais por clube em cada data do servidor
	}
	provides_hooks = {
		"daily_official.status": "decide {club, date} -> {available, played, remaining, last_date}: o clube ainda pode jogar o oficial nesta data (AAAA-MM-DD do servidor)?",
	}


func install(bus: HookBus) -> void:
	bus.on(Hooks.OFFICIAL_MATCH_PLAYED, _on_official, id)
	bus.on("daily_official.status", _on_status, id)


func _on_official(payload: Dictionary) -> void:
	var world: World = payload.world
	var date := str(payload.date)
	var result: Dictionary = payload.result
	for side in ["home", "away"]:
		var club: Club = world.clubs.get(str(result.get(side, {}).get("club_id", "")))
		if club == null:
			continue
		var d := club.ext_for(id)
		if str(d.get("date", "")) != date:
			d["date"] = date
			d["count"] = 0
		d["count"] = int(d.get("count", 0)) + 1


func _on_status(payload: Dictionary) -> Dictionary:
	var club: Club = payload.get("club")
	var date := str(payload.get("date", ""))
	var d: Dictionary = club.ext.get(id, {}) if club else {}
	var played := int(d.get("count", 0)) if str(d.get("date", "")) == date else 0
	var per_day := int(param("per_day"))
	return {
		"available": club != null and date != "" and played < per_day,
		"played": played,
		"remaining": maxi(per_day - played, 0),
		"last_date": str(d.get("date", "")),
	}
