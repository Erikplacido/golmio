extends TestCase


func test_cansaco_dispara_troca_com_estamina() -> void:
	var reg := Fixtures.registry_with(["stamina", "substitutions"], {"stamina": {"drain_per_minute": 0.2}})
	var r := Fixtures.engine(reg, 8, 10.0).run_to_end()
	check(r.home.participants.size() > 11, "houve substituição no mandante")
	check(r.home.participants.size() <= 16, "no máximo 5 trocas")


func test_sem_estamina_regra_de_cansaco_nao_dispara() -> void:
	var reg := Fixtures.registry_with(["substitutions"])
	var r := Fixtures.engine(reg, 8, 10.0).run_to_end()
	check_eq(r.away.participants.size(), 11, "visitante só tem regra de cansaço")
