class_name TestGameTerms
extends TestCase
## Vocabulário oficial (GameTerms + i18n/termos.csv), escala de mentalidade e catálogo de campos.


func _formation(id: String) -> Array:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/formations/%s.json" % id))
	return d.slots


func test_setores_em_portugues() -> void:
	check_eq([GameTerms.sector("GK"), GameTerms.sector("DEF"), GameTerms.sector("MID"), GameTerms.sector("FWD")],
		["GOL", "DEF", "MEI", "ATA"], "siglas")
	check_eq(GameTerms.sector("MID", false), "Meio-campista", "nome por extenso")
	check_eq(GameTerms.sector("XYZ"), "MEI", "setor desconhecido não quebra")


func test_nomes_de_cartas_e_pacotes() -> void:
	var cards := ["bronze", "prata", "ouro", "diamante", "deus"].map(func(t): return GameTerms.card_tier(t))
	check_eq(cards, ["Normal", "Raro", "Lendário", "Mítico", "Divino"], "tipos de carta")
	check_eq([GameTerms.pack("comum"), GameTerms.pack("raro"), GameTerms.pack("gol")], ["Básico", "Raro", "Mítico"], "pacotes")


func test_toda_chave_tem_texto_em_portugues() -> void:
	var lines := FileAccess.get_file_as_string("res://i18n/termos.csv").split("\n", false)
	for i in range(1, lines.size()):
		var key := lines[i].split(",")[0]
		check(GameTerms.text(key) != key, "sem tradução: %s" % key)


func test_funcoes_derivadas_das_formacoes() -> void:
	check_eq(GameTerms.roles_for_formation(_formation("4-3-3")),
		["GOL", "LE", "ZAG", "ZAG", "LD", "VOL", "MEI", "MEI", "PE", "CA", "PD"], "4-3-3")
	check_eq(GameTerms.roles_for_formation(_formation("4-2-3-1")),
		["GOL", "LE", "ZAG", "ZAG", "LD", "VOL", "VOL", "ME", "MEI", "MD", "CA"], "4-2-3-1")
	check_eq(GameTerms.roles_for_formation(_formation("3-5-2")).slice(1, 4), ["ZAG", "ZAG", "ZAG"], "linha de 3 não tem laterais")
	for f in ["3-4-3", "3-5-2", "4-2-3-1", "4-3-3", "4-4-2", "5-3-2"]:
		var roles := GameTerms.roles_for_formation(_formation(f))
		check_eq(roles.size(), 11, "%s: 11 funções" % f)
		for r in roles:
			check(GameTerms.role(r) != "FUNC_%s_CURTA" % r, "%s: função %s sem texto" % [f, r])


func test_escala_de_mentalidade_completa_e_ordenada() -> void:
	var mech: Mechanic = load("res://mechanics/mentality/mechanic.gd").new()
	var profiles: Dictionary = mech.default_params["profiles"]
	for m in GameTerms.MENTALITIES:
		check(profiles.has(m), "perfil existe no motor: %s" % m)
		check(GameTerms.mentality(m, true) != "MENT_%s_DESC" % m.to_upper(), "descrição: %s" % m)
	check_eq(GameTerms.MENTALITIES.size(), 7, "7 níveis")
	# Do mais defensivo ao mais ofensivo, a linha nunca recua.
	var last := -INF
	for m in GameTerms.MENTALITIES:
		var line := float(profiles[m].get("line_height", MatchTeam.DEFAULT_KNOBS.line_height))
		check(line >= last, "linha cresce até %s" % m)
		last = line


func test_catalogo_de_campos() -> void:
	check(PitchSkins.is_valid(PitchSkins.DEFAULT), "campo padrão existe")
	check(PitchSkins.texture_path("gramado", 4).ends_with("campo_gramado@4x.png"), "caminho @4x")
	var team := MatchTeam.new()
	check_eq(PitchSkins.for_team(team), PitchSkins.DEFAULT, "sem escolha: padrão")
	team.ext["pitch_skin"] = "nao_existe"
	check_eq(PitchSkins.for_team(team), PitchSkins.DEFAULT, "id inválido: padrão")
