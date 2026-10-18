class_name ClubValidation
extends RefCounted
## Validação básica de nome e sigla do clube (sem moderação de servidor por ora).
## Regras: nome 3–30 caracteres, sigla 2–5 (só letras/números), sem termos da lista de bloqueio.
## Estática e pura: roda no cliente (feedback imediato) e de novo no onboarding (defesa).

const NAME_MIN := 3
const NAME_MAX := 30
const SIGLA_MIN := 2
const SIGLA_MAX := 5

## Termos barrados (comparados sem acento, sem símbolos e com leetspeak normalizado).
## Lista mínima; a moderação de verdade virá do servidor.
const BLOCKED_TERMS := [
	"porra", "caralho", "puta", "merda", "buceta", "viado", "cuzao", "foder", "fdp",
	"nazi", "hitler", "kkk", "fuck", "shit", "bitch", "nigger", "rape", "estupro",
]

const _ACCENTS := {
	"á": "a", "à": "a", "â": "a", "ã": "a", "ä": "a", "é": "e", "è": "e", "ê": "e", "ë": "e",
	"í": "i", "ì": "i", "î": "i", "ï": "i", "ó": "o", "ò": "o", "ô": "o", "õ": "o", "ö": "o",
	"ú": "u", "ù": "u", "û": "u", "ü": "u", "ç": "c",
}
const _LEET := {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s"}


## {"ok": bool, "name": nome normalizado, "sigla": sigla normalizada, "errors": Array[String]}
static func validate(club_name: String, sigla: String) -> Dictionary:
	var n := club_name.strip_edges()
	while n.contains("  "):
		n = n.replace("  ", " ")
	var s := sigla.strip_edges().to_upper()
	var errors: Array[String] = []

	if len(n) < NAME_MIN or len(n) > NAME_MAX:
		errors.append("O nome do clube deve ter entre %d e %d caracteres." % [NAME_MIN, NAME_MAX])
	elif not _name_regex().search(n):
		errors.append("O nome só pode ter letras, números, espaço e . ' & -")
	elif _repeats(n):
		errors.append("O nome tem caracteres repetidos demais.")
	elif _is_blocked(n):
		errors.append("Esse nome não é permitido. Escolha outro.")

	if len(s) < SIGLA_MIN or len(s) > SIGLA_MAX:
		errors.append("A sigla deve ter entre %d e %d caracteres." % [SIGLA_MIN, SIGLA_MAX])
	elif not _sigla_regex().search(s):
		errors.append("A sigla só pode ter letras e números.")
	elif _is_blocked(s):
		errors.append("Essa sigla não é permitida.")

	return {"ok": errors.is_empty(), "name": n, "sigla": s, "errors": errors}


static func _name_regex() -> RegEx:
	var r := RegEx.new()
	r.compile("^[\\p{L}\\p{N} .'&-]+$")
	return r


static func _sigla_regex() -> RegEx:
	var r := RegEx.new()
	r.compile("^[\\p{L}\\p{N}]+$")
	return r


## 4+ caracteres iguais seguidos ("aaaaa").
static func _repeats(text: String) -> bool:
	var run := 1
	for i in range(1, len(text)):
		run = run + 1 if text[i].to_lower() == text[i - 1].to_lower() else 1
		if run >= 4:
			return true
	return false


static func _normalize(text: String) -> String:
	var out := ""
	for ch in text.to_lower():
		if _ACCENTS.has(ch):
			ch = _ACCENTS[ch]
		elif _LEET.has(ch):
			ch = _LEET[ch]
		if ch >= "a" and ch <= "z":
			out += ch
	return out


static func _is_blocked(text: String) -> bool:
	var flat := _normalize(text)
	for term in BLOCKED_TERMS:
		if flat.contains(term):
			return true
	return false
