extends TestCase
## Validação de nome/sigla e OnboardingController (sem tocar em user://).


class MemBackend extends LocalBackend:
	var saved: Dictionary = {}

	func load_world() -> Dictionary:
		return saved

	func save_world(data: Dictionary) -> bool:
		saved = data.duplicate(true)
		return true


class FakeApp extends Node:
	var backend: Backend
	var registry: MechanicRegistry


func _data(n: String, s: String) -> Dictionary:
	return {"name": n, "sigla": s, "club_identity": {"kit": {"colors": ["#16a34a", "#ffffff", "#000000"]}}}


func test_validacao_nome_e_sigla() -> void:
	check(bool(ClubValidation.validate("Estrela FC", "ECE")["ok"]), "nome/sigla válidos")
	check(bool(ClubValidation.validate("  Esporte   Clube  ", "ec")["ok"]), "normaliza espaços e caixa")
	check_eq(ClubValidation.validate("  Esporte   Clube  ", "ec")["sigla"], "EC", "sigla em maiúsculas")
	check(not bool(ClubValidation.validate("AB", "ABC")["ok"]), "nome curto demais")
	check(not bool(ClubValidation.validate("A".repeat(31), "ABC")["ok"]), "nome longo demais")
	check(not bool(ClubValidation.validate("Estrela", "A")["ok"]), "sigla curta demais")
	check(not bool(ClubValidation.validate("Estrela", "ABCDEF")["ok"]), "sigla longa demais")
	check(not bool(ClubValidation.validate("Estrela <b>", "ABC")["ok"]), "caracteres inválidos no nome")
	check(not bool(ClubValidation.validate("Estrela", "A-B")["ok"]), "caracteres inválidos na sigla")
	check(not bool(ClubValidation.validate("Aaaaaa FC", "ABC")["ok"]), "repetição excessiva")
	check(not bool(ClubValidation.validate("Time da Pu7a", "ABC")["ok"]), "termo bloqueado (leetspeak)")
	check(not bool(ClubValidation.validate("Estrela", "FDP")["ok"]), "sigla bloqueada")
	check(bool(ClubValidation.validate("São João Atlético", "SJA")["ok"]), "acentos são aceitos")


func test_controller_cria_clube_e_salva() -> void:
	var app := FakeApp.new()
	app.backend = MemBackend.new()
	app.registry = Fixtures.registry("res://rulesets/dev.json")
	var view := Node.new()
	var ctrl := OnboardingController.new()
	ctrl._app = app
	ctrl._view = view

	var res := ctrl.create_club(_data("Esporte Clube Estrela", "ece"))
	check(bool(res.get("ok", false)), "clube criado")
	var saved: Dictionary = app.backend.saved
	check_eq(saved.get("clubs", {}).size(), 1, "world salvo com 1 clube")
	check_eq(saved.get("athletes", {}).size(), 11, "world salvo com 11 atletas")
	var club: Club = res["club"]
	check_eq(club.short_name, "ECE", "sigla normalizada")
	check_eq(club.athlete_ids.size(), 11, "11 atletas no elenco")

	var again := ctrl.create_club(_data("Outro Clube", "OUT"))
	check(not bool(again.get("ok", true)), "não cria segundo clube no mesmo mundo")
	check_eq(app.backend.saved.get("clubs", {}).size(), 1, "mundo intacto após segunda tentativa")
	app.free()
	view.free()
	ctrl.free()


func test_controller_rejeita_dados_invalidos() -> void:
	var app := FakeApp.new()
	app.backend = MemBackend.new()
	app.registry = Fixtures.registry("res://rulesets/dev.json")
	var ctrl := OnboardingController.new()
	ctrl._app = app
	var res := ctrl.create_club(_data("AB", "X"))
	check(not bool(res.get("ok", true)), "dados inválidos rejeitados")
	check_eq(res.get("errors", []).size(), 2, "dois erros (nome e sigla)")
	check(app.backend.saved.is_empty(), "nada salvo")
	app.free()
	ctrl.free()
