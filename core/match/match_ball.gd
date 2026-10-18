class_name MatchBall
extends RefCounted

const RADIUS := 4.5
const FRICTION := 0.982

var pos := Vector2.ZERO
var prev_pos := Vector2.ZERO
var vel := Vector2.ZERO
var radius := RADIUS
var friction := FRICTION
var holder: MatchPlayer = null
var intended: MatchPlayer = null      # destinatário do último passe (corre para receber)
var block_tried: Dictionary = {}      # defensores que já tentaram bloquear o chute atual
var loose := false                    # bola espirrada de um domínio errado (não conta como passe)
var cross_team: MatchTeam = null      # time que cruzou a bola em voo (null = não é cruzamento)
var last_kicker: MatchPlayer = null
var pass_cooldown := 0
var is_shot := false
var shot_resolved := false
var shot_on_target := false
var shot_origin := Vector2.ZERO
var team_shot_cooldown := {"home": 0, "away": 0}
