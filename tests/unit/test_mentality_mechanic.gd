extends TestCase
## Testes unitários para a Matriz Intransitiva de Mentalidades (TASK-06).
## Valida que a dinâmica Pedra-Papel-Tesoura entre:
##   1. Pressão Alta (High Press) > Posse / Retranca (Compact Possession)
##   2. Contra-Ataque Direto (Direct Counter) > Pressão Alta (High Press)
##   3. Posse / Retranca (Compact Possession) > Contra-Ataque Direto (Direct Counter)
## opera com determinismo através dos hooks TEAM_KNOBS, TACKLE_ATTEMPT e PLAYER_ATTRIBUTES.


func _create_match_engine(home_mentality: String, away_mentality: String) -> MatchEngine:
	var reg := Fixtures.registry("res://rulesets/dev.json")
	var setup := DemoData.match_setup(42, 5.0)
	setup.home.tactics = {"mentality": home_mentality}
	setup.away.tactics = {"mentality": away_mentality}
	return MatchEngine.create(setup, reg)


func test_high_press_supera_posse_compacta() -> void:
	# High Press (pressao_total) vs Compact/Possession (retranca)
	var engine := _create_match_engine("pressao_total", "retranca")
	var ctx := engine.ctx

	# 1. Knobs: High press ganha press_radius ampliado e press_count = 2
	var home_knobs: Dictionary = ctx.home.knobs
	check(float(home_knobs.get("press_radius", 0.0)) >= 290.0, "raio de pressao ampliado contra posse")
	check_eq(int(home_knobs.get("press_count", 1)), 2, "2 jogadores na pressao contra posse")

	# 2. Tackle: High press ganha bônus no campo do adversário
	var tackler: MatchPlayer = ctx.home.players[ctx.home.players.size() - 1]
	var holder: MatchPlayer = ctx.away.players[1]
	holder.pos = Vector2(Pitch.W * 0.8, Pitch.H * 0.5) if ctx.away.dir == -1 else Vector2(Pitch.W * 0.2, Pitch.H * 0.5)
	var tackle_data := {"chance": 0.5, "handled": false}
	var res: Dictionary = ctx.bus.pipe(Hooks.TACKLE_ATTEMPT, tackle_data, {"ctx": ctx, "tackler": tackler, "holder": holder})
	check(float(res.chance) > 0.5, "bonus de desarme no campo adversario")

	engine.dispose()


func test_direct_counter_supera_high_press() -> void:
	# Direct/Counter (ofensivo) vs High Press (pressao_total)
	var engine := _create_match_engine("ofensivo", "pressao_total")
	var ctx := engine.ctx

	# 1. Knobs: Direct counter ganha aumento em pass_risk e alcance de finalizacao
	var home_knobs: Dictionary = ctx.home.knobs
	check(float(home_knobs.get("pass_risk", 0.0)) >= 0.5, "risco de passe vertical aumentado")
	check(float(home_knobs.get("shot_range_mult", 1.0)) > 1.2, "alcance de chute ampliado")

	# 2. Attributes: Atacante do Direct Counter ganha bonus de pace e passing
	var fwd: MatchPlayer = null
	for p: MatchPlayer in ctx.home.players:
		if p.role == "FWD":
			fwd = p
			break
	if fwd != null:
		var base_attrs := {"pace": 50.0, "passing": 50.0}
		var boosted: Dictionary = ctx.bus.pipe(Hooks.PLAYER_ATTRIBUTES, base_attrs, {"ctx": ctx, "player": fwd})
		check(float(boosted.pace) > 50.0, "pace de atacante aumentado contra linha alta")
		check(float(boosted.passing) > 50.0, "passing de atacante aumentado contra linha alta")

	engine.dispose()


func test_compact_possession_supera_direct_counter() -> void:
	# Compact/Possession (retranca) vs Direct/Counter (ofensivo)
	var engine := _create_match_engine("retranca", "ofensivo")
	var ctx := engine.ctx

	# 1. Knobs: Linha defensiva recua ainda mais para negar profundidade
	var home_knobs: Dictionary = ctx.home.knobs
	check(float(home_knobs.get("line_height", 0.0)) <= -55.0, "bloco recuado contra bolas longas")
	check(int(home_knobs.get("tempo_frames", 16)) >= 22, "tempo de posse cadenciado")

	# 2. Attributes: Zagueiros ganham bonus de tackling e physical para neutralizar bolas diretas
	var defender: MatchPlayer = null
	for p: MatchPlayer in ctx.home.players:
		if p.role == "DEF":
			defender = p
			break
	if defender != null:
		var base_attrs := {"tackling": 60.0, "physical": 60.0}
		var boosted: Dictionary = ctx.bus.pipe(Hooks.PLAYER_ATTRIBUTES, base_attrs, {"ctx": ctx, "player": defender})
		check(float(boosted.tackling) > 60.0, "tackling de zagueiro aumentado contra ataque direto")
		check(float(boosted.physical) > 60.0, "fisico de zagueiro aumentado contra ataque direto")

	engine.dispose()


func test_equilibrado_neutro_sem_modificadores() -> void:
	# Equilibrado vs Equilibrado: nenhum efeito intransitivo ativado
	var engine := _create_match_engine("equilibrado", "equilibrado")
	var ctx := engine.ctx
	var home_knobs: Dictionary = ctx.home.knobs
	check_eq(int(home_knobs.get("press_count", 1)), 1, "press_count padrao")
	check_eq(float(home_knobs.get("line_height", 0.0)), 0.0, "line_height neutro")
	engine.dispose()

