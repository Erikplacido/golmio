class_name MatchTeam
extends RefCounted
## Time durante uma partida.

## "Botões" táticos que o motor lê. Mecânicas mudam via hook TEAM_KNOBS (ex.: mentalidade, crise).
## Botão novo: adicione aqui com valor neutro (= comportamento atual) e use no motor.
const DEFAULT_KNOBS := {
	"line_height": 0.0,       # px: desloca o bloco inteiro para frente (+) ou para trás (-)
	"press_radius": 180.0,    # distância máxima para sair na pressão
	"press_count": 1,         # quantos jogadores pressionam a bola ao mesmo tempo
	"shot_range_mult": 1.0,   # multiplica o alcance de finalização
	"shot_prob_mult": 1.0,    # multiplica a vontade de finalizar
	"pass_risk": 0.0,         # -1..1: peso extra de passes para frente
	"tempo_frames": 16,       # ticks mínimos com a bola antes de pensar no passe
}

var side: String = "home"
var setup: TeamSetup
var name: String = ""
var color: Color = Color.WHITE
var dir: int = 1                 # +1 ataca para x = W
var players: Array = []          # MatchPlayer em campo
var bench: Array = []            # Athlete ainda disponíveis
var participants: Dictionary = {}  # athlete_id -> true (entrou em campo; GDD 2.1)
var subs_used: int = 0
var knobs: Dictionary = DEFAULT_KNOBS.duplicate()
var stats: Dictionary = {
	"goals": 0, "shots": 0, "shots_on_target": 0, "shots_blocked": 0, "passes_attempted": 0,
	"passes_completed": 0, "tackles": 0, "saves": 0, "corners": 0, "possession_ticks": 0,
}
var ext: Dictionary = {}


func own_goal_x() -> float:
	return 0.0 if dir == 1 else Pitch.W


func opp_goal_x() -> float:
	return Pitch.W if dir == 1 else 0.0


func goalkeeper() -> MatchPlayer:
	for p: MatchPlayer in players:
		if p.is_gk():
			return p
	return null


func ext_for(mechanic_id: String) -> Dictionary:
	if not ext.has(mechanic_id):
		ext[mechanic_id] = {}
	return ext[mechanic_id]
