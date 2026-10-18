extends TestCase
## Contrato: cada mecânica precisa funcionar SOZINHA (+ dependências) e JUNTO com todas as outras.
## Uma mecânica nova entra neste teste automaticamente.


func test_cada_mecanica_isolada() -> void:
	var all := Fixtures.registry()
	for mid in all.available:
		var ids: Array = [mid]
		ids.append_array(all.available[mid].depends_on)
		var reg := Fixtures.registry_with(ids)
		check(reg.is_enabled(mid), "%s deveria ligar sozinha" % mid)
		var e := Fixtures.engine(reg, 99, 4.0, true)
		var r := e.run_to_end()
		check(e.is_finished(), "%s: partida não terminou" % mid)
		check(r.home.participants.size() >= 11, "%s: participantes" % mid)


func test_todas_juntas() -> void:
	var reg := Fixtures.registry_with(Fixtures.registry().available.keys())
	var e := Fixtures.engine(reg, 123, 6.0, true)
	var r := e.run_to_end()
	check(e.is_finished())
	check(r.winner != "", "mata-mata sempre tem vencedor")
