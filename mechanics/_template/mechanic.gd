extends Mechanic
## MODELO — copie esta pasta para res://mechanics/<seu_id>/ e renomeie o id.
## Pastas que começam com "_" nunca são carregadas.
## Checklist completo em res://mechanics/README.md.


func _init() -> void:
	id = "_template"                       # = nome da pasta
	title = "Nome legível"
	description = "O que muda no jogo e em que seção do GDD está."
	version = 1                            # suba quando o comportamento mudar
	data_version = 1                       # suba quando o formato de ext mudar (+ migrate_data)
	layer = "match"                        # match | career | economy | meta | presentation
	stage = "experimental"                 # experimental -> stable -> deprecated
	depends_on = []                        # ex.: ["stamina"] — desliga junto se a dependência cair
	conflicts_with = []
	enabled_by_default = false             # nasce desligada; ligue no ruleset de teste primeiro
	default_params = {
		"exemplo_intensidade": 1.0,        # TODO número de balanceamento aqui, nunca fixo no código
	}
	provides_hooks = {
		# "_template.algo": "pipe float ... ; payload {ctx, ...} — para outras mecânicas estenderem",
	}


## Hooks globais (mundo/carreira/economia). Remova se não usar.
func install(bus: HookBus) -> void:
	# bus.on(Hooks.OFFICIAL_MATCH_PLAYED, _on_official, id)
	pass


## Hooks de uma partida. Remova se não usar.
func setup_match(ctx: MatchContext) -> void:
	# ctx.bus.on(Hooks.TEAM_KNOBS, _on_knobs, id)
	pass


# func _on_knobs(knobs: Dictionary, payload: Dictionary) -> Dictionary:
# 	var ctx: MatchContext = payload.ctx
# 	knobs.press_radius *= float(param("exemplo_intensidade"))
# 	return knobs   # pipe SEMPRE retorna o valor
