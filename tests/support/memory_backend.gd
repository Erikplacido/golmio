class_name MemoryBackend
extends LocalBackend
## Backend em memória para testes: mundo, resultados e relógio do servidor sem tocar em user://.

var saved: Dictionary = {}
var results: Array = []
## Relógio fixo do servidor (segundos Unix UTC).
var now := 1791633600   # 2026-10-10 12:00 UTC


func load_world() -> Dictionary:
	return saved.duplicate(true)


func save_world(data: Dictionary) -> bool:
	saved = data.duplicate(true)
	return true


func submit_match_result(result: Dictionary) -> Dictionary:
	results.append(result.duplicate(true))
	return {"accepted": true}


func fetch_match_results(club_id: String = "", limit: int = 0) -> Array:
	var out: Array = []
	for i in range(results.size() - 1, -1, -1):
		var r: Dictionary = results[i]
		if club_id == "" or str(r.get("home", {}).get("club_id", "")) == club_id \
				or str(r.get("away", {}).get("club_id", "")) == club_id:
			out.append(r)
			if limit > 0 and out.size() >= limit:
				break
	return out


func server_time() -> int:
	return now


## Avança o relógio do servidor em dias.
func advance_days(days: int) -> void:
	now += days * 86400
