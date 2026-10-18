class_name GameTerms
extends RefCounted
## Vocabulário oficial do jogo. Idioma base: português do Brasil (i18n/termos.csv, coluna pt_BR);
## outros idiomas entram como colunas novas no mesmo CSV, sem mexer no código.
##
## Os ids internos NÃO mudam com o idioma e não aparecem na tela:
##   setor (motor, saves) ...... GK / DEF / MID / FWD   -> GOL / DEF / MEI / ATA
##   função (vaga da formação) . derivada da posição da vaga: ZAG, LE, LD, VOL, MC, ME, MD, MEI, PE, PD, CA
##   carta (DNA "tier") ........ bronze / prata / ouro / diamante / deus -> Normal / Raro / Lendário / Mítico / Divino
##   pacote (packs) ............ comum / raro / gol                     -> Básico / Raro / Mítico
##   mentalidade ............... MENTALITIES, da mais defensiva à mais ofensiva

const SECTORS := ["GK", "DEF", "MID", "FWD"]
const CARD_TIER_KEYS := {
	"bronze": "CARTA_NORMAL", "prata": "CARTA_RARO", "ouro": "CARTA_LENDARIO",
	"diamante": "CARTA_MITICO", "deus": "CARTA_DIVINO",
}
const PACK_KEYS := {"comum": "PACOTE_BASICO", "raro": "PACOTE_RARO", "gol": "PACOTE_MITICO"}
## Escala de 7 níveis (a mesma dos simuladores de gestão): muito defensivo -> muito ofensivo.
const MENTALITIES := ["retranca", "defensivo", "cauteloso", "equilibrado", "positivo", "ofensivo", "pressao_total"]

## Fronteiras (coordenadas da formação, atacando para a direita; y 0 = lado esquerdo do time).
const WIDE_DEF_MIN_LINE := 4      # laterais só existem em linhas de 4 ou 5
const WIDE_MID_Y := 0.2           # meias abertos: y <= 0.2 ou >= 0.8
const WIDE_FWD_Y := 0.25          # pontas: y <= 0.25 ou >= 0.75
const HOLDING_MID_X := 0.28       # volante: meio central até aqui
const ATTACKING_MID_X := 0.38     # meia ofensivo: meio central a partir daqui


static func text(key: String) -> String:
	return TranslationServer.translate(key)


## "GOL" / "Goleiro" para o setor do motor.
static func sector(code: String, short := true) -> String:
	var c := code if code in SECTORS else "MID"
	return text("POS_%s%s" % [c, "_CURTA" if short else ""])


## "ZAG" / "Zagueiro" para uma função ("ZAG", "LE"...).
static func role(code: String, short := true) -> String:
	return text("FUNC_%s%s" % [code, "_CURTA" if short else ""])


static func card_tier(tier_id: String) -> String:
	return text(CARD_TIER_KEYS.get(tier_id, "CARTA_NORMAL"))


static func pack(pack_id: String) -> String:
	return text(PACK_KEYS[pack_id]) if PACK_KEYS.has(pack_id) else pack_id.capitalize()


static func mentality(id: String, description := false) -> String:
	return text("MENT_%s%s" % [id.to_upper(), "_DESC" if description else ""])


## Função de cada vaga da formação (`slots` como em data/formations/*.json), na mesma ordem.
static func roles_for_formation(slots: Array) -> Array:
	var defs := slots.filter(func(s): return str(s.get("role")) == "DEF")
	var def_ys: Array = defs.map(func(s): return float(s.get("y", 0.5)))
	var out: Array = []
	for s in slots:
		var x := float(s.get("x", 0.5))
		var y := float(s.get("y", 0.5))
		match str(s.get("role", "MID")):
			"GK":
				out.append("GOL")
			"DEF":
				if defs.size() >= WIDE_DEF_MIN_LINE and y == def_ys.min():
					out.append("LE")
				elif defs.size() >= WIDE_DEF_MIN_LINE and y == def_ys.max():
					out.append("LD")
				else:
					out.append("ZAG")
			"MID":
				if y <= WIDE_MID_Y:
					out.append("ME")
				elif y >= 1.0 - WIDE_MID_Y:
					out.append("MD")
				elif x <= HOLDING_MID_X:
					out.append("VOL")
				elif x >= ATTACKING_MID_X:
					out.append("MEI")
				else:
					out.append("MC")
			_:
				if y <= WIDE_FWD_Y:
					out.append("PE")
				elif y >= 1.0 - WIDE_FWD_Y:
					out.append("PD")
				else:
					out.append("CA")
	return out
