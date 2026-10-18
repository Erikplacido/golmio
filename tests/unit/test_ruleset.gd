extends TestCase


func test_extends_herda_e_sobrescreve() -> void:
	var rs := Ruleset.load_file("res://rulesets/arcade.json")
	check_eq(rs.id, "arcade")
	check(not rs.is_enabled("set_pieces", true), "arcade desliga set_pieces")
	check(rs.is_enabled("mentality", false), "herdado do default")
	check_eq(int(rs.core_param("match_minutes")), 90)


func test_unlisted_off() -> void:
	var rs := Ruleset.load_file("res://rulesets/core_only.json")
	check(not rs.is_enabled("qualquer_mecanica_futura", true))


func test_assinatura_muda_com_params() -> void:
	var a := Fixtures.registry()
	var b := Fixtures.registry_with(["stamina"], {"stamina": {"drain_per_minute": 0.5}})
	var c := Fixtures.registry_with(["stamina"])
	check(a.signature().hash != b.signature().hash)
	check(b.signature().hash != c.signature().hash, "mesmo conjunto, params diferentes => assinatura diferente")


func test_mecanicas_do_projeto_sem_erros() -> void:
	var reg := Fixtures.registry()
	check(reg.errors.is_empty(), "erros: %s" % str(reg.errors))
	check(reg.warnings.is_empty(), "avisos: %s" % str(reg.warnings))
	for mid in reg.available:
		var m: Mechanic = reg.available[mid]
		check(m.version >= 1, "%s sem versão" % mid)
		check(not m.title.is_empty(), "%s sem título" % mid)
		for h in m.provides_hooks:
			check(str(h).begins_with(mid + "."), "hook '%s' deve ter prefixo '%s.'" % [h, mid])
