extends TestCase
## Padrões e brasões do clube: grátis desde a criação; os outros só depois de ganhos.


func test_gratis_e_bloqueados() -> void:
	check(Cosmetics.is_unlocked("lisa"), "padrão grátis sem clube")
	check(not Cosmetics.is_unlocked("chevron"), "padrão premium bloqueado na criação")
	check(Cosmetics.is_unlocked(Cosmetics.DEFAULT_CREST), "brasão padrão é grátis")
	check(not Cosmetics.is_unlocked("nao_existe"), "id desconhecido")


func test_desbloqueio_fica_no_clube() -> void:
	var club := Club.new()
	check(not Cosmetics.is_unlocked("losango_estrela", club), "começa bloqueado")
	check(Cosmetics.unlock(club, "losango_estrela"), "desbloqueia")
	check(Cosmetics.is_unlocked("losango_estrela", club), "liberado para o clube")
	check(not Cosmetics.unlock(club, "losango_estrela"), "não desbloqueia duas vezes")
	check(not Cosmetics.locked(club).has("losango_estrela"), "sai da lista de bloqueados")


func test_todo_padrao_tem_formula() -> void:
	for id in Cosmetics.PATTERNS:
		check(UniformMaps.PATTERNS.has(id), "padrão %s existe no shader" % id)
	# Os novos desenham algo além da cor principal.
	for id in ["listras_diagonais", "chevron", "duas_faixas", "losangos"]:
		var kit := {"pattern": id, "count": 3, "width": 0.16}
		var seen := {}
		for i in 20:
			for j in 20:
				seen[UniformMaps.pattern_index(kit, i / 20.0, j / 20.0, 1.2)] = true
		check(seen.has(0) and seen.has(1), "padrão %s usa as duas cores" % id)
