extends TestCase
## Textos das telas novas: todo texto vem do i18n/termos.csv (PLANO_DE_TELAS, Fase 0) e toda chave
## usada existe. Vale para as pastas criadas com a casca; as telas antigas ainda têm texto fixo.

const CSV := "res://i18n/termos.csv"
const DIRS := [
	"res://presentation/ui", "res://presentation/shell", "res://presentation/state", "res://presentation/home",
	"res://presentation/prematch", "res://presentation/result", "res://presentation/squad",
	"res://presentation/club", "res://presentation/collection", "res://presentation/shop",
	"res://presentation/onboarding",
]
const EXTRA_FILES := ["res://presentation/match_view/match_summary_overlay.gd"]


func _keys() -> Dictionary:
	var out := {}
	var f := FileAccess.open(CSV, FileAccess.READ)
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() >= 2 and row[0] != "":
			out[row[0]] = row[1]
	return out


func _files() -> Array:
	var out: Array = EXTRA_FILES.duplicate()
	for d in DIRS:
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd"):
				out.append(d.path_join(f))
	return out


func test_chaves_existem() -> void:
	var keys := _keys()
	var re := RegEx.new()
	re.compile("(?:tr|translate)\\(\"([A-Z0-9_]+)\"\\)")
	var seen := 0
	for path in _files():
		var src := FileAccess.get_file_as_string(path)
		for m in re.search_all(src):
			seen += 1
			check(keys.has(m.get_string(1)), "%s usa a chave %s, que não está no termos.csv" % [path.get_file(), m.get_string(1)])
	check(seen > 100, "o lint achou as chaves (%d)" % seen)


func test_chaves_dinamicas() -> void:
	var keys := _keys()
	for ph in GameStore.PHASES:
		check(keys.has("FASE_" + ph.to_upper()), "fase %s" % ph)
	for k in MatchSetup.KINDS:
		check(keys.has("TIPO_" + k.to_upper()), "tipo de partida %s" % k)
	for tab in Routes.TABS:
		check(keys.has(Routes.TAB_LABELS[tab]), "rótulo da aba %s" % tab)
	for id in Routes.TABLE:
		var t := str(Routes.get_route(id).get("title", ""))
		check(t == "" or keys.has(t), "título da rota %s" % id)
	for r in MatchStats.ROWS:
		check(keys.has(r[0]), "estatística %s" % r[0])


## Texto de interface escrito direto no código: literal com letra e espaço (ou acento) fora de
## comentários. Chaves (MAIUSCULAS_COM_SUBLINHADO), caminhos e nomes de nó não têm espaço.
func test_sem_texto_fixo() -> void:
	var lit := RegEx.new()
	lit.compile("\"((?:[^\"\\\\]|\\\\.)*)\"")
	var fmt := RegEx.new()
	fmt.compile("%[-+0-9.]*[dsfx%]")
	var letter := RegEx.new()
	letter.compile("\\p{L}")
	for path in _files():
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var code := lines[i].strip_edges()
			# Comentários e mensagens de log para o desenvolvedor não são texto de interface.
			if code.begins_with("#") or code.contains("push_error(") or code.contains("push_warning(") or code.begins_with("print("):
				continue
			var hash_at := code.find(" ## ")
			if hash_at >= 0:
				code = code.substr(0, hash_at)
			for m in lit.search_all(code):
				var s := fmt.sub(m.get_string(1), "", true)
				var has_letter := letter.search(s) != null
				var accented := false
				for ch in s:
					if ch.unicode_at(0) > 127 and letter.search(ch) != null:
						accented = true
				if has_letter and (s.contains(" ") or accented):
					failures.append("%s:%d texto fixo: \"%s\" (use uma chave do termos.csv)" % [path.get_file(), i + 1, m.get_string(1)])


func test_csv_sem_chave_repetida() -> void:
	var seen := {}
	var f := FileAccess.open(CSV, FileAccess.READ)
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 2 or row[0] == "":
			continue
		check(not seen.has(row[0]), "chave repetida: %s" % row[0])
		seen[row[0]] = true


func test_icones_existem() -> void:
	for id in GameIcons.PATHS:
		check(GameIcons.has(id), "ícone '%s' (%s) existe" % [id, GameIcons.PATHS[id]])
	# Nome de arquivo com acento some no Android (o macOS grava o acento decomposto): só ASCII.
	var paths: Array = GameIcons.PATHS.values() + ButtonPieces.STYLES.values()
	for p in paths:
		var ascii := true
		for ch in str(p):
			ascii = ascii and ch.unicode_at(0) < 128
		check(ascii, "caminho só ASCII: %s" % p)
