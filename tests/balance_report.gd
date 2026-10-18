extends SceneTree
## Agrega os JSONs gerados por tests/balance.sh e imprime o relatório de balanceamento.

const Balance := preload("res://tests/balance.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir := args[0]
	var ruleset := "res://rulesets/default.json"
	var overrides := ""
	for a in args:
		if a.begins_with("--ruleset="):
			ruleset = a.trim_prefix("--ruleset=")
		elif a.begins_with("--set="):
			overrides = a.trim_prefix("--set=")
	var tot := {"matches": 0, "wins_home": 0, "wins_away": 0, "draws": 0, "home": {}, "away": {}}
	for f in DirAccess.get_files_at(dir):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
		if not (d is Dictionary):
			continue
		for k in ["matches", "wins_home", "wins_away", "draws"]:
			tot[k] += int(d[k])
		for side in ["home", "away"]:
			for k in d[side]:
				tot[side][k] = int(tot[side].get(k, 0)) + int(d[side][k])
	var rs := Ruleset.load_file(ruleset)
	var reg := MechanicRegistry.new()
	reg.discover()
	reg.apply_ruleset(rs)
	Balance.print_report(tot, reg, 0.0)
	if overrides != "":
		print("tuning: " + overrides)
	reg.dispose()
	quit()
