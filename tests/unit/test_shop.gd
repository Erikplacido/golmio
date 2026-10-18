extends TestCase
## Teste unitário para a Loja Cosmética e Sinks de Moeda (TASK-07).
## Valida compra, dedução de créditos, bloqueio por saldo insuficiente, equipar e persistência.


func _store() -> GameStore:
	var backend := MemoryBackend.new()
	var reg := Fixtures.registry("res://rulesets/dev.json")
	var world := World.new()
	world.date = "2026-10-10"
	OnboardingService.create_club(world, {"name": "Galo da Colina", "sigla": "GAL"}, reg, backend)
	var g := GameStore.new()
	g.bind(backend, reg)
	g.reload()
	return g


func test_loja_compra_deduz_creditos_e_persiste() -> void:
	var g := _store()
	check_eq(g.credits(), 250, "saldo inicial padrao de 250 creditos")

	# Compra item de 100 créditos
	var item_id := "disco_vinil"
	check(not g.is_cosmetic_unlocked(item_id), "item ainda nao desbloqueado")
	var bought := g.buy_cosmetic(item_id, 100)
	check(bought, "compra bem sucedida")
	check_eq(g.credits(), 150, "deduziu exatamente 100 creditos")
	check(g.is_cosmetic_unlocked(item_id), "item agora esta desbloqueado")

	# Equipa item
	var equipped := g.equip_cosmetic("button", item_id)
	check(equipped, "item equipado com sucesso")
	check_eq(g.active_cosmetic("button"), item_id, "item ativo e o disco_vinil")

	# Simula reload do backend para verificar persistência
	g.reload()
	check_eq(g.credits(), 150, "saldo persistido apos reload")
	check(g.is_cosmetic_unlocked(item_id), "desbloqueio persistido")
	check_eq(g.active_cosmetic("button"), item_id, "item equipado persistido")

	g.registry.dispose()
	g.free()


func test_loja_bloqueia_quando_saldo_insuficiente() -> void:
	var g := _store()
	# Gasta créditos até sobrar menos que o preço
	g.spend_credits(200)
	check_eq(g.credits(), 50, "saldo reduzido para 50")

	var item_id := "rede_ouro" # Custa 150
	check(not g.can_afford(150), "can_afford retorna false")
	var bought := g.buy_cosmetic(item_id, 150)
	check(not bought, "compra recusada por saldo insuficiente")
	check_eq(g.credits(), 50, "saldo permanece intacto")
	check(not g.is_cosmetic_unlocked(item_id), "item permanece bloqueado")

	g.registry.dispose()
	g.free()


func test_tela_da_loja_monta_pronta() -> void:
	var g := _store()
	var scene := load("res://presentation/shop/shop_screen.tscn") as PackedScene
	var screen: ShopScreen = scene.instantiate()
	screen.store = g
	screen.setup("shop", {})
	screen._ready()
	check_eq(screen.state, ScreenBase.State.READY, "loja monta em estado READY")
	var buy_btn = screen.find_child("Buy_disco_vinil", true, false)
	check(buy_btn != null, "botao de compra do item visivel na tela")
	screen.free()
	g.registry.dispose()
	g.free()
