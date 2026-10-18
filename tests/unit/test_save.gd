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


func test_salvamento_atomico_e_recuperacao_backup() -> void:
	var backend := LocalBackend.new()
	backend.save_dir = "user://test_save_atomic_" + str(Time.get_ticks_usec())
	var test_data := {"clube": "Teste FC", "versao": 1}
	
	# Primeiro save: cria world.json sem .tmp residual
	var ok := backend.save_world(test_data)
	check(ok, "primeiro save deve ter sucesso")
	check(FileAccess.file_exists(backend.world_path()), "world.json existe")
	check(not FileAccess.file_exists(backend.tmp_path()), "sem .tmp residual")
	
	# Segundo save: cria backup do anterior
	var test_data2 := {"clube": "Teste FC", "versao": 2}
	ok = backend.save_world(test_data2)
	check(ok, "segundo save deve ter sucesso")
	check(FileAccess.file_exists(backend.bak_path()), "world.json.bak criado no segundo save")
	
	# Simula corrupção do arquivo principal (world.json truncado com string inválida)
	var f := FileAccess.open(backend.world_path(), FileAccess.WRITE)
	f.store_string("{corrompido")
	f.close()
	
	# load_world() deve recuperar a partir do backup .bak
	var recovered := backend.load_world()
	check_eq(int(recovered.get("versao", 0)), 1, "recuperou versao 1 do backup")
	
	# Limpeza da pasta de teste
	DirAccess.remove_absolute(backend.world_path())
	DirAccess.remove_absolute(backend.bak_path())
	if FileAccess.file_exists(backend.tmp_path()):
		DirAccess.remove_absolute(backend.tmp_path())
	DirAccess.remove_absolute(backend.save_dir)
