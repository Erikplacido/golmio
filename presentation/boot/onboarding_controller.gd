class_name OnboardingController
extends Node
## Onboarding: liga a tela de criação de clube ao mundo. Recebe `club_saved` da view, valida de
## novo (defesa), carrega o World do backend, cria o clube com os 11 atletas iniciais
## (OnboardingService: packs.grant_starter / athlete_generator.generate via bus.decide) e salva.
## Depois troca para `next_scene` ("" = quem ouve `completed` navega, como a estreia guiada do
## Router). Não guarda estado de jogo.

const HUB_SCENE := "res://presentation/tactics/tactics_view.tscn"

## Clube criado e mundo salvo.
signal completed(club: Club)
## Falha (validação ou backend); a view continua aberta.
signal failed(errors: Array)

## Cena aberta depois de criar o clube; "" = não troca de cena (quem ouve `completed` decide).
var next_scene := HUB_SCENE
var _app: Node
var _view: Node


## Conecta a view (ClubCreationView) e devolve o controlador. `app` é o autoload App.
static func attach(view: Node, app: Node) -> OnboardingController:
	var c := OnboardingController.new()
	c._app = app
	c._view = view
	view.club_saved.connect(c._on_club_saved)
	if view.has_method("show_errors"):
		c.failed.connect(view.show_errors)
	view.add_child(c)
	return c


func _on_club_saved(club_data: Dictionary) -> void:
	var res := create_club(club_data)
	if bool(res.get("ok", false)):
		completed.emit(res["club"])
		if next_scene != "":
			get_tree().change_scene_to_file.call_deferred(next_scene)
	else:
		failed.emit(res.get("errors", []))


## Núcleo testável, sem troca de cena. Devolve {"ok", "club", "athletes"} ou {"ok": false, "errors"}.
func create_club(club_data: Dictionary) -> Dictionary:
	var check := ClubValidation.validate(str(club_data.get("name", "")), str(club_data.get("sigla", "")))
	if not bool(check["ok"]):
		return {"ok": false, "errors": check["errors"]}
	if _app == null or _app.get("backend") == null or _app.get("registry") == null:
		return {"ok": false, "errors": ["Backend indisponível."]}

	var data := club_data.duplicate(true)
	data["name"] = check["name"]
	data["sigla"] = check["sigla"]

	var world := World.from_dict(_app.backend.load_world())
	if not world.clubs.is_empty():
		return {"ok": false, "errors": ["Já existe um clube neste mundo."]}
	if world.date.is_empty():
		world.date = Time.get_date_string_from_system(true)
	var res := OnboardingService.create_club(world, data, _app.registry, _app.backend)
	if not bool(res.get("ok", false)):
		return {"ok": false, "errors": ["Não foi possível criar o clube."]}
	return res
