class_name Mechanic
extends RefCounted
## Classe base de TODA mecânica plugável. Cada mecânica vive em res://mechanics/<id>/mechanic.gd
## e é descoberta automaticamente pelo MechanicRegistry.
##
## Regras de ouro (detalhes em docs/ARQUITETURA.md):
##   1. Conversa com o núcleo e com outras mecânicas SÓ por hooks (nunca referencie outra mecânica).
##   2. Estado de partida vai em ctx.state_for(id) / player.ext[id] / team.ext[id] — nunca em variáveis
##      da instância (a mesma instância serve a várias partidas).
##   3. Dados persistentes vão em athlete.ext[id] / club.ext[id] / world.ext[id].
##   4. Aleatoriedade só via ctx.rng_for(id). Nada de randf(), Time ou OS em regras.
##   5. Todo número de balanceamento vai em default_params (sobrescrevível pelo ruleset).

const LAYERS := ["match", "career", "economy", "meta", "presentation"]
## Ciclo de vida: experimental (só em rulesets de teste) -> stable -> deprecated -> pasta apagada.
const STAGES := ["experimental", "stable", "deprecated"]

# --- Metadados: preencha no _init() da subclasse -------------------------------------------
var id: String = ""
var title: String = ""
var description: String = ""
## Suba quando o COMPORTAMENTO mudar (entra na assinatura das partidas; replays antigos sabem que regra usaram).
var version: int = 1
## Suba quando o FORMATO dos dados em ext mudar, e implemente migrate_data().
var data_version: int = 1
var layer: String = "match"
var stage: String = "stable"
var depends_on: Array = []        # ids de mecânicas obrigatórias
var conflicts_with: Array = []    # ids incompatíveis
var enabled_by_default: bool = false
var default_params: Dictionary = {}
var provides_hooks: Dictionary = {}   # "<id>.<nome>": "documentação" — hooks que esta mecânica oferece

# --- Preenchido pelo registro ---------------------------------------------------------------
var params: Dictionary = {}
var _registry_ref: WeakRef = null
var registry: MechanicRegistry:
	get:
		return _registry_ref.get_ref() as MechanicRegistry if _registry_ref != null else null
	set(val):
		_registry_ref = weakref(val) if val != null else null


## Registra hooks globais (mundo/carreira/economia). Chamado a cada aplicação de ruleset.
func install(_bus: HookBus) -> void:
	pass


## Registra hooks de UMA partida em ctx.bus. Chamado ao montar cada partida.
func setup_match(_ctx: MatchContext) -> void:
	pass


## Converte dados antigos de ext (de from_version para from_version + 1).
## owner_kind: "athlete" | "club" | "world".
func migrate_data(_owner_kind: String, _from_version: int, data: Dictionary) -> Dictionary:
	return data


func param(key: String, fallback: Variant = null) -> Variant:
	return params.get(key, default_params.get(key, fallback))


func describe() -> Dictionary:
	return {
		"id": id, "title": title, "description": description, "version": version,
		"data_version": data_version, "layer": layer, "stage": stage, "depends_on": depends_on,
		"conflicts_with": conflicts_with, "enabled_by_default": enabled_by_default,
		"default_params": default_params, "provides_hooks": provides_hooks,
	}
