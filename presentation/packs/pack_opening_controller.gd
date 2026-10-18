class_name PackOpeningController
extends RefCounted
## Revelação de um pacote de figurinhas no CLIENTE (PacoteFigurinhas; GDD 5.3; docs/RETRATOS.md 6).
## Quem decide é o servidor: o hook packs.open (mecânica packs) sorteia os tiers, faz nascer os
## atletas, entrega ao elenco e devolve as cartas. Este controlador só conduz a interface: mostrar
## o pacote, guardar ou abrir, revelar carta a carta e confirmar a entrega. Não sorteia nada e não
## guarda estado de jogo: se a tela fechar no meio da revelação, os atletas já estão no elenco.
##
## Estados e transições. Qualquer outra chamada devolve false e não muda nada (nem emite sinal):
##
##   IDLE ─present(lacrado)─► PREVIEW ─keep()─► KEPT ─back()─► IDLE      ("guardar": sem servidor)
##                              │
##                              └─open()─► OPENING ─┬─► REVEALING ─reveal_next()...─► COMPLETE
##                                                  │       (reveal_all() revela o resto de uma vez)
##                                                  ├─► BLOCKED (squad_full; needed_slots) ─back()─► IDLE
##                                                  └─► FAILED (erro do servidor) ─back()─► IDLE
##   COMPLETE ─finish()─► DELIVERED ─back()─► IDLE
##   present(pacote aberto ou inválido) ─► FAILED (already_opened | invalid_pack)
##   present() também é aceito em PREVIEW (trocar de pacote), KEPT e DELIVERED.
##
## OPENING dura o tempo da resposta do servidor. Hoje open_fn é síncrona, então open() passa por
## OPENING e chega a REVEALING, BLOCKED ou FAILED na mesma chamada (state_changed sai duas vezes).
##
## Ordem de revelação: atletas do tier mais baixo para o mais alto (o melhor por último; empate
## mantém a ordem do servidor) e, no fim, os slots colecionáveis ("reserved" = "Em breve") na
## ordem dos slots. `cards` já está nessa ordem; card_revealed(i, carta) usa o índice nela.
##
## Uso:
##   var ctrl := PackOpeningController.for_registry(registry, world, club)
##   ctrl.card_revealed.connect(_on_card_revealed)
##   ctrl.present(pacote_do_inventario)   # PREVIEW
##   ctrl.open(pacote.id)                 # REVEALING (ou BLOCKED / FAILED); só abre o confirmado
##   while ctrl.reveal_next(): ...        # COMPLETE ao revelar a última
##   ctrl.finish()                        # DELIVERED + delivered(athlete_ids)

enum State {IDLE, PREVIEW, KEPT, OPENING, BLOCKED, REVEALING, COMPLETE, DELIVERED, FAILED}

## Mudou de estado (valores de State).
signal state_changed(from_state: int, to_state: int)
## Carta revelada: index = posição na ordem de revelação (em `cards`); card = cópia da carta.
signal card_revealed(index: int, card: Dictionary)
## packs.open respondeu ok: result é a resposta inteira ({ok, pack, athletes, cards}).
signal opened(result: Dictionary)
## finish(): ids dos atletas entregues ao elenco, na ordem do servidor (a do elenco).
signal delivered(athlete_ids: Array)
## Entrou em FAILED: error = código (already_opened, invalid_pack, packs_unavailable ou o código
## do servidor); info = {pack_id, detail, ...resto da resposta do servidor}.
signal failed(error: String, info: Dictionary)
## Entrou em BLOCKED (elenco sem vagas): needed_slots = vagas a liberar; info = resposta do servidor.
signal blocked(needed_slots: int, info: Dictionary)

const HOOK_OPEN := "packs.open"
const HOOK_TYPES := "packs.types"
const KIND_ATHLETE := "athlete"
const STATUS_SEALED := "sealed"
## Do mais comum ao mais raro (default_params da mecânica packs).
const DEFAULT_TIER_ORDER := ["bronze", "prata", "ouro", "diamante", "deus"]
const ERR_ALREADY_OPENED := "already_opened"
const ERR_INVALID_PACK := "invalid_pack"
const ERR_PACKS_UNAVAILABLE := "packs_unavailable"
const ERR_SQUAD_FULL := "squad_full"
## Resposta com ok = false e sem código de erro.
const ERR_UNKNOWN := "open_failed"
## Estados em que present() aceita um pacote (os "de repouso" da interface).
const PRESENTABLE_FROM := [State.IDLE, State.PREVIEW, State.KEPT, State.DELIVERED]
## Estados em que back() volta para IDLE.
const BACKABLE_FROM := [State.BLOCKED, State.FAILED, State.KEPT, State.DELIVERED]

## Estado atual (só leitura; mude pelos métodos).
var state: State = State.IDLE
## Pacote em foco (cópia): o apresentado e, depois de aberto, o devolvido pelo servidor.
var pack: Dictionary = {}
## Resposta ok de packs.open ({} antes de abrir).
var result: Dictionary = {}
## Cartas na ordem de revelação (cópias de result.cards).
var cards: Array = []
## reveal_order[i] = índice em result.cards da i-ésima carta revelada.
var reveal_order: Array = []
## Quantas cartas de `cards` já foram reveladas (as primeiras revealed_count).
var revealed_count: int = 0
## Em BLOCKED: vagas que faltam liberar no elenco para o pacote abrir.
var needed_slots: int = 0
## Em FAILED ou BLOCKED: código do erro e detalhes.
var last_error: String = ""
var error_info: Dictionary = {}

var _open_fn: Callable
var _tier_order: Array = []


## open_fn(pack_id: String) -> Dictionary no formato de packs.open; null (ou Callable inválida)
## vira FAILED "packs_unavailable". tier_order define a ordem de revelação.
func _init(open_fn: Callable = Callable(), tier_order: Array = DEFAULT_TIER_ORDER) -> void:
	_open_fn = open_fn
	for t in tier_order:
		_tier_order.append(str(t))


## Controlador ligado ao servidor local: open_fn = registry.bus.decide("packs.open", ...) e ordem
## dos tiers de packs.types. Com a mecânica packs desligada, open() termina em FAILED
## "packs_unavailable".
static func for_registry(registry: MechanicRegistry, world: World, club: Club) -> PackOpeningController:
	var order: Array = DEFAULT_TIER_ORDER
	if registry != null:
		var types: Variant = registry.bus.decide(HOOK_TYPES, {})
		if types is Dictionary and types.get("tier_order") is Array and not (types.tier_order as Array).is_empty():
			order = types.tier_order
	var open_fn := func(pack_id: String) -> Variant:
		if registry == null:
			return null
		return registry.bus.decide(HOOK_OPEN, {"world": world, "club": club, "pack_id": pack_id})
	return PackOpeningController.new(open_fn, order)


# --- transições ------------------------------------------------------------------------------------

## Mostra um pacote do inventário. Lacrado -> PREVIEW; aberto -> FAILED already_opened; sem id
## -> FAILED invalid_pack. Aceito em IDLE, PREVIEW, KEPT e DELIVERED.
func present(p_pack: Dictionary) -> bool:
	if not PRESENTABLE_FROM.has(state):
		return false
	_clear()
	pack = p_pack.duplicate(true)
	var pack_id := str(pack.get("id", ""))
	if pack_id == "":
		_fail(ERR_INVALID_PACK, {"pack_id": "", "detail": "pacote sem id"})
	elif str(pack.get("status", "")) != STATUS_SEALED:
		_fail(ERR_ALREADY_OPENED, {"pack_id": pack_id,
			"detail": "pacote %s não está lacrado (status %s)" % [pack_id, str(pack.get("status", ""))]})
	else:
		_set_state(State.PREVIEW)
	return true


## "Guardar": PREVIEW -> KEPT. Não fala com o servidor; o pacote segue lacrado no inventário.
func keep() -> bool:
	if state != State.PREVIEW:
		return false
	_set_state(State.KEPT)
	return true


## Pede a abertura ao servidor: PREVIEW -> OPENING -> REVEALING (ok), BLOCKED (squad_full) ou
## FAILED (qualquer outro erro, ou servidor sem resposta).
## expected_pack_id: o pacote que o usuário confirmou. Se o pacote em prévia já não é esse (a
## interface trocou de pacote entre o clique e a chamada, por exemplo durante uma animação),
## devolve false e não fala com o servidor: abrir é irreversível. "" = o pacote em prévia.
func open(expected_pack_id: String = "") -> bool:
	if state != State.PREVIEW:
		return false
	if expected_pack_id != "" and str(pack.get("id", "")) != expected_pack_id:
		return false
	_set_state(State.OPENING)
	var res: Variant = null
	if _open_fn.is_valid():
		res = _open_fn.call(str(pack.get("id", "")))
	_receive(res)
	return true


## Revela a próxima carta (REVEALING). A última leva a COMPLETE.
func reveal_next() -> bool:
	if state != State.REVEALING or revealed_count >= cards.size():
		return false
	var index := revealed_count
	revealed_count += 1
	card_revealed.emit(index, (cards[index] as Dictionary).duplicate(true))
	if state == State.REVEALING and revealed_count >= cards.size():
		_set_state(State.COMPLETE)
	return true


## Revela todas as cartas que faltam, em ordem (um card_revealed por carta) -> COMPLETE.
func reveal_all() -> bool:
	if state != State.REVEALING:
		return false
	while state == State.REVEALING and revealed_count < cards.size():
		reveal_next()
	return true


## Confirma a entrega: COMPLETE -> DELIVERED e delivered(athlete_ids). Os atletas já estão no
## elenco desde packs.open (o servidor é a fonte da verdade); aqui a interface só fecha o ciclo.
func finish() -> bool:
	if state != State.COMPLETE:
		return false
	var ids := athlete_ids()
	_set_state(State.DELIVERED)
	delivered.emit(ids)
	return true


## Volta ao início: BLOCKED, FAILED, KEPT ou DELIVERED -> IDLE (esquece pacote e cartas).
func back() -> bool:
	if not BACKABLE_FROM.has(state):
		return false
	_clear()
	_set_state(State.IDLE)
	return true


# --- consultas -------------------------------------------------------------------------------------

## Ids dos atletas do pacote aberto, na ordem do servidor ([] antes de abrir).
func athlete_ids() -> Array:
	var ids: Array = []
	for c in result.get("cards", []):
		if c is Dictionary and str(c.get("kind", "")) == KIND_ATHLETE:
			ids.append(str(c.get("athlete_id", "")))
	return ids


## Cartas que ainda faltam revelar.
func remaining() -> int:
	return cards.size() - revealed_count


func is_revealed(index: int) -> bool:
	return index >= 0 and index < revealed_count


func tier_order() -> Array:
	return _tier_order.duplicate()


static func state_name(s: int) -> String:
	var names: Array = State.keys()
	return str(names[s]) if s >= 0 and s < names.size() else "?"


## Índices de p_cards na ordem de revelação: atletas por tier crescente (tier fora de tier_order
## conta como o mais baixo; empate mantém a ordem original), depois as demais cartas (slots
## colecionáveis) na ordem original.
static func sort_for_reveal(p_cards: Array, tier_order: Array = DEFAULT_TIER_ORDER) -> Array:
	var athletes: Array = []
	var others: Array = []
	for i in p_cards.size():
		var c: Variant = p_cards[i]
		if c is Dictionary and str(c.get("kind", "")) == KIND_ATHLETE:
			athletes.append([tier_order.find(str(c.get("tier", ""))), i])
		else:
			others.append(i)
	athletes.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var order: Array = []
	for a in athletes:
		order.append(a[1])
	order.append_array(others)
	return order


# --- interno ---------------------------------------------------------------------------------------

func _receive(res: Variant) -> void:
	var pack_id := str(pack.get("id", ""))
	if not (res is Dictionary):
		_fail(ERR_PACKS_UNAVAILABLE, {"pack_id": pack_id,
			"detail": "%s não respondeu (mecânica packs desligada ou servidor indisponível)" % HOOK_OPEN})
		return
	var response: Dictionary = res
	if not bool(response.get("ok", false)):
		var code := str(response.get("error", ""))
		var info := response.duplicate(true)
		info["pack_id"] = pack_id
		info["detail"] = str(response.get("detail", ""))
		if code == ERR_SQUAD_FULL:
			needed_slots = maxi(0, int(response.get("needed_slots", 0)))
			last_error = code
			error_info = info
			_set_state(State.BLOCKED)
			blocked.emit(needed_slots, info.duplicate(true))
		else:
			_fail(code if code != "" else ERR_UNKNOWN, info)
		return

	result = response
	if response.get("pack") is Dictionary:
		pack = (response.pack as Dictionary).duplicate(true)
	var all_cards: Array = response.get("cards", []) if response.get("cards") is Array else []
	reveal_order = sort_for_reveal(all_cards, _tier_order)
	cards = []
	for i in reveal_order:
		var c: Variant = all_cards[i]
		cards.append((c as Dictionary).duplicate(true) if c is Dictionary else {})
	revealed_count = 0
	_set_state(State.REVEALING)
	opened.emit(result)
	if state == State.REVEALING and cards.is_empty():
		_set_state(State.COMPLETE)


func _fail(code: String, info: Dictionary) -> void:
	last_error = code
	error_info = info
	_set_state(State.FAILED)
	failed.emit(code, info.duplicate(true))


func _clear() -> void:
	pack = {}
	result = {}
	cards = []
	reveal_order = []
	revealed_count = 0
	needed_slots = 0
	last_error = ""
	error_info = {}


func _set_state(to: State) -> void:
	var from := state
	state = to
	state_changed.emit(from, to)
