extends SceneTree
## Balanceamento: simula N partidas completas e compara as médias por time com o futebol real.
##   godot --headless --path jogo --script res://tests/balance.gd -- --matches=40
## Opções:
##   --ruleset=res://rulesets/arcade.json     ruleset a usar (padrão: default.json)
##   --set=shot_prob_far=0.2,block_chance_base=0.4   sobrescreve MatchTuning sem editar arquivos
##   --minutes=90 --seed=1000 --json            (--json: só imprime os totais, para agregação)
## Paralelo (usa todos os núcleos): ./tests/balance.sh 48 "--set=..."

## Metas por time em 90 min (médias de ligas de elite, Opta/FBref).
const TARGETS := {
	"goals": [1.2, 1.6],
	"shots": [11.0, 14.0],
	"shots_on_target": [3.5, 5.0],
	"shots_blocked": [2.5, 4.0],
	"passes_attempted": [380.0, 520.0],
	"pass_accuracy": [76.0, 84.0],
	"tackles": [15.0, 25.0],
	"saves": [2.2, 3.5],
	"corners": [4.0, 6.0],
}
const KEYS := ["crosses", "goals", "shots", "shots_on_target", "shots_blocked", "passes_attempted", "passes_completed", "tackles", "saves", "corners", "possession_ticks"]


func _init() -> void:
	var args := {"matches": "20", "ruleset": "res://rulesets/default.json", "minutes": "90", "seed": "1000", "set": ""}
	var as_json := false
	for a in OS.get_cmdline_user_args():
		if a == "--json":
			as_json = true
			continue
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var rs := Ruleset.load_file(args.ruleset)
	var overrides := _parse_set(str(args.set))
	if not overrides.is_empty():
		rs.core["tuning"] = Ruleset.deep_merge(rs.core.get("tuning", {}), overrides)
	var reg := MechanicRegistry.new()
	reg.discover()
	reg.apply_ruleset(rs)
	var n := int(args.matches)
	var tot := {"matches": n, "wins_home": 0, "wins_away": 0, "draws": 0, "home": {}, "away": {}}
	var t0 := Time.get_ticks_msec()
	for i in n:
		var e := MatchEngine.create(DemoData.match_setup(int(args.seed) + i, float(args.minutes)), reg)
		var r := e.run_to_end()
		match r.winner:
			"home": tot.wins_home += 1
			"away": tot.wins_away += 1
			_: tot.draws += 1
		for side in ["home", "away"]:
			for k in KEYS:
				tot[side][k] = int(tot[side].get(k, 0)) + int(r[side].stats.get(k, 0))
		e.dispose()
	if as_json:
		print("BALANCE_JSON " + JSON.stringify(tot))
	else:
		print_report(tot, reg, (Time.get_ticks_msec() - t0) / 1000.0)
	reg.dispose()
	quit()


static func print_report(tot: Dictionary, reg: MechanicRegistry, secs: float) -> void:
	var n := float(tot.matches)
	print("\nRuleset %s | mecânicas: %s | %d partidas | %.1f s" % [reg.ruleset.id, ", ".join(reg.enabled_ids()), tot.matches, secs])
	print("Vitórias: mandante %d | visitante %d | empates %d (%.0f%%)" % [tot.wins_home, tot.wins_away, tot.draws, 100.0 * tot.draws / n])
	print("%-18s %9s %9s %9s   %-13s" % ["por time/partida", "mandante", "visitante", "média", "meta real"])
	var rows := {}
	for k in TARGETS:
		var h: float
		var a: float
		if k == "pass_accuracy":
			h = 100.0 * tot.home.passes_completed / maxf(tot.home.passes_attempted, 1.0)
			a = 100.0 * tot.away.passes_completed / maxf(tot.away.passes_attempted, 1.0)
		else:
			h = tot.home[k] / n
			a = tot.away[k] / n
		var avg := (h + a) / 2.0
		var lo: float = TARGETS[k][0]
		var hi: float = TARGETS[k][1]
		var flag := "ok" if avg >= lo and avg <= hi else ("BAIXO" if avg < lo else "ALTO")
		print("%-18s %9.2f %9.2f %9.2f   %5.1f–%-6.1f %s" % [k, h, a, avg, lo, hi, flag])
	print("%-18s %9.2f %9.2f   (referência real: 15–20)" % ["cruzamentos", tot.home.get("crosses", 0) / n, tot.away.get("crosses", 0) / n])
	var pt := float(tot.home.possession_ticks + tot.away.possession_ticks)
	print("%-18s %8.0f%% %8.0f%%" % ["posse", 100.0 * tot.home.possession_ticks / maxf(pt, 1.0), 100.0 * tot.away.possession_ticks / maxf(pt, 1.0)])


static func _parse_set(s: String) -> Dictionary:
	var out := {}
	for pair in s.split(",", false):
		var kv := pair.split("=")
		if kv.size() != 2:
			continue
		var v: Variant = kv[1]
		if v == "true" or v == "false":
			v = v == "true"
		elif v.is_valid_float():
			v = float(v)
		var path := kv[0].strip_edges().split(".")
		var node := out
		for i in path.size() - 1:
			if not node.has(path[i]):
				node[path[i]] = {}
			node = node[path[i]]
		node[path[-1]] = v
	return out
