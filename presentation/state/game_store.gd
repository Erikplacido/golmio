class_name GameStore
extends Node
## Autoload "Game": o estado do jogador para as telas. Lê o World do backend, entrega dados prontos
## para exibir (elenco, força do time, status do oficial, histórico) e faz as ações que escrevem
## (salvar tática, preparar e registrar partidas, avançar a estreia). As telas nunca falam com o
## backend direto: quando o servidor real chegar (chamadas com await), só esta classe muda.
##
## Não tem regra de jogo. O que acontece depois de uma partida é das mecânicas (MatchReporter
## dispara os hooks globais); aqui só se compara o antes e o depois para mostrar ao jogador.

signal changed

## world.ext["onboarding"] = {"stage": ...}: progresso da estreia (O02–O05). Saves sem a chave
## (anteriores à estreia guiada) contam como "done".
const ONBOARDING_KEY := "onboarding"
const STAGE_CREATE := "create"
const STAGE_STARTER := "starter_pack"
const STAGE_FIRST_LINEUP := "first_lineup"
const STAGE_DEBUT := "debut"
const STAGE_TOUR := "tour"
const STAGE_DONE := "done"
const ONBOARDING_STAGES := [STAGE_STARTER, STAGE_FIRST_LINEUP, STAGE_DEBUT, STAGE_TOUR, STAGE_DONE]

const KIND_OFFICIAL := "official"
const KIND_FRIENDLY := "friendly"
## Clubes de demonstração que fazem o papel dos outros jogadores enquanto não há snapshots reais
## (Fase 4).
const FRIENDLY_OPPONENTS := [DemoData.HOME_CLUB, DemoData.AWAY_CLUB]
## Amistosos oferecidos: [clube, diferença de OVR pedida ao backend em relação ao seu time].
const FRIENDLY_OFFERS := [[DemoData.HOME_CLUB, 0], [DemoData.AWAY_CLUB, -5]]
## OVR usado no pareamento quando o time ainda não tem titulares.
const FALLBACK_OVR := 50
## Distância de cor (RGB, 0..1.7) abaixo da qual o visitante troca para a cor secundária.
const COLOR_CLASH := 0.35
const DEFAULT_FORMATION := "4-3-3"
const SECONDS_PER_DAY := 86400
## Fases da carreira exibidas na ficha (E03), na ordem.
const PHASES := ["promessa", "auge", "veterano", "declinio"]

var backend: Backend
var registry: MechanicRegistry
var world: World = World.new()
## Sobe a cada leitura ou gravação: telas guardadas na pilha se refazem quando ficam desatualizadas.
var revision := 0
## Partida preparada pelo Pré-jogo e consumida pela MatchView:
## {setup: MatchSetup, kind, opponent, debut: bool, reported: bool}.
var pending_match: Dictionary = {}
## Resumo da última partida registrada, para a tela de Resultado (ver finish_match).
var last_report: Dictionary = {}


func _ready() -> void:
	var app := get_node_or_null("/root/App")
	if app:
		bind(app.backend, app.registry)
	reload()


## Liga a loja a um backend e a um registro (o autoload usa os do App; testes passam os seus).
func bind(p_backend: Backend, p_registry: MechanicRegistry) -> void:
	backend = p_backend
	registry = p_registry


# --- leitura e gravação -----------------------------------------------------------------------

## Relê o mundo do backend (aplicando migrações de save).
func reload() -> void:
	var raw: Dictionary = backend.load_world() if backend else {}
	if registry and not raw.is_empty():
		raw = SaveMigrator.migrate(raw, registry)
	world = World.from_dict(raw)
	# Elenco de emergência de saves antigos (sem gerador): ganha rosto e nome de verdade, uma vez.
	if OnboardingService.repair_placeholder_athletes(world, registry, backend) > 0 and backend:
		backend.save_world(world.to_dict())
	_touch()


## Grava o mundo. false = backend recusou (a tela mostra o erro e mantém o que o jogador fez).
func persist() -> bool:
	var ok := backend != null and backend.save_world(world.to_dict())
	_touch()
	return ok


func _touch() -> void:
	revision += 1
	changed.emit()


# --- clube e elenco ---------------------------------------------------------------------------

## Clube do jogador (o save local tem um só; OnboardingService recusa o segundo).
func club() -> Club:
	for cid in world.clubs:
		return world.clubs[cid]
	return null


func has_club() -> bool:
	return club() != null


func athlete(athlete_id: String) -> Athlete:
	return world.athletes.get(athlete_id)


## Atletas do elenco, na ordem do clube.
func squad() -> Array[Athlete]:
	var out: Array[Athlete] = []
	var c := club()
	if c == null:
		return out
	for aid in c.athlete_ids:
		var a: Athlete = world.athletes.get(aid)
		if a != null:
			out.append(a)
	return out


func squad_limit() -> int:
	return _core_int("squad_limit", 30)


func lineup_size() -> int:
	return _core_int("lineup_size", 11)


func bench_size() -> int:
	return _core_int("bench_size", 5)


func _core_int(key: String, fallback: int) -> int:
	if registry == null:
		return fallback
	var v: Variant = registry.ruleset.core_param(key)
	return int(v) if v != null else fallback


## Uniforme do clube para retratos e figurinhas.
func kit() -> Dictionary:
	return PortraitRenderer.kit_for_club(club())


func is_enabled(mechanic_id: String) -> bool:
	return registry != null and registry.is_enabled(mechanic_id)


# --- tática -----------------------------------------------------------------------------------

## Tática salva do clube (cópia). Vazia se o clube ainda não tem.
func tactics() -> Dictionary:
	var c := club()
	if c == null:
		return {}
	return (c.ext.get("tactics", {}) as Dictionary).duplicate(true)


func save_tactics(t: Dictionary) -> bool:
	var c := club()
	if c == null:
		return false
	c.ext["tactics"] = t.duplicate(true)
	return persist()


func set_mentality(mentality: String) -> bool:
	if not GameTerms.MENTALITIES.has(mentality):
		return false
	var t := tactics()
	t["mentality"] = mentality
	return save_tactics(t)


## Titulares escalados (Athlete), na ordem das vagas da formação; "" vira null.
func starters() -> Array:
	var out: Array = []
	for aid in tactics().get("starting_11", []):
		out.append(athlete(str(aid)))
	return out


## TeamSetup do clube do jogador a partir da tática salva (o mesmo formato do snapshot que o
## servidor guarda para outros jogadores enfrentarem). Atletas fora do elenco ou aposentados ficam
## de fora e a validação aponta a vaga vazia.
func team_setup() -> TeamSetup:
	var c := club()
	var ts := TeamSetup.new()
	if c == null:
		return ts
	var t := tactics()
	ts.club_id = c.id
	ts.name = c.name
	ts.short_name = c.short_name
	ts.color = c.primary_color()
	ts.slots = DemoData.formation(str(t.get("formation", DEFAULT_FORMATION)))
	for aid in t.get("starting_11", []):
		var a := athlete(str(aid))
		if a != null and a.is_active() and c.athlete_ids.has(a.id) and not ts.lineup.has(a):
			ts.lineup.append(a)
	for aid in t.get("bench", []):
		var a := athlete(str(aid))
		if a != null and a.is_active() and c.athlete_ids.has(a.id) and not ts.lineup.has(a) and not ts.bench.has(a):
			ts.bench.append(a)
	# Camisas: titulares de 1 a 11 na ordem das vagas (o goleiro é a vaga 0), reservas de 12 em diante.
	for i in ts.lineup.size():
		ts.shirts[ts.lineup[i].id] = i + 1
	for i in ts.bench.size():
		ts.shirts[ts.bench[i].id] = 12 + i
	ts.tactics = _match_tactics(t)
	return ts


## Chaves que as mecânicas leem em TeamSetup.tactics (mentality, penalty_order, auto_subs) a partir
## do que a tela de escalação grava.
static func _match_tactics(t: Dictionary) -> Dictionary:
	var out := {"mentality": str(t.get("mentality", "equilibrado"))}
	var order: Array = []
	for key in ["penalty_taker_id", "freekick_taker_id", "captain_id"]:
		var aid := str(t.get(key, ""))
		if aid != "" and not order.has(aid):
			order.append(aid)
	out["penalty_order"] = order
	var stamina := int(t.get("sub_rule_stamina", 0))
	out["auto_subs"] = [{"when": "condition_below", "value": stamina / 100.0}] if stamina > 0 else []
	return out


## Problemas que impedem a partida (mensagens prontas): escalação incompleta, goleiro, banco...
func lineup_problems() -> PackedStringArray:
	if not has_club():
		return PackedStringArray()
	var ts := team_setup()
	return ts.validate(registry.ruleset if registry else null, registry.bus if registry else null)


# --- números para a interface --------------------------------------------------------------------

## OVR de um atleta: a média dos atributos (a mesma conta da figurinha e da tela de escalação).
static func overall(a: Athlete) -> int:
	return StickerCard.overall(a.attributes) if a != null else -1


## Força do time: média do OVR no geral e por setor (goleiro conta na defesa). -1 = sem atletas.
static func strength(athletes: Array) -> Dictionary:
	var sums := {"ovr": 0.0, "def": 0.0, "mid": 0.0, "fwd": 0.0}
	var counts := {"ovr": 0, "def": 0, "mid": 0, "fwd": 0}
	for a in athletes:
		if not (a is Athlete):
			continue
		var o := float(overall(a))
		var sector := "def" if a.position in ["GK", "DEF"] else ("mid" if a.position == "MID" else "fwd")
		for key in ["ovr", sector]:
			sums[key] += o
			counts[key] += 1
	var out := {}
	for key in sums:
		out[key] = roundi(sums[key] / counts[key]) if counts[key] > 0 else -1
	return out


## Idade em anos (quem responde é a career_aging, se ligada; senão a idade de nascimento).
func age(a: Athlete) -> float:
	if registry == null:
		return float(a.dna.get("initial_age", 17))
	return MatchReporter.athlete_age(registry, a)


## Carreira para a ficha: idade, dias no ano atual, dias por ano e a fase (PHASES).
func career(a: Athlete) -> Dictionary:
	var m: Mechanic = _career_mechanic()
	var per_year := int(m.param("days_per_year", 25)) if m else 25
	var years := age(a)
	var start := float(a.dna.get("initial_age", m.param("start_age", 17) if m else 17))
	var days := roundi((years - start) * per_year)
	return {
		"age": years,
		"days_in_year": posmod(days, per_year),
		"days_per_year": per_year,
		"phase": career_phase(years),
		"aging": is_enabled("career_aging"),
	}


## Fase pelo ciclo da career_aging: crescimento = promessa; o platô se divide em auge e veterano;
## a faixa de declínio = declínio. Sem a mecânica, usa os números padrão dela.
func career_phase(years: float) -> String:
	var growth_to := 27.0
	var decline_from := 38.0
	var m: Mechanic = _career_mechanic()
	if m:
		for s in m.param("stages", []):
			if float(s.get("delta", 0.0)) > 0.0:
				growth_to = float(s.get("to_age", growth_to))
			elif float(s.get("delta", 0.0)) < 0.0:
				decline_from = float(s.get("from_age", decline_from))
	if years < growth_to:
		return PHASES[0]
	if years < (growth_to + decline_from) / 2.0:
		return PHASES[1]
	if years < decline_from:
		return PHASES[2]
	return PHASES[3]


func _career_mechanic() -> Mechanic:
	if registry == null:
		return null
	if registry.is_enabled("career_aging"):
		return registry.get_mechanic("career_aging")
	return registry.available.get("career_aging")


# --- relógio do servidor e jogo oficial ---------------------------------------------------------

func server_time() -> int:
	var t := backend.server_time() if backend else 0
	return t if t > 0 else int(Time.get_unix_time_from_system())


## Data do jogo (servidor, UTC, AAAA-MM-DD).
func today() -> String:
	return Time.get_date_string_from_unix_time(server_time())


## Segundos até a virada do dia no servidor (quando o próximo oficial libera).
func seconds_to_next_day() -> int:
	return SECONDS_PER_DAY - posmod(server_time(), SECONDS_PER_DAY)


## Jogo oficial de hoje. {"enabled": false} sem a mecânica daily_official; senão o status dela
## mais "next_in" (segundos até liberar o próximo) e "today_result" (resumo do oficial de hoje).
func official_status() -> Dictionary:
	if registry == null or not registry.bus.has_handlers("daily_official.status") or not has_club():
		return {"enabled": false}
	var s: Variant = registry.bus.decide("daily_official.status", {"club": club(), "date": today()})
	var out: Dictionary = (s as Dictionary).duplicate() if s is Dictionary else {"available": false}
	out["enabled"] = true
	out["next_in"] = seconds_to_next_day()
	out["today_result"] = {}
	for r in recent_results(10):
		if r.kind == KIND_OFFICIAL and r.date == today():
			out["today_result"] = r
			break
	return out


## OVR do time escalado (ou do elenco, sem titulares): a referência do pareamento por força.
func team_ovr() -> int:
	var o := int(strength(team_setup().lineup).ovr)
	if o < 0:
		o = int(strength(squad()).ovr)
	return o if o >= 0 else FALLBACK_OVR


## Adversário do oficial de hoje: snapshot do servidor pareado pela força do seu time.
func official_opponent() -> Dictionary:
	if backend == null or not has_club():
		return {}
	var snap: Dictionary = backend.fetch_opponent_snapshot({"club_id": club().id, "kind": KIND_OFFICIAL,
		"date": today(), "target_ovr": team_ovr()})
	return opponent_from_snapshot(snap, "official")


## Adversários para amistoso (FRIENDLY_OFFERS), do mais fraco ao mais forte.
func friendly_opponents() -> Array:
	var out: Array = []
	if backend == null:
		return out
	var mine := team_ovr()
	for offer in FRIENDLY_OFFERS:
		var snap: Dictionary = backend.fetch_opponent_snapshot({"club_id": club().id if has_club() else "",
			"kind": KIND_FRIENDLY, "club_file": offer[0], "target_ovr": mine + int(offer[1])})
		var o := opponent_from_snapshot(snap, "friendly:%s" % offer[0].get_file().get_basename())
		if not o.is_empty() and (not has_club() or o.id != club().id):
			out.append(o)
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.strength.ovr < y.strength.ovr)
	return out


## Adversário pela chave (as telas passam a chave nos params, não o snapshot inteiro).
func opponent(key: String) -> Dictionary:
	if key == "official":
		return official_opponent()
	for o in friendly_opponents():
		if o.key == key:
			return o
	return {}


## Resumo de um snapshot (formato de data/demo) para as telas e para montar a partida.
static func opponent_from_snapshot(snap: Dictionary, key: String = "") -> Dictionary:
	if snap.is_empty() or not snap.has("club"):
		return {}
	var ts := DemoData.team_setup_from_dict(snap)
	var club_d: Dictionary = snap.get("club", {})
	return {
		"key": key, "id": ts.club_id, "name": ts.name, "short_name": ts.short_name,
		"color": ts.color,
		"secondary": Color.from_string(str(club_d.get("colors", {}).get("secondary", "#ffffff")), Color.WHITE),
		"formation": str(snap.get("formation", "")),
		"strength": strength(ts.lineup),
		"snapshot": snap,
	}


## Cores e sigla de um clube conhecido pelo id (o seu ou um de demonstração), para escudos.
func club_look(club_id: String) -> Dictionary:
	var c := club()
	if c and c.id == club_id:
		return {"color": c.primary_color(), "secondary": Color.from_string(str(c.colors.get("secondary", "#ffffff")), Color.WHITE), "short_name": c.short_name}
	for path in FRIENDLY_OPPONENTS:
		var d: Variant = DemoData.read_json(path)
		if d is Dictionary and str(d.get("club", {}).get("id", "")) == club_id:
			var cd: Dictionary = d.club
			return {"color": Color.from_string(str(cd.colors.primary), Color.GRAY),
				"secondary": Color.from_string(str(cd.colors.get("secondary", "#ffffff")), Color.WHITE),
				"short_name": str(cd.short_name)}
	return {}


# --- partida --------------------------------------------------------------------------------

## Prepara a partida do Pré-jogo: valida a escalação, monta o MatchSetup com semente do servidor e
## guarda em pending_match para a MatchView. {"ok": true, "setup"} ou {"ok": false, "errors"}.
func prepare_match(kind: String, opponent: Dictionary, opts: Dictionary = {}) -> Dictionary:
	if not has_club():
		return {"ok": false, "errors": [tr("ERRO_SEM_CLUBE")]}
	if opponent.is_empty() or not (opponent.get("snapshot") is Dictionary):
		return {"ok": false, "errors": [tr("ERRO_SEM_ADVERSARIO")]}
	if kind == KIND_OFFICIAL:
		var st := official_status()
		if not bool(st.get("enabled", false)):
			return {"ok": false, "errors": [tr("ERRO_OFICIAL_DESLIGADO")]}
		if not bool(st.get("available", false)):
			return {"ok": false, "errors": [tr("ERRO_OFICIAL_JOGADO")]}
	var problems := lineup_problems()
	if not problems.is_empty():
		return {"ok": false, "errors": Array(problems)}
	var away := DemoData.team_setup_from_dict(opponent.snapshot)
	var home := team_setup()
	if _color_distance(home.color, away.color) < COLOR_CLASH:
		away.color = opponent.get("secondary", Color.WHITE)
	var setup := MatchSetup.new()
	setup.rng_seed = backend.new_seed()
	setup.kind = kind
	setup.date = today()
	setup.match_minutes = float(registry.ruleset.core_param("match_minutes")) if registry else 90.0
	setup.home = home
	setup.away = away
	pending_match = {
		"setup": setup, "kind": kind, "opponent": opponent.duplicate(),
		"debut": bool(opts.get("debut", false)), "reported": false,
	}
	return {"ok": true, "setup": setup}


static func _color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func has_pending_match() -> bool:
	return not pending_match.is_empty() and pending_match.get("setup") is MatchSetup


## Registra a partida terminada uma única vez: MatchReporter (as mecânicas reagem), envio ao
## backend e gravação do mundo. Devolve o resumo para a tela de Resultado (também em last_report):
## {result, kind, opponent, debut, user_side, summary, career: {days_gained, birthdays, retired}}.
func finish_match(result: Dictionary) -> Dictionary:
	if not has_pending_match():
		return last_report
	if bool(pending_match.get("reported", false)):
		return last_report
	pending_match["reported"] = true
	var setup: MatchSetup = pending_match.setup
	var user_side := "home" if setup.home.club_id == (club().id if club() else "") else "away"
	var before := {}
	for aid in result.get(user_side, {}).get("participants", []):
		var a := athlete(str(aid))
		if a != null:
			before[a.id] = {"age": age(a), "status": a.status}
	MatchReporter.report(registry, world, result, setup.date)
	var career_report := {"days_gained": 0, "birthdays": [], "retired": []}
	for aid in before:
		var a := athlete(aid)
		var now := age(a)
		if now > float(before[aid].age) + 0.0001:
			career_report.days_gained += 1
		if floori(now) > floori(float(before[aid].age)):
			career_report.birthdays.append({"id": a.id, "name": a.name, "age": floori(now)})
		if before[aid].status != a.status and not a.is_active():
			career_report.retired.append({"id": a.id, "name": a.name})
	if backend:
		backend.submit_match_result(result)
	if bool(pending_match.get("debut", false)) and onboarding_stage() == STAGE_DEBUT:
		_set_stage(STAGE_TOUR)
	last_report = {
		"result": result, "kind": str(pending_match.kind), "opponent": pending_match.opponent,
		"debut": bool(pending_match.get("debut", false)), "user_side": user_side,
		"summary": summarize(result, club().id if club() else ""), "career": career_report,
	}
	persist()
	return last_report


## Partida abandonada antes do fim (amistoso): nada é registrado.
func discard_pending_match() -> void:
	pending_match = {}


# --- histórico --------------------------------------------------------------------------------

## Últimas partidas do clube, da mais recente para a mais antiga, já resumidas (summarize).
func recent_results(limit: int = 5) -> Array:
	if backend == null or not has_club():
		return []
	var out: Array = []
	for r in backend.fetch_match_results(club().id, limit):
		out.append(summarize(r, club().id))
	return out


## Resumo de um resultado do ponto de vista do clube `club_id`: placar, adversário e V/E/D.
## outcome: "win" | "draw" | "loss" (pênaltis decidem pelo "winner" do motor). "raw" = o resultado.
static func summarize(result: Dictionary, club_id: String) -> Dictionary:
	var side := "away" if str(result.get("away", {}).get("club_id", "")) == club_id else "home"
	var other := "home" if side == "away" else "away"
	var mine: Dictionary = result.get(side, {})
	var theirs: Dictionary = result.get(other, {})
	var winner := str(result.get("winner", ""))
	var outcome := "draw"
	if winner == side:
		outcome = "win"
	elif winner == other:
		outcome = "loss"
	var shootout: Dictionary = result.get("extra", {}).get("shootout", {})
	return {
		"raw": result,
		"kind": str(result.get("kind", KIND_FRIENDLY)), "date": str(result.get("date", "")),
		"side": side, "goals_for": int(mine.get("goals", 0)), "goals_against": int(theirs.get("goals", 0)),
		"opponent": str(theirs.get("name", "")), "opponent_id": str(theirs.get("club_id", "")),
		"outcome": outcome,
		"shootout": [int(shootout.get(side, 0)), int(shootout.get(other, 0))] if not shootout.is_empty() else [],
	}


# --- coleção ----------------------------------------------------------------------------------

## Pacotes do clube (packs.inventory); [] se a mecânica estiver desligada.
func pack_inventory() -> Array:
	if registry == null or not registry.bus.has_handlers("packs.inventory") or not has_club():
		return []
	var inv: Variant = registry.bus.decide("packs.inventory", {"club": club()})
	return inv if inv is Array else []


## Carta (formato do StickerCard) de um atleta.
static func card_for(a: Athlete) -> Dictionary:
	return {
		"kind": StickerCard.KIND_ATHLETE, "athlete_id": a.id, "tier": a.tier(), "name": a.name,
		"position": a.position, "nationality": a.nationality, "face": face_for(a),
	}


## Rosto para desenhar o atleta. Atleta sem rosto no DNA (elenco de emergência, criado quando o
## gerador está desligado) ganha um rosto de vitrine fixo pelo id: a carta nunca sai vazia e o
## mesmo atleta tem sempre a mesma cara. Só aparência: nada é gravado no DNA.
static func face_for(a: Athlete) -> Dictionary:
	if a == null:
		return {}
	var face: Variant = a.dna.get("face")
	if face is Dictionary and not (face as Dictionary).is_empty():
		return face
	var made := PreviewAthletes.generate([a.position], ["bronze"], absi(a.id.hash()) % 2147483646 + 1)
	if made.is_empty():
		return {}
	var preview: Variant = made[0].dna.get("face")
	return preview if preview is Dictionary else {}


# --- estreia ----------------------------------------------------------------------------------

## Etapa da estreia: "create" sem clube; depois ONBOARDING_STAGES (saves antigos = "done").
func onboarding_stage() -> String:
	if not has_club():
		return STAGE_CREATE
	var d: Variant = world.ext.get(ONBOARDING_KEY, {})
	var s := str((d as Dictionary).get("stage", STAGE_DONE)) if d is Dictionary else STAGE_DONE
	return s if ONBOARDING_STAGES.has(s) else STAGE_DONE


## Começa a estreia guiada logo depois de criar o clube (pacote inicial em seguida).
func start_onboarding() -> void:
	if has_club():
		_set_stage(STAGE_STARTER)
		persist()


## Avança a estreia (só para a frente) e grava.
func advance_onboarding(stage: String) -> void:
	if ONBOARDING_STAGES.find(stage) > ONBOARDING_STAGES.find(onboarding_stage()):
		_set_stage(stage)
		persist()


func _set_stage(stage: String) -> void:
	world.ext[ONBOARDING_KEY] = {"stage": stage}
