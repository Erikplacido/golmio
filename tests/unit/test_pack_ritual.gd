extends TestCase
## PackRitual (ritual de abertura GOLMIO): linha do tempo por raridade, momentos e fim emitidos uma
## vez, pular (exato e idempotente), seek sem sinais, repetição e determinismo das partículas.
## Roda fora da árvore: _process é chamado à mão.

const SIZE := Vector2(1100, 720)


func _card(tier: String, id: String = "a1") -> Dictionary:
	return {"kind": "athlete", "athlete_id": id, "tier": tier, "name": "Teste", "position": "FWD",
		"nationality": "Brasil"}


func _ritual(tier: String = "bronze", reduce := false) -> PackRitual:
	var r := PackRitual.new()
	r.size = SIZE
	r.reduce_motion = reduce
	r.play(_card(tier))
	return r


func _run(r: PackRitual, seconds: float, step: float = 1.0 / 60.0) -> void:
	var t := 0.0
	while t < seconds:
		r._process(step)
		t += step


func test_linha_do_tempo_por_raridade() -> void:
	var low := _ritual("bronze")
	var high := _ritual("deus")
	var calm := _ritual("deus", true)
	check_near(low.duration(), 2.9, 0.001, "base de ~3 s")
	check(high.duration() > low.duration(), "raridade alta alonga o ritual")
	check_near(high.moment_start("reveal") - high.moment_start("anticipation"),
		PackRitual.DURATIONS.anticipation + 3 * PackRitual.ANTICIPATION_PER_RANK, 0.001, "antecipação do divino")
	check(calm.duration() < low.duration(), "reduzir movimento encurta")
	var prev := -1.0
	for m in PackRitual.MOMENTS:
		check(high.moment_start(m) >= prev, "momentos em ordem: %s" % m)
		prev = high.moment_start(m)
	check(high._confetti.size() > low._confetti.size(), "mais confete na raridade alta")
	check(calm._confetti.is_empty() and calm._fragments.is_empty(), "sem partículas com movimento reduzido")
	for r in [low, high, calm]:
		r.free()


func test_momentos_e_fim_uma_vez() -> void:
	var r := _ritual("ouro")
	var beats: Array = []
	var ends: Array = []
	r.beat.connect(func(m: String) -> void: beats.append(m))
	r.finished.connect(func(s: bool) -> void: ends.append(s))
	_run(r, r.duration() + 1.0)
	check_eq(beats, PackRitual.MOMENTS, "cada momento uma vez, em ordem")
	check_eq(ends, [false], "terminou sem pular, uma vez")
	check(r.done and not r.skipped)
	check(not r.skip(), "pular depois do fim não faz nada")
	check_eq(ends.size(), 1)
	r.free()


func test_pular_vai_para_a_carta_parada() -> void:
	var r := _ritual("diamante")
	var ends: Array = []
	r.finished.connect(func(s: bool) -> void: ends.append(s))
	_run(r, 0.5)
	check(r.skip(), "pular no meio")
	check(not r.skip(), "pular de novo não emite outra vez")
	check_eq(ends, [true])
	var c := r._card
	var m := r._metrics()
	check_near(c.position.x + c.size.x / 2.0, float(m.card_center.x), 0.01, "carta no centro (x)")
	check_near(c.position.y + c.size.y / 2.0, float(m.card_center.y), 0.01, "carta no centro (y)")
	check_near(c.rotation, 0.0, 0.0001, "de frente")
	check_near(c.scale.x, 1.0, 0.0001, "no tamanho final")
	check_eq(c.z_index, 3, "na frente do pacote")
	check(c.visible and not r._pack.visible, "pacote já saiu")
	_run(r, 1.0)
	check_eq(ends, [true], "seguir rodando não emite de novo")
	r.free()


func test_seek_sem_sinais_e_repetir() -> void:
	var r := _ritual("prata")
	var events: Array = []
	r.beat.connect(func(m: String) -> void: events.append(m))
	r.finished.connect(func(s: bool) -> void: events.append(s))
	r.seek(r.duration() + 1.0)
	check(events.is_empty(), "seek não emite")
	check(not r.done, "seek não conclui")
	_run(r, 0.1)
	check_eq(events, [false], "o próximo quadro depois do fim conclui; momentos já passados não são reemitidos")
	r.play(r.card)
	check(r.playing and not r.done and not r.skipped, "repetir recomeça")
	check_near(r.time(), 0.0, 0.0001)
	check(not r._card.visible and r._front.visible, "pacote lacrado de novo")
	r.free()


func test_mesma_carta_mesmo_ritual() -> void:
	var a := _ritual("deus", false)
	var b := _ritual("deus", false)
	var other := PackRitual.new()
	other.size = SIZE
	other.play(_card("deus", "a2"))
	check_eq(a._confetti.size(), b._confetti.size())
	check_eq(str(a._confetti), str(b._confetti), "confete igual")
	check_eq(str(a._fragments), str(b._fragments), "fragmentos iguais")
	check(str(a._confetti) != str(other._confetti), "outra carta, outro confete")
	for t in [0.3, 1.0, 1.9, 2.4, 3.2]:
		check_eq(a._card_state(t), b._card_state(t), "carta igual em t=%.1f" % t)
		check_eq(a._pack_state(t), b._pack_state(t), "pacote igual em t=%.1f" % t)
	for r in [a, b, other]:
		r.free()


func test_carta_escondida_ate_a_abertura() -> void:
	var r := _ritual("bronze")
	for t in [0.0, 0.4, r.moment_start("tear") + 0.01]:
		check(not bool(r._card_state(t).visible), "carta escondida em t=%.2f" % t)
	var during := r._card_state(r.moment_start("reveal") + 0.05)
	check(during.visible and not during.front, "subindo por dentro do pacote (atrás do corpo)")
	var after := r._card_state(r.moment_start("inspect"))
	check(after.front, "depois de sair, na frente do pacote")
	r.free()
