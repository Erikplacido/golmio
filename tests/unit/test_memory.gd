extends TestCase
## O servidor vai simular milhares de partidas: nenhuma pode deixar objetos presos na memória.


func _objects() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))


func test_partida_descartada_libera_memoria() -> void:
	var reg := Fixtures.registry()
	_run_and_dispose(reg)  # aquecimento: carrega scripts e caches estáticos
	var before := _objects()
	for i in 3:
		_run_and_dispose(reg)
	check_eq(_objects(), before, "objetos vivos após 3 partidas descartadas")
	reg.dispose()


func test_registro_descartado_libera_mecanicas() -> void:
	var before := _objects()
	var reg := Fixtures.registry()
	reg.dispose()
	reg = null
	check_eq(_objects(), before, "objetos vivos após descartar o registro")


func _run_and_dispose(reg: MechanicRegistry) -> void:
	var e := Fixtures.engine(reg, 5, 2.0, true)
	e.run_to_end()
	e.dispose()
