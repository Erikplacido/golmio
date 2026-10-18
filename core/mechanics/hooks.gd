class_name Hooks
extends RefCounted
## Catálogo oficial de hooks do núcleo. É o CONTRATO entre o núcleo e as mecânicas.
##
## Três formas de hook (ver HookBus):
##   emit   -> notificação; os handlers recebem (payload) e não retornam nada.
##   pipe   -> transformação; handlers recebem (valor, payload) e DEVEM retornar o valor (modificado ou não).
##   decide -> decisão; handlers recebem (payload); o primeiro retorno != null vence.
##
## Regras de evolução (docs/ARQUITETURA.md, seção "Evoluindo o contrato"):
##   - Adicionar hook novo ou chave nova no payload: seguro.
##   - Renomear/remover hook ou mudar o formato de um payload: só com deprecação
##     (mantém o antigo funcionando por pelo menos uma versão de ruleset).
## Mecânicas podem declarar hooks próprios em `provides_hooks` (prefixo "<id_mecanica>.").

# ---------------------------------------------------------------- PARTIDA (ctx.bus)
const MATCH_SETUP := "match.setup"
const MATCH_PERIODIC := "match.periodic"
const MATCH_TICK := "match.tick"
const MATCH_EVENT := "match.event"
const PERIOD_START := "match.period_start"
const PERIOD_END := "match.period_end"
const MATCH_END_DECISION := "match.end_decision"
const MATCH_END := "match.end"
const PLAYER_ATTRIBUTES := "match.player_attributes"
const PLAYER_CONDITION := "match.player_condition"
const TEAM_KNOBS := "match.team_knobs"
const TACKLE_ATTEMPT := "match.tackle_attempt"
const SAVE_ATTEMPT := "match.save_attempt"
const BALL_OUT := "match.ball_out"
const GOAL_SCORED := "match.goal"
const PASS_RELEASED := "match.pass_released"

# ---------------------------------------------------------------- MUNDO (registry.bus)
const MATCH_PLAYED := "world.match_played"
const OFFICIAL_MATCH_PLAYED := "world.official_match_played"
const ATHLETE_AGE := "world.athlete_age"
const ATHLETE_BIRTHDAY := "world.athlete_birthday"
const ATHLETE_RETIRED := "world.athlete_retired"
const LINEUP_VALIDATE := "world.lineup_validate"

## Documentação de cada hook: forma, payload e valor. Fonte única da verdade.
const CATALOG := {
	MATCH_SETUP: "emit {ctx} — partida montada, antes do apito. Inicialize estado em ctx.state_for(id).",
	MATCH_PERIODIC: "emit {ctx, dt} — a cada MatchContext.REFRESH_TICKS (5 s de jogo). Use para lógica contínua barata.",
	MATCH_TICK: "emit {ctx} — a cada tick (0,2 s de jogo). CARO: prefira MATCH_PERIODIC.",
	MATCH_EVENT: "emit {ctx, event} — todo evento registrado na linha do tempo (gol, chute, defesa, reinício...).",
	PERIOD_START: "emit {ctx, period} — início de período (1T, 2T, prorrogação...).",
	PERIOD_END: "emit {ctx, period} — fim de período.",
	MATCH_END_DECISION: "decide {ctx} -> Array de períodos extras [{id, seconds}] para continuar, ou null para encerrar. Pode também resolver pênaltis e gravar em ctx.result_extra.",
	MATCH_END: "emit {ctx, result} — partida encerrada; result é serializável.",
	PLAYER_ATTRIBUTES: "pipe Dictionary {atributo: valor} ; payload {ctx, player} — atributos efetivos (recalculados a cada REFRESH_TICKS).",
	PLAYER_CONDITION: "pipe float 0..1 (energia/condição) ; payload {ctx, player}. Padrão 1.0.",
	TEAM_KNOBS: "pipe Dictionary de botões táticos (MatchTeam.DEFAULT_KNOBS) ; payload {ctx, team}.",
	TACKLE_ATTEMPT: "pipe Dictionary {chance, handled} ; payload {ctx, tackler, holder}. handled=true: a mecânica resolveu o lance (ex.: falta).",
	SAVE_ATTEMPT: "pipe Dictionary {chance, hold_chance} ; payload {ctx, keeper, shooter}.",
	BALL_OUT: "decide {ctx, line('side'|'end'), point, last_team} -> true se a mecânica tratou a saída de bola. Sem handler: a bola rebate (modo arcade).",
	GOAL_SCORED: "emit {ctx, team, scorer, own_goal}.",
	PASS_RELEASED: "emit {ctx, passer, receiver, through} — bola saiu do pé do passador. Receptor ainda não tocou.",
	MATCH_PLAYED: "emit {world, result, date, participants} — qualquer partida concluída (oficial ou não).",
	OFFICIAL_MATCH_PLAYED: "emit {world, result, date, participants} — só partidas do Campeonato Oficial (conta dia de carreira).",
	ATHLETE_AGE: "pipe float idade em anos ; payload {athlete}. Padrão: dna.initial_age ou 17.",
	ATHLETE_BIRTHDAY: "emit {athlete, age}.",
	ATHLETE_RETIRED: "emit {athlete}.",
	LINEUP_VALIDATE: "pipe Array de mensagens de erro ; payload {team_setup}.",
}
