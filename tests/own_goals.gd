extends SceneTree
## Diagnóstico de gols contra: joga N partidas e classifica cada gol contra pela última ação de
## quem tocou na bola (recuo para o goleiro, passe para trás, domínio errado, reposição...).
##   godot --headless --path jogo --script res://tests/own_goals.gd -- --mode=gerado_fraco --matches=32
## Modos:
##   gerado_fraco   elenco inicial gerado (OnboardingService, OVR ~34) × anil deslocado para --target
##   gerado_demo    elenco inicial gerado × anil real (OVR ~66)
##   demo           rubro × anil (os clubes da calibração)
##   demo_fraco     rubro e anil deslocados para --target
## Opções: --target=34 --seed=5000 --minutes=90 --ruleset=res://rulesets/dev.json
##         --set=chave=valor,... (sobrescreve MatchTuning, como no balance.gd)
## A classificação lê ctx.message (texto da narração): serve para diagnóstico, não para regra.

## Backend com sementes fixas: o elenco gerado é sempre o mesmo entre execuções.
class FixedSeedBackend extends MemoryBackend:
	var next_seed := 12345

	func new_seed() -> int:
		next_seed += 7919
		return next_seed


var _actions := {}      # ação -> quantas vezes aconteceu
var _own_goals := {}    # ação -> gols contra que ela causou
var _goals := 0
var _own_goal_total := 0


func _init() -> void:
	var args := {"mode": "gerado_fraco", "matches": "32", "minutes": "90", "target": "34", "seed": "5000",
		"ruleset": "res://rulesets/dev.json", "set": ""}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var rs := Ruleset.load_file(args.ruleset)
	var overrides := preload("res://tests/balance.gd")._parse_set(str(args.set))
	if not overrides.is_empty():
		rs.core["tuning"] = Ruleset.deep_merge(rs.core.get("tuning", {}), overrides)
	var reg := MechanicRegistry.new()
	reg.discover()
	reg.apply_ruleset(rs)

	var lb := LocalBackend.new()
	var target := float(args.target)
	var home: TeamSetup
	var away_snap: Dictionary
	var store: GameStore = null
	match str(args.mode):
		"gerado_fraco", "gerado_demo":
			var backend := FixedSeedBackend.new()
			var world := World.new()
			world.date = "2026-10-10"
			var res := OnboardingService.create_club(world, {"name": "Teste FC", "sigla": "TFC"}, reg, backend)
			if not bool(res.get("ok", false)):
				push_error("não foi possível criar o clube: %s" % str(res))
				quit(1)
				return
			store = GameStore.new()
			store.bind(backend, reg)
			store.reload()
			home = store.team_setup()
			var crit := {"club_file": DemoData.AWAY_CLUB}
			if args.mode == "gerado_fraco":
				crit["target_ovr"] = target
			away_snap = lb.fetch_opponent_snapshot(crit)
		"demo":
			home = DemoData.team_setup(DemoData.HOME_CLUB)
			away_snap = lb.fetch_opponent_snapshot({"club_file": DemoData.AWAY_CLUB})
		"demo_fraco":
			home = DemoData.team_setup_from_dict(lb.fetch_opponent_snapshot({"club_file": DemoData.HOME_CLUB, "target_ovr": target}))
			away_snap = lb.fetch_opponent_snapshot({"club_file": DemoData.AWAY_CLUB, "target_ovr": target})
		_:
			push_error("modo desconhecido: %s" % args.mode)
			quit(1)
			return

	var n := int(args.matches)
	for i in n:
		var s := MatchSetup.new()
		s.rng_seed = int(args.seed) + i
		s.match_minutes = float(args.minutes)
		s.date = "2026-10-10"
		s.home = home
		s.away = DemoData.team_setup_from_dict(away_snap)
		var e := MatchEngine.create(s, reg)
		_play(e)
		e.dispose()

	print("\n%s | ruleset %s | OVR mandante %.1f × visitante %.1f | %d partidas" % [args.mode, reg.ruleset.id,
		_ovr(home), LocalBackend._lineup_mean(away_snap), n])
	print("%d gols, %d contra (%.2f por partida, %.0f%% dos gols)" % [_goals, _own_goal_total,
		_own_goal_total / float(n), 100.0 * _own_goal_total / maxf(_goals, 1.0)])
	print("%-30s %12s %16s" % ["ação (papel:ação:zona)", "gols contra", "ações/partida"])
	var keys := _own_goals.keys()
	keys.sort_custom(func(x, y): return _own_goals[x] > _own_goals[y])
	for k in keys:
		print("%-30s %12d %16.1f" % [k, _own_goals[k], _actions.get(k, 0) / float(n)])
	if store:
		store.free()
	reg.dispose()
	quit()


## Roda a partida tick a tick; a cada toque que solta a bola, guarda a ação. Num gol contra, a
## última ação guardada é a causa.
func _play(e: MatchEngine) -> void:
	var ctx := e.ctx
	var ball := ctx.ball
	var last := ""
	var seen := 0
	while not ctx.finished:
		var msg_before := ctx.message
		var holder_before := ball.holder
		var kicker_before := ball.last_kicker
		e.step()
		for i in range(seen, ctx.events.size()):
			var ev: Dictionary = ctx.events[i]
			if ev.type != "goal":
				continue
			_goals += 1
			if bool(ev.data.get("own_goal", false)):
				_own_goal_total += 1
				_own_goals[last] = int(_own_goals.get(last, 0)) + 1
		seen = ctx.events.size()
		if not ctx.restart.is_empty() or ball.holder != null or ball.last_kicker == null:
			continue
		if holder_before != null or ball.last_kicker != kicker_before:
			var p: MatchPlayer = ball.last_kicker
			var zone := "area" if absf(p.pos.x - p.team.own_goal_x()) < Pitch.PENALTY_BOX_W else "fora"
			last = "%s:%s:%s" % [p.role, _action(ctx, msg_before, p), zone]
			_actions[last] = int(_actions.get(last, 0)) + 1


func _action(ctx: MatchContext, msg_before: String, p: MatchPlayer) -> String:
	var ball := ctx.ball
	var m := ctx.message
	if ball.loose and m == msg_before:
		return "dominio_errado"
	if ball.is_shot:
		return "chute"
	if m.begins_with("Chute bloqueado"):
		return "bloqueio"
	if m.contains("espalma"):
		return "espalmada"
	if m.contains("corta de cabeça") or m.contains("afasta o cruzamento"):
		return "corte_cruzamento"
	if m.begins_with("Corte de"):
		return "desarme_afasta"
	if m.begins_with("Cruzamento"):
		return "cruzamento"
	if m.begins_with("Saída de bola") or m.contains("repõe"):
		return "reposicao_goleiro"
	if m.begins_with("Passe"):
		var to: MatchPlayer = ball.intended
		if to != null and to.is_gk():
			return "recuo_goleiro"
		if to != null and (to.pos.x - p.pos.x) * p.team.dir < 0.0:
			return "passe_para_tras"
		return "passe"
	return "outro"


func _ovr(ts: TeamSetup) -> float:
	var total := 0.0
	for a: Athlete in ts.lineup:
		total += GameStore.overall(a)
	return total / maxf(ts.lineup.size(), 1.0)
