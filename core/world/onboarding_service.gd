class_name OnboardingService
extends RefCounted
## Serviço de Onboarding e Criação Inicial de Clube.
## Garante a integridade da fundação do clube, a concessão dos 11 atletas iniciais
## e a configuração tática padrão inicial (GDD 5.3, 5.4).

const POSITIONS_11 := ["GK", "DEF", "DEF", "DEF", "DEF", "MID", "MID", "MID", "FWD", "FWD", "FWD"]
## Ids do elenco de emergência (sem packs nem athlete_generator ligados): sem rosto, nome de posição.
const PLACEHOLDER_PREFIX := "ath_init_"
const HOOK_GENERATE := "athlete_generator.generate"
const HOOK_REGISTER := "athlete_generator.register"


## Cria e inicializa um novo clube no World com 11 atletas garantidos e tática inicial.
static func create_club(world: World, club_data: Dictionary, registry: MechanicRegistry, backend: Backend) -> Dictionary:
	var name: String = str(club_data.get("name", "Meu Clube FC")).strip_edges()
	var sigla: String = str(club_data.get("sigla", "MCF")).strip_edges().to_upper()
	var valid := ClubValidation.validate(name, sigla)
	if not bool(valid["ok"]):
		return {"ok": false, "errors": valid["errors"]}
	name = valid["name"]
	sigla = valid["sigla"]

	var club_id := "club_" + str(abs(name.hash()))
	var club := Club.new()
	club.id = club_id
	club.name = name
	club.short_name = sigla

	var identity: Dictionary = club_data.get("club_identity", {})
	var kit: Dictionary = identity.get("kit", {})
	var colors_arr: Array = kit.get("colors", [])
	if colors_arr.size() >= 2:
		club.colors["primary"] = str(colors_arr[0])
		club.colors["secondary"] = str(colors_arr[1])
	club.ext["club_identity"] = identity.duplicate(true)

	world.add_club(club)

	# 11 atletas garantidos no início
	var athletes := _grant_11_initial_athletes(world, club, registry, backend)

	# Tática padrão inicial (4-3-3 com os 11 titulares)
	_setup_initial_tactics(club, athletes)

	# Persistir no backend
	backend.save_world(world.to_dict())

	return {
		"ok": true,
		"club": club,
		"athletes": athletes,
	}


## Concede 11 atletas ao clube (1 GK, 4 DEF, 3 MID, 3 FWD) usando packs, generator ou fallback.
static func _grant_11_initial_athletes(world: World, club: Club, registry: MechanicRegistry, backend: Backend) -> Array[Athlete]:
	var granted_athletes: Array[Athlete] = []
	var seed := backend.new_seed()

	# 1. Tentar via packs.grant_starter
	if registry.bus.has_handlers("packs.grant_starter"):
		var pack_res: Variant = registry.bus.decide("packs.grant_starter", {
			"world": world,
			"club": club,
			"seed": seed,
		})
		if pack_res is Dictionary and bool(pack_res.get("ok", false)):
			var raw_list: Array = pack_res.get("athletes", [])
			for a in raw_list:
				if a is Athlete:
					granted_athletes.append(a)
			if granted_athletes.size() == 11:
				return granted_athletes

	# 2. Tentar via athlete_generator.generate diretamente
	if registry.bus.has_handlers("athlete_generator.generate"):
		var tiers: Array = ["prata", "prata", "bronze", "bronze", "bronze", "bronze", "bronze", "bronze", "bronze", "bronze", "bronze"]
		var gen_res: Variant = registry.bus.decide("athlete_generator.generate", {
			"world": world,
			"count": 11,
			"seed": seed,
			"tiers": tiers,
			"positions": POSITIONS_11,
			"origin": {"source": "onboarding", "club_id": club.id, "date": world.date},
			"unique": true,
			"commit": true,
		})
		if gen_res is Dictionary and bool(gen_res.get("ok", false)):
			var raw_list: Array = gen_res.get("athletes", [])
			for a in raw_list:
				if a is Athlete:
					club.athlete_ids.append(a.id)
					a.club_history.append({"club_id": club.id, "from": world.date, "to": "", "via": "onboarding"})
					granted_athletes.append(a)
			if granted_athletes.size() == 11:
				return granted_athletes

	# 3. Fallback determinístico garantido caso nenhuma mecânica de meta esteja ligada
	var fallback_names := [
		"Goleiro Titular", "Zagueiro Central", "Zagueiro Direito", "Lateral Esquerdo", "Lateral Direito",
		"Volante", "Meia Armador", "Meia Ofensivo", "Ponta Esquerda", "Ponta Direita", "Centroavante"
	]
	for i in 11:
		var pos: String = POSITIONS_11[i]
		var a := Athlete.new()
		a.id = "ath_init_%s_%d" % [club.id, i + 1]
		a.name = fallback_names[i]
		a.position = pos
		a.nationality = "BR"
		a.attributes = {
			"pace": 55, "physical": 55, "passing": 55, "finishing": 55,
			"tackling": 55, "positioning": 55, "reflexes": 55, "elasticity": 55, "stamina": 75
		}
		if pos == "GK":
			a.attributes["reflexes"] = 65
			a.attributes["positioning"] = 62
			a.attributes["elasticity"] = 60
		elif pos == "DEF":
			a.attributes["tackling"] = 62
			a.attributes["physical"] = 60
		elif pos == "MID":
			a.attributes["passing"] = 64
			a.attributes["positioning"] = 58
		elif pos == "FWD":
			a.attributes["finishing"] = 65
			a.attributes["pace"] = 62

		a.club_history.append({"club_id": club.id, "from": world.date, "to": "", "via": "onboarding"})
		world.add_athlete(a)
		club.athlete_ids.append(a.id)
		granted_athletes.append(a)

	return granted_athletes


## Saves feitos sem o gerador ligado têm o elenco de emergência: sem rosto e com nome de posição
## ("Lateral Esquerdo"). Com o gerador ligado, cada um desses atletas ganha identidade gerada (rosto,
## nome, nacionalidade, atributos e DNA, registrados para a unicidade) e mantém id, posição, clube,
## histórico e lugar na escalação. Devolve quantos foram consertados (0 = nada a fazer).
static func repair_placeholder_athletes(world: World, registry: MechanicRegistry, backend: Backend) -> int:
	if world == null or registry == null or not registry.bus.has_handlers(HOOK_GENERATE):
		return 0
	var targets: Array[Athlete] = []
	for a: Athlete in world.athletes.values():
		var face: Variant = a.dna.get("face")
		if a.id.begins_with(PLACEHOLDER_PREFIX) and not (face is Dictionary and not (face as Dictionary).is_empty()):
			targets.append(a)
	if targets.is_empty():
		return 0
	var positions: Array = []
	var tiers: Array = []
	for a in targets:
		positions.append(a.position)
		tiers.append("bronze")
	var res: Variant = registry.bus.decide(HOOK_GENERATE, {
		"world": world, "seed": backend.new_seed() if backend else 1, "count": targets.size(),
		"tiers": tiers, "positions": positions, "origin": {"source": "onboarding_repair", "date": world.date},
		"unique": true, "commit": false,
	})
	if not (res is Dictionary and bool(res.get("ok", false))):
		push_warning("OnboardingService: não deu para gerar os atletas do elenco de emergência: %s" % str(res))
		return 0
	var made: Array = res.get("athletes", [])
	if made.size() != targets.size():
		return 0
	for i in targets.size():
		var t := targets[i]
		var g: Athlete = made[i]
		t.name = g.name
		t.nationality = g.nationality
		t.attributes = g.attributes.duplicate()
		t.dna = g.dna.duplicate(true)
	if registry.bus.has_handlers(HOOK_REGISTER):
		registry.bus.decide(HOOK_REGISTER, {"world": world, "athletes": targets})
	return targets.size()


## Configura a tática padrão 4-3-3 com os 11 atletas posicionados nas suas funções ideais.
static func _setup_initial_tactics(club: Club, athletes: Array[Athlete]) -> void:
	var starting_11: Array[String] = []
	var gks: Array[String] = []
	var defs: Array[String] = []
	var mids: Array[String] = []
	var fwds: Array[String] = []

	for a in athletes:
		match a.position:
			"GK": gks.append(a.id)
			"DEF": defs.append(a.id)
			"MID": mids.append(a.id)
			"FWD": fwds.append(a.id)
			_: mids.append(a.id)

	# 1 GK
	if not gks.is_empty(): starting_11.append(gks[0])
	# 4 DEF
	for i in range(mini(4, defs.size())): starting_11.append(defs[i])
	# 3 MID
	for i in range(mini(3, mids.size())): starting_11.append(mids[i])
	# 3 FWD
	for i in range(mini(3, fwds.size())): starting_11.append(fwds[i])

	# Se faltou preencher 11, completa com os que sobraram
	if starting_11.size() < 11:
		for a in athletes:
			if not starting_11.has(a.id):
				starting_11.append(a.id)
			if starting_11.size() == 11:
				break

	var captain := starting_11[1] if starting_11.size() > 1 else (starting_11[0] if not starting_11.is_empty() else "")
	var penalty := starting_11[10] if starting_11.size() > 10 else captain
	var freekick := starting_11[6] if starting_11.size() > 6 else captain

	club.ext["tactics"] = {
		"formation": "4-3-3",
		"mentality": "equilibrado",
		"defensive_line": "media",
		"passing_style": "misto",
		"captain_id": captain,
		"penalty_taker_id": penalty,
		"freekick_taker_id": freekick,
		"corner_taker_id": freekick,
		"starting_11": starting_11,
		"bench": [],
	}
