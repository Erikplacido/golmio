extends TestCase


func test_ida_e_volta_preserva_dados_de_mecanicas_removidas() -> void:
	var w := DemoData.world()
	var a: Athlete = w.athletes.values()[0]
	a.ext["mecanica_removida"] = {"segredo": 42}
	var data: Dictionary = JSON.parse_string(JSON.stringify(w.to_dict()))
	data = SaveMigrator.migrate(data, Fixtures.registry())
	var w2 := World.from_dict(data)
	var a2: Athlete = w2.athletes[a.id]
	check_eq(int(a2.ext.mecanica_removida.segredo), 42, "dados dormentes preservados")
	check_eq(a2.attributes, a.attributes)
	check(data.mechanic_data_versions.has("career_aging"))


func test_demo_tem_todos_os_atributos_do_catalogo() -> void:
	var w := DemoData.world()
	for aid in w.athletes:
		for k in AttributeCatalog.ids():
			check(w.athletes[aid].attributes.has(k), "%s sem %s" % [aid, k])
