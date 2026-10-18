class_name MatchStats
extends RefCounted
## Números de uma partida para as telas (intervalo P05 e resultado P07), a partir do `result`
## serializável do motor ou do contexto ao vivo. Só lê: nenhuma regra mora aqui.

## [chave i18n, campo] das linhas comparativas, na ordem da tela.
const ROWS := [
	["STAT_POSSE", "possession"], ["STAT_CHUTES", "shots"], ["STAT_NO_ALVO", "shots_on_target"],
	["STAT_XG", "xg"], ["STAT_PASSES", "pass_accuracy"], ["STAT_DESARMES", "tackles"],
	["STAT_DEFESAS", "saves"], ["STAT_ESCANTEIOS", "corners"],
]
const PERCENT_FIELDS := ["possession", "pass_accuracy"]


## {"home": {...}, "away": {...}} com as estatísticas do motor mais posse (%), acerto de passe (%)
## e xG (soma de data.xg dos chutes, se a xg_model estiver ligada; -1 sem xG).
static func from_result(result: Dictionary) -> Dictionary:
	var out := {}
	for side in ["home", "away"]:
		out[side] = (result.get(side, {}).get("stats", {}) as Dictionary).duplicate()
	_derive(out, result.get("events", []))
	return out


static func from_ctx(ctx: MatchContext) -> Dictionary:
	var out := {"home": ctx.home.stats.duplicate(), "away": ctx.away.stats.duplicate()}
	_derive(out, ctx.events)
	return out


static func _derive(out: Dictionary, events: Array) -> void:
	var total_pos := float(out.home.get("possession_ticks", 0) + out.away.get("possession_ticks", 0))
	var has_xg := false
	var xg := {"home": 0.0, "away": 0.0}
	for ev in events:
		if str(ev.get("type", "")) == "shot" and ev.get("data", {}).has("xg"):
			has_xg = true
			var team := str(ev.get("team", ""))
			if xg.has(team):
				xg[team] += float(ev.data.xg)
	for side in ["home", "away"]:
		var s: Dictionary = out[side]
		s["possession"] = 100.0 * float(s.get("possession_ticks", 0)) / total_pos if total_pos > 0.0 else 50.0
		var att := float(s.get("passes_attempted", 0))
		s["pass_accuracy"] = 100.0 * float(s.get("passes_completed", 0)) / att if att > 0.0 else 0.0
		s["xg"] = xg[side] if has_xg else -1.0


## Linhas para CompareBar: [[legenda, valor mandante, valor visitante, formato], ...].
static func rows(stats: Dictionary) -> Array:
	var out: Array = []
	for r in ROWS:
		var field: String = r[1]
		var h := float(stats.home.get(field, 0))
		var a := float(stats.away.get(field, 0))
		if field == "xg" and h < 0.0:
			continue
		var fmt := "%d%%" if PERCENT_FIELDS.has(field) else ("%.2f" if field == "xg" else "%d")
		out.append([TranslationServer.translate(r[0]), h, a, fmt])
	return out


## Gols, cartões e substituições na ordem: [{minute, period, type, team, athlete_id, data}].
static func highlights(events: Array, period: String = "") -> Array:
	var out: Array = []
	for ev in events:
		var t := str(ev.get("type", ""))
		if period != "" and str(ev.get("period", "")) != period:
			continue
		var card := str(ev.get("data", {}).get("card", ""))
		if t == "goal" or (t == "foul" and card != "") or t == "substitution":
			out.append({"minute": float(ev.get("t", 0.0)), "period": str(ev.get("period", "")), "type": t,
				"team": str(ev.get("team", "")), "athlete_id": str(ev.get("athlete_id", "")),
				"data": ev.get("data", {})})
	return out


## Texto de um lance para listas ("23' Gol de Fulano"). `names`: athlete_id -> nome.
static func describe(h: Dictionary, names: Dictionary) -> String:
	var who := str(names.get(h.athlete_id, ""))
	var minute := "%d'" % ceili(float(h.minute))
	match str(h.type):
		"goal":
			var key := "LANCE_GOL_CONTRA" if bool(h.data.get("own_goal", false)) else "LANCE_GOL"
			return "%s  %s" % [minute, TranslationServer.translate(key) % who]
		"foul":
			var key := "LANCE_VERMELHO" if str(h.data.get("card", "")) == "red" else "LANCE_AMARELO"
			return "%s  %s" % [minute, TranslationServer.translate(key) % who]
		"substitution":
			return "%s  %s" % [minute, TranslationServer.translate("LANCE_SUBSTITUICAO") % [
				str(names.get(str(h.data.get("in", "")), "")), str(names.get(str(h.data.get("out", "")), ""))]]
	return minute


## Ícone (GameIcons) de um lance.
static func icon_for(h: Dictionary) -> String:
	match str(h.type):
		"goal":
			return "gol"
		"foul":
			return "vermelho" if str(h.data.get("card", "")) == "red" else "amarelo"
		"substitution":
			return "substituicao"
	return "falta"
