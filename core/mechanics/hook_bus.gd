class_name HookBus
extends RefCounted
## Barramento de hooks. Núcleo e mecânicas só conversam por aqui.
## Ordem de execução determinística: prioridade (menor primeiro) -> id do dono -> ordem de registro.

var _handlers: Dictionary = {}   # hook(String) -> Array[{cb, owner, priority, seq}]
var _known: Dictionary = {}      # hooks válidos; vazio = sem validação
var _seq := 0


func _init(known_hooks: Dictionary = {}) -> void:
	_known = known_hooks


func on(hook: String, callback: Callable, owner: String = "", priority: int = 0) -> void:
	if not _known.is_empty() and not _known.has(hook):
		push_error("Hook desconhecido '%s' (registrado por '%s'). Declare em Hooks.CATALOG ou em provides_hooks da mecânica." % [hook, owner])
		return
	_seq += 1
	var list: Array = _handlers.get(hook, [])
	list.append({"cb": callback, "owner": owner, "priority": priority, "seq": _seq})
	list.sort_custom(_sort_handlers)
	_handlers[hook] = list


func has_handlers(hook: String) -> bool:
	return _handlers.has(hook)


func owners_of(hook: String) -> PackedStringArray:
	var out := PackedStringArray()
	for h in _handlers.get(hook, []):
		out.append(h.owner)
	return out


func emit(hook: String, payload: Dictionary = {}) -> void:
	for h in _handlers.get(hook, []):
		h.cb.call(payload)


func pipe(hook: String, value: Variant, payload: Dictionary = {}) -> Variant:
	for h in _handlers.get(hook, []):
		var out: Variant = h.cb.call(value, payload)
		if out == null:
			push_error("Handler de '%s' da mecânica '%s' não retornou valor (pipe exige retorno)." % [hook, h.owner])
			continue
		value = out
	return value


func decide(hook: String, payload: Dictionary = {}) -> Variant:
	for h in _handlers.get(hook, []):
		var out: Variant = h.cb.call(payload)
		if out != null:
			return out
	return null


static func _sort_handlers(a: Dictionary, b: Dictionary) -> bool:
	if a.priority != b.priority:
		return a.priority < b.priority
	if a.owner != b.owner:
		return a.owner < b.owner
	return a.seq < b.seq
