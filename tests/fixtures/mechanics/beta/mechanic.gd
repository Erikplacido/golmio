extends Mechanic

func _init() -> void:
	id = "beta"
	enabled_by_default = true
	depends_on = ["alpha"]


func install(bus: HookBus) -> void:
	bus.on("alpha.value", func(v, _p): return v * 10, id, 10)
