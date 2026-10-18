extends Node
## Autoload "App": monta backend, ruleset e mecânicas uma vez e os expõe ao resto do jogo.
## Classes do núcleo NÃO dependem deste autoload (para rodarem em testes e no servidor).

signal ruleset_changed

var backend: Backend = LocalBackend.new()
var registry := MechanicRegistry.new()
var ruleset: Ruleset


func _ready() -> void:
	DesignTokens.init_typography()
	registry.discover()
	apply_ruleset(Ruleset.from_dict(backend.fetch_ruleset()))


func _exit_tree() -> void:
	registry.dispose()


func apply_ruleset(rs: Ruleset) -> void:
	ruleset = rs
	registry.apply_ruleset(rs)
	for w in registry.warnings:
		push_warning(w)
	for e in registry.errors:
		push_error(e)
	print("[FOTEBA] ruleset %s v%s | mecânicas: %s" % [rs.id, rs.version, ", ".join(registry.enabled_ids())])
	ruleset_changed.emit()
