class_name PitchSkins
extends RefCounted
## Campos (gramados) disponíveis. O jogador ganha campos em pacotes de figurinhas ou compra na loja;
## a partida usa o campo do MANDANTE (MatchTeam ext "pitch_skin"), como num estádio de verdade.
##
## Campo novo: duplique visuais/campo/campo_template.psd como campo_<id>.psd, pinte e rode
## "Exportar Campo.command" (gera assets/pitch/campo_<id>@2x.png e @4x.png). Depois acrescente o id
## aqui. Medidas e regras da arte: visuais/campo/criar_template_campo.jsx.

const DIR := "res://assets/pitch/"
const DEFAULT := "gramado"
## id -> file: prefixo dos PNGs em assets/pitch; label: nome exibido; has_lines: a arte já traz as
## marcações (senão o código desenha as linhas por cima).
const SKINS := {
	"gramado": {"file": "campo_gramado", "label": "Gramado clássico", "has_lines": true},
}


static func ids() -> Array:
	return SKINS.keys()


static func is_valid(id: String) -> bool:
	return SKINS.has(id) and ResourceLoader.exists(texture_path(id, 2))


static func for_team(team: MatchTeam) -> String:
	var id := str(team.ext.get("pitch_skin", "")) if team else ""
	return id if is_valid(id) else DEFAULT


## Caminho da versão @2x ou @4x.
static func texture_path(id: String, scale: int) -> String:
	var skin: Dictionary = SKINS.get(id, SKINS[DEFAULT])
	return "%s%s@%dx.png" % [DIR, skin.file, scale]


static func has_lines(id: String) -> bool:
	return bool(SKINS.get(id, {}).get("has_lines", false))


static func label(id: String) -> String:
	return str(SKINS.get(id, {}).get("label", id))
