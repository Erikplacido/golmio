class_name CreateClubScreen
extends Control
## O01 · Criar clube (tela cheia): a tela de criação (ClubCreationView) ligada ao onboarding. Ao
## salvar, o OnboardingController cria o clube com os atletas iniciais e grava o mundo; daqui a
## estreia guiada segue para o pacote inicial (O02). Não há para onde voltar antes de ter clube.

const CLUB_CREATION := "res://presentation/club_creation/club_creation_view.tscn"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiFrames.paper_background())
	# Tela cheia fica fora da casca: a moldura amplia para leitura (no celular a view cai no
	# layout compacto, que decide pelo tamanho lógico).
	var frame := UiScaledFrame.new()
	add_child(frame)
	var view: Control = load(CLUB_CREATION).instantiate()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_child(view)
	var ctrl := OnboardingController.attach(view, get_node_or_null("/root/App"))
	ctrl.next_scene = ""
	ctrl.completed.connect(_on_completed)


func _on_completed(_club: Club) -> void:
	var game := get_node_or_null("/root/Game")
	if game:
		game.reload()
		game.start_onboarding()
	var router := get_node_or_null("/root/Router")
	if router:
		router.go("starter_pack")


## Sem clube não há tela anterior: o voltar não sai daqui.
func handle_back() -> bool:
	return true
