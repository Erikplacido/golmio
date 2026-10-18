extends TestCase


func test_pipe_respeita_prioridade_e_dono() -> void:
	var bus := HookBus.new()
	var calls: Array = []
	bus.on("x", func(v, _p): calls.append("b0"); return v + "b", "b", 0)
	bus.on("x", func(v, _p): calls.append("a0"); return v + "a", "a", 0)
	bus.on("x", func(v, _p): calls.append("z-5"); return v + "z", "z", -5)
	check_eq(bus.pipe("x", ""), "zab", "ordem prioridade -> dono")
	check_eq(calls, ["z-5", "a0", "b0"])


func test_decide_primeiro_nao_nulo_vence() -> void:
	var bus := HookBus.new()
	bus.on("d", func(_p): return null, "a")
	bus.on("d", func(_p): return "b", "b")
	bus.on("d", func(_p): return "c", "c")
	check_eq(bus.decide("d"), "b")
	check_eq(bus.decide("sem_handlers"), null)


func test_emit_sem_handlers_nao_falha() -> void:
	var bus := HookBus.new()
	bus.emit("nada", {})
	check(not bus.has_handlers("nada"))
