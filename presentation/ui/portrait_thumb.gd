class_name PortraitThumb
extends Control
## Retrato pequeno de atleta para listas (elenco, pré-jogo, resultado): quadro de papel com o
## retrato vestido com o uniforme do clube, desenhado uma vez pelo PortraitBaker (cache em disco).
## Atleta sem rosto no DNA (demonstração, elenco reserva do onboarding) mostra as iniciais sobre a
## cor do setor.

## Tamanho em que o retrato é desenhado (o cache é por tamanho: manter fixo reaproveita o PNG).
const BAKE_SIZE := Vector2i(128, 160)

var _face: Dictionary = {}
var _kit: Dictionary = {}
var _initials := ""
var _sector_color := DesignTokens.COLOR_TEXT_SECONDARY
var _tex: Texture2D


func _init(p_size: float = 48.0) -> void:
	custom_minimum_size = Vector2(p_size, p_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func set_athlete(a: Athlete, kit: Dictionary = {}) -> void:
	_face = GameStore.face_for(a)
	_kit = kit
	_sector_color = DesignTokens.color_for_position(a.position) if a else _sector_color
	_initials = ""
	if a:
		for part in a.name.split(" ", false).slice(0, 2):
			_initials += part.left(1).to_upper()
	_tex = null
	if not _face.is_empty():
		_tex = PortraitBaker.cached(_face, _kit, BAKE_SIZE)
		if _tex == null and is_inside_tree():
			_bake.call_deferred()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and _tex == null and not _face.is_empty():
		_bake.call_deferred()


func _bake() -> void:
	if not is_inside_tree() or _face.is_empty():
		return
	var face := _face
	var tex: Texture2D = await PortraitBaker.bake(face, _kit, BAKE_SIZE, self)
	if is_instance_valid(self) and face == _face and tex != null:
		_tex = tex
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(_sector_color, 0.22) if _tex == null else DesignTokens.COLOR_ACCENT_YELLOW)
	if _tex:
		# O retrato é um busto em 4:5: mostra a parte de cima (rosto e ombros) no quadrado.
		var ts := _tex.get_size()
		var src := Rect2(0, 0, ts.x, minf(ts.y, ts.x * size.y / maxf(size.x, 1.0)))
		draw_texture_rect_region(_tex, r, src)
	elif _initials != "":
		var f := DesignTokens.font(true)
		var fs := maxi(int(size.y * 0.36), 9)
		var tw := f.get_string_size(_initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2((size.x - tw) / 2.0, size.y / 2.0 + fs * 0.36), _initials,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _sector_color)
	draw_rect(r, DesignTokens.COLOR_INK, false, 2.0)
