class_name Backend
extends RefCounted
## Interface do servidor. O jogo só fala com esta classe; trocar LocalBackend por um backend
## real (Nakama, Supabase, próprio...) não mexe em mecânicas nem no motor.
## Implementações remotas serão assíncronas: chame sempre com `await`.

## Ruleset ativo (remote config). Formato: ver Ruleset.
func fetch_ruleset() -> Dictionary:
	return _not_implemented("fetch_ruleset", {})


func load_world() -> Dictionary:
	return _not_implemented("load_world", {})


func save_world(_data: Dictionary) -> bool:
	return _not_implemented("save_world", false)


## Snapshot defensivo de outro clube, por divisão/Elo (GDD 1). Retorna dados de TeamSetup.
func fetch_opponent_snapshot(_criteria: Dictionary) -> Dictionary:
	return _not_implemented("fetch_opponent_snapshot", {})


## Registra o resultado. No servidor real, partidas oficiais são simuladas/validadas lá.
func submit_match_result(_result: Dictionary) -> Dictionary:
	return _not_implemented("submit_match_result", {})


## Resultados registrados, do mais recente para o mais antigo (no máximo `limit`; 0 = todos).
## `club_id` não vazio filtra as partidas desse clube.
func fetch_match_results(_club_id: String = "", _limit: int = 0) -> Array:
	return _not_implemented("fetch_match_results", [])


## Relógio do servidor: segundos Unix (UTC). A data do jogo e a janela do jogo oficial diário
## saem daqui, nunca do relógio do aparelho (que o jogador pode adiantar).
func server_time() -> int:
	return _not_implemented("server_time", 0)


## Entropia do servidor: semente nova, inteira em [0, 2^48) (AthleteDna.SEED_LIMIT, segura em
## JSON), para pacotes, criação de clube etc. Mecânicas NUNCA criam semente com relógio: quem
## concede recebe a semente daqui e a passa no payload (ex.: packs.grant).
func new_seed() -> int:
	return _not_implemented("new_seed", 0)


func _not_implemented(method: String, fallback: Variant) -> Variant:
	push_error("Backend.%s não implementado em %s" % [method, get_script().resource_path])
	return fallback
