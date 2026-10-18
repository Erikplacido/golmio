class_name MatchTuning
extends RefCounted
## Números de calibração do NÚCLEO da partida. Ficam aqui (e não espalhados no código) para que
## o balanceamento seja feito por DADOS: sobrescreva no ruleset em "core": {"tuning": {...}}.
## Mudou um número? A assinatura do ruleset muda junto (replays sabem qual calibração usaram).
## Calibração de referência: tests/balance.sh contra as médias reais por time em 90 min
## (Opta/FBref, ligas de elite). Recalibrado em 2026-10-09 (motor v3) com 384 partidas: todas as 9
## métricas na faixa (gols 1,50 · chutes 11,6 · no alvo 4,0 · bloqueados 3,1 · passes 481 ·
## acerto 80% · desarmes 19 · defesas 3,2 · escanteios 4,3 por time). No v3 o goleiro deixou de
## falhar em recuos; cross_clear_out e block_out_share subiram para repor os escanteios que essas
## falhas davam ao adversário (base v2 nas mesmas 384 partidas: gols 1,51 · escanteios 4,24).

const DEFAULTS := {
	# --- finalização ---------------------------------------------------------------------
	"shot_range_attacker": 245.0,     # px até o gol (≈ 9 px por metro)
	"shot_range_other": 205.0,
	"shot_close_dist": 115.0,
	"shot_prob_close": 0.34,          # chance por tick de decidir chutar (perto)
	"shot_prob_far": 0.16,            # (longe)
	"shot_attacker_mult": 1.25,
	"shot_other_mult": 0.9,
	"shot_spread_base": 250.0,        # dispersão do chute (px no gol) para finalização 0
	"shot_spread_skill": 90.0,        # quanto a Finalização 100 reduz a dispersão
	"shot_spread_per_px": 0.0012,        # dispersão extra por px de distância
	"shot_power_base": 10.2,
	"shot_power_skill": 4.2,
	"shot_power_random": 2.0,
	"shot_angle_power": 2.0,          # vontade de chutar *= (cosseno do ângulo ao gol)^isto; 0 = ignora ângulo
	"team_shot_cooldown": 35,         # ticks entre chutes do mesmo time
	"shooter_cooldown": 180,
	# --- bloqueio de chute por defensores -------------------------------------------------------
	"block_chance_base": 0.42,
	"block_chance_skill": 0.3,        # + Desarme/100 * isto
	"block_reach": 16.0,               # px além dos raios (alcance da perna)
	"block_out_share": 0.9,            # bloqueios que desviam para a linha de fundo (escanteio)
	"block_cooldown": 14,              # ticks em que ninguém domina a bola desviada
	"block_speed_keep_min": 0.3,
	"block_speed_keep_max": 0.6,
	# --- linha defensiva --------------------------------------------------------------------
	"def_box_drop": true,            # zaga recua para dentro da área quando a bola se aproxima
	"def_drop_margin": 30.0,          # px entre a bola e a linha (a zaga fica do lado do gol)
	"def_min_line": 70.0,             # px mínimos da própria linha de fundo
	# --- goleiro ---------------------------------------------------------------------------
	"save_far": 0.82,                 # chute de longe (> 140 px)
	"save_mid": 0.74,                 # 90..140 px
	"save_close": 0.66,
	"save_quality_base": 0.65,
	"save_quality_weight": 0.42,
	"hold_base": 0.10,
	"hold_skill": 0.40,
	"parry_out_share": 0.9,           # espalmadas que vão para fora (escanteio)
	"gk_receives_pass": true,         # vai ao encontro do passe de um companheiro (recuo), como o receptor de linha
	"gk_covers_own_goal": true,       # bola do próprio time indo para dentro do gol (recuo torto, domínio ruim): entra na trajetória
	"gk_recovers_fumble": true,       # pode retomar a bola que ele mesmo dominou mal
	# --- passe -----------------------------------------------------------------------------
	"pass_clearance_base": 6.0,      # folga mínima (px) da linha de passe para o adversário
	"pass_clearance_skill": 5.0,
	"pass_clearance_floor": 4.0,
	"pass_receiver_free": 6.0,       # adversário mais perto do receptor que isto = passe vetado
	"pass_spread": 0.012,             # rad de erro por ponto de Passe abaixo de 100
	"pass_lead": 0.30,
	"through_lead": 0.70,
	"receiver_runs_to_ball": true,   # receptor ataca a bola (ponto de encontro)
	"receiver_max_lookahead": 25.0,   # ticks de antecipação do ponto de encontro
	# --- cruzamento ------------------------------------------------------------------------
	"cross_prob": 0.2,                # chance por tick de cruzar quando aberto perto da linha de fundo
	"cross_zone": 340.0,              # px da linha de fundo adversária
	"cross_min_width": 90.0,         # px do eixo central para ser considerado "aberto"
	"cross_speed_min": 8.5,
	"cross_speed_max": 11.0,
	"cross_cooldown": 10,             # ticks em que ninguém domina o cruzamento
	"cross_clear_out": 0.7,          # cortes de cabeça da zaga que vão para escanteio
	"cross_first_time_shot": 0.75,     # atacante que recebe o cruzamento finaliza de primeira
	"wide_keep_width": true,
	"wide_mid_push": 80.0,             # px extras que meias abertos sobem quando o time tem a bola         # jogador aberto conduz pela ponta em vez de cortar para o meio
	# --- domínio (primeiro toque) -----------------------------------------------------------
	"miscontrol_base": 0.10,           # chance de dominar mal um passe
	"miscontrol_pressure": 0.12,       # + isto se houver adversário a menos de 42 px
	"miscontrol_speed": 0.05,          # + isto * (velocidade da bola / 10)
	"miscontrol_skill": 0.08,          # - Passe/100 * isto
	# --- desarme ---------------------------------------------------------------------------
	"tackle_rate": 0.28,
	"tackle_mult_settled": 1.3,       # portador com a bola há mais de 6 ticks
	"tackle_mult_fresh": 0.4,
	"tackle_cooldown": 90,
	"interception_stat_chance": 0.22,
	# --- bola ------------------------------------------------------------------------------
	"ball_friction": 0.982,
	# --- valores-base dos knobs táticos (MatchTeam.DEFAULT_KNOBS); mentalidade etc. ajustam por cima
	"knobs": {},
}


static func resolve(ruleset: Ruleset) -> Dictionary:
	var over: Dictionary = ruleset.core.get("tuning", {}) if ruleset else {}
	for k in over:
		if not DEFAULTS.has(k):
			push_warning("Tuning desconhecido '%s' no ruleset (ignorado)." % k)
	return Ruleset.deep_merge(DEFAULTS, over)
