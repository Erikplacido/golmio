class_name UiScaledFrame
extends Control
## Moldura de leitura para telas FORA da casca (rotas de tela cheia: criação do clube, pacote
## inicial, primeira escalação). Faz o mesmo que o _frame do AppShell: amplia o conteúdo por
## Settings.readability_scale() e desconta as margens seguras (entalhe, barra de gestos).
## Sem ela, num celular em retrato o layout de 1100 px lógicos é encolhido para caber em ~390 pt
## e o texto fica ilegível.
##
## Os filhos ancoram em PRESET_FULL_RECT e enxergam o tamanho LÓGICO (logical_size()); a decisão
## de layout (compacto/expandido) deve usar esse tamanho, não o do viewport.

signal logical_resized(logical: Vector2)

var k := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	get_viewport().size_changed.connect(_layout)
	var settings := get_node_or_null("/root/Settings")
	if settings:
		settings.changed.connect(func(key: String, _v: Variant) -> void:
			if key in ["ui_scale", "aspect"]:
				_layout.call_deferred()
		)
	_layout()


func _process(_delta: float) -> void:
	# A escala de leitura depende da janela e da densidade da tela: muda ao girar ou trocar de monitor.
	if not is_equal_approx(_read_k(), k):
		_layout()


func logical_size() -> Vector2:
	return size


func _read_k() -> float:
	var s := get_node_or_null("/root/Settings")
	return s.readability_scale() if s else 1.0


func _layout() -> void:
	if not is_inside_tree():
		return
	k = _read_k()
	var s := get_node_or_null("/root/Settings")
	var safe: Vector4 = s.safe_margins() if s else Vector4.ZERO
	var vp := get_viewport_rect().size
	position = Vector2(safe.x, safe.y)
	scale = Vector2(k, k)
	var logical := (vp - Vector2(safe.x + safe.z, safe.y + safe.w)) / k
	if not size.is_equal_approx(logical):
		size = logical
		logical_resized.emit(logical)
