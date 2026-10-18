class_name SeededRng
extends RefCounted
## Gerador aleatório determinístico. TODA aleatoriedade de regras passa por aqui:
## nunca use randf()/randi() globais nem Time/OS em código de simulação.
## Mesma semente + mesmo ruleset => mesma partida, em qualquer plataforma.
## Base: PCG32 do Godot (aritmética inteira pura). Floats são derivados em GDScript (double),
## sem passar por randf()/randf_range() do C++, para não depender do compilador.

const TWO_POW_32 := 4294967296.0

var seed_value: int
var _rng := RandomNumberGenerator.new()


func _init(p_seed: int = 0) -> void:
	seed_value = p_seed
	_rng.seed = p_seed


## Float em [0, 1).
func next_float() -> float:
	return float(_rng.randi()) / TWO_POW_32


func between(a: float, b: float) -> float:
	return a + next_float() * (b - a)


func int_between(a: int, b: int) -> int:
	return _rng.randi_range(a, b)


func chance(p: float) -> bool:
	return next_float() < p


func pick_sign() -> float:
	return 1.0 if next_float() < 0.5 else -1.0


## Cria um fluxo independente (ex.: um por mecânica), para que o consumo de
## números aleatórios de uma mecânica não embaralhe os sorteios de outra.
func fork(salt: String) -> SeededRng:
	return SeededRng.new(("%d:%s" % [seed_value, salt]).hash())
