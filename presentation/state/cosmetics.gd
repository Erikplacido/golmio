class_name Cosmetics
extends RefCounted
## Itens de visual do clube: padrões de camisa e brasões. Os grátis valem desde a criação do clube;
## os outros entram em `club.ext["cosmetics"]` quando o jogador ganha numa recompensa ou na loja.
## Nome e cores do clube nunca mudam depois da criação: estes itens só mexem no desenho.

## Padrões (ids de UniformMaps.PATTERNS); `label` é chave do termos.csv. `params`: "count" (repetições) ou "width" (largura).
const PATTERNS := {
	"lisa": {"label": "PADRAO_LISA", "free": true},
	"listras_verticais": {"label": "PADRAO_LISTRAS_VERTICAIS", "free": true, "params": "count"},
	"listras_horizontais": {"label": "PADRAO_LISTRAS_HORIZONTAIS", "free": true, "params": "count"},
	"faixa_horizontal": {"label": "PADRAO_FAIXA_HORIZONTAL", "free": true, "params": "width"},
	"faixa_vertical": {"label": "PADRAO_FAIXA_VERTICAL", "free": true, "params": "width"},
	"faixa_diagonal": {"label": "PADRAO_FAIXA_DIAGONAL", "free": true, "params": "width"},
	"metades": {"label": "PADRAO_METADES", "free": true},
	"xadrez": {"label": "PADRAO_XADREZ", "free": true, "params": "count"},
	"listras_diagonais": {"label": "PADRAO_LISTRAS_DIAGONAIS", "free": false, "params": "count"},
	"chevron": {"label": "PADRAO_CHEVRON", "free": false, "params": "width"},
	"duas_faixas": {"label": "PADRAO_DUAS_FAIXAS", "free": false, "params": "width"},
	"losangos": {"label": "PADRAO_LOSANGOS", "free": false, "params": "count"},
}

## Brasões: forma do escudo + desenho interno (ClubCrest). O primeiro é o padrão.
const CRESTS := {
	"classico_faixa": {"shape": "classico", "motif": "faixa_vertical", "free": true},
	"redondo_liso": {"shape": "redondo", "motif": "liso", "free": true},
	"frances_metades": {"shape": "frances", "motif": "metades", "free": true},
	"flamula_diagonal": {"shape": "flamula", "motif": "faixa_diagonal", "free": true},
	"classico_estrela": {"shape": "classico", "motif": "estrela", "free": false},
	"redondo_listras": {"shape": "redondo", "motif": "listras", "free": false},
	"losango_estrela": {"shape": "losango", "motif": "estrela", "free": false},
	"frances_estrela": {"shape": "frances", "motif": "estrela", "free": false},
	"losango_metades": {"shape": "losango", "motif": "metades", "free": false},
	"flamula_listras": {"shape": "flamula", "motif": "listras", "free": false},
}
const DEFAULT_CREST := "classico_faixa"


static func _entry(id: String) -> Dictionary:
	if PATTERNS.has(id):
		return PATTERNS[id]
	if CRESTS.has(id):
		return CRESTS[id]
	if ButtonPieces.STYLES.has(id):
		return {"free": id in [ButtonPieces.DEFAULT_HOME, ButtonPieces.DEFAULT_AWAY]}
	if PitchSkins.SKINS.has(id):
		return {"free": id == PitchSkins.DEFAULT}
	return {"free": false}


## Liberado para este clube (null = clube ainda não criado: só os grátis).
static func is_unlocked(id: String, club: Club = null) -> bool:
	var e := _entry(id)
	if bool(e.get("free", false)):
		return true
	return club != null and (club.ext.get("cosmetics", []) as Array).has(id)


## Dá o item ao clube (recompensa, loja). Devolve false se não existe ou já era dele.
static func unlock(club: Club, id: String) -> bool:
	if club == null or is_unlocked(id, club):
		return false
	var owned: Array = club.ext.get("cosmetics", [])
	if not owned.has(id):
		owned.append(id)
	club.ext["cosmetics"] = owned
	return true


## Itens ainda bloqueados para o clube: o sorteio de recompensa tira daqui.
static func locked(club: Club) -> Array:
	var out := []
	for id in PATTERNS.keys() + CRESTS.keys():
		if not is_unlocked(id, club):
			out.append(id)
	return out
