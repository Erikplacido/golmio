extends TestCase

const FIX := "res://tests/fixtures/mechanics"


func _reg(data: Dictionary) -> MechanicRegistry:
	var reg := MechanicRegistry.new()
	reg.discover(FIX)
	reg.apply_ruleset(Ruleset.from_dict(data))
	return reg


func test_descobre_pastas_automaticamente() -> void:
	var reg := _reg({})
	check_eq(reg.available.keys().size(), 3)
	check_eq(reg.enabled_ids(), PackedStringArray(["alpha", "beta"]), "default: alpha e beta ligadas, gamma desligada")


func test_hooks_de_mecanicas_compoem() -> void:
	var reg := _reg({})
	check_eq(reg.bus.pipe("alpha.value", 1), 20, "(1 + 1) * 10")


func test_desligar_dependencia_desliga_dependente() -> void:
	var reg := _reg({"mechanics": {"alpha": {"enabled": false}}})
	check_eq(reg.enabled_ids().size(), 0)
	check(reg.warnings.size() > 0, "deve avisar que beta caiu")
	check_eq(reg.bus.pipe("alpha.value", 1), 1, "hook de mecânica desligada é inofensivo")


func test_conflito_desliga_um_e_registra_erro() -> void:
	var reg := _reg({"mechanics": {"gamma": {"enabled": true}}})
	check(reg.is_enabled("alpha"))
	check(not reg.is_enabled("gamma"))
	check(reg.errors.size() > 0)


func test_params_do_ruleset_sobrescrevem_default() -> void:
	var reg := _reg({"mechanics": {"alpha": {"params": {"level": 5, "nested": {"b": 9}}}}})
	var a := reg.get_mechanic("alpha")
	check_eq(a.params.level, 5)
	check_eq(a.params.nested, {"a": 1, "b": 9}, "merge profundo")
	check_eq(reg.bus.pipe("alpha.value", 1), 60)


func test_mecanica_inexistente_no_ruleset_so_avisa() -> void:
	var reg := _reg({"mechanics": {"fantasma": {"enabled": true}}})
	check(reg.errors.is_empty())
	check(Array(reg.warnings).any(func(w): return "fantasma" in w))


func test_ordem_respeita_dependencias() -> void:
	var reg := _reg({})
	check_eq(reg.enabled[0].id, "alpha")
	check_eq(reg.enabled[1].id, "beta")


func test_experimental_nao_nasce_ligada_e_deprecada_avisa() -> void:
	var reg := MechanicRegistry.new()
	var exp := Mechanic.new()
	exp.id = "nova"
	exp.stage = "experimental"
	exp.enabled_by_default = true
	reg.register(exp)
	var dep := Mechanic.new()
	dep.id = "velha"
	dep.stage = "deprecated"
	dep.enabled_by_default = true
	reg.register(dep)
	reg.apply_ruleset(Ruleset.from_dict({}))
	check(Array(reg.warnings).any(func(w): return "experimental" in w))
	check(Array(reg.warnings).any(func(w): return "deprecada" in w))
