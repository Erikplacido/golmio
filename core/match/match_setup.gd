class_name MatchSetup
extends RefCounted
## Tudo o que define uma partida. Mesmo MatchSetup + mesmo ruleset => mesmo resultado.

const KINDS := ["official", "friendly", "cup", "varzea", "national"]

var rng_seed: int = 0
var kind: String = "friendly"   # só "official" conta dia de carreira (GDD 2.1)
var knockout: bool = false      # mata-mata: empate aciona a decisão de fim de jogo
var match_minutes: float = 90.0
var date: String = ""
## Cara ou coroa (decidido antes do apito, faz parte da partida): quem dá a saída no 1º tempo (o
## outro dá no 2º) e para onde o mandante ataca no 1º tempo (1 = direita, -1 = esquerda).
var kickoff_side: String = "home"
var home_dir: int = 1
var home: TeamSetup
var away: TeamSetup
