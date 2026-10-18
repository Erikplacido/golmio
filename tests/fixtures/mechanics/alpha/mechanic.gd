extends Mechanic

func _init() -> void:
	id = "alpha"
	enabled_by_default = true
	default_params = {"level": 1, "nested": {"a": 1, "b": 2}}
	provides_hooks = {"alpha.value": "pipe int ; teste"}


func install(bus: HookBus) -> void:
	bus.on("alpha.value", func(v, _p): return v + int(param("level")), id)
