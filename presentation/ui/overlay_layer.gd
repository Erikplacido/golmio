class_name OverlayLayer
extends CanvasLayer
## Sobreposições do sistema (S07) num padrão único, por cima de qualquer cena (o Router é o dono):
##   - modal(): janela com título, texto e ações; o botão destrutivo fica à direita, vermelho, e
##     nunca recebe o foco inicial;
##   - confirm(): atalho de modal com Cancelar + confirmar;
##   - toast(): aviso no rodapé; sucesso e informação somem em TOAST_SECONDS, erro fica até fechar;
##   - coach(): dica guiada com destaque (CoachMark).
## Tudo é ampliado por Settings.readability_scale() em telas pequenas, como o HUD da partida.

signal modal_closed(id: int)

const TOAST_SECONDS := 4.0
const MODAL_MAX_W := 460.0
const DIM := Color(0, 0, 0, 0.5)

var _root: Control
var _modals: Array = []        # [{id, node, on_cancel}]
var _toasts: VBoxContainer
var _coach: CoachMark
var _next_id := 0


func _ready() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = DesignTokens.base_theme()
	add_child(_root)
	_toasts = VBoxContainer.new()
	_toasts.name = "Toasts"
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_theme_constant_override("separation", DesignTokens.SPACING_SM)
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(_toasts)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _process(_delta: float) -> void:
	# A escala de leitura muda com a janela e com as configurações: confere a cada quadro (barato).
	if _root and not is_equal_approx(_root.scale.x, _scale()):
		_layout()


func _scale() -> float:
	var s := get_node_or_null("/root/Settings")
	return s.readability_scale() if s else 1.0


func _layout() -> void:
	if _root == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var k := _scale()
	_root.scale = Vector2(k, k)
	_root.size = vp / k
	_toasts.position = Vector2(16, 0)
	_toasts.size = Vector2(_root.size.x - 32, _root.size.y - 24)
	for m in _modals:
		_fit_modal(m.node)
	if _coach:
		_coach.size = _root.size
		_coach.queue_redraw()


## Área lógica das sobreposições (viewport / escala de leitura).
func logical_size() -> Vector2:
	return _root.size if _root else Vector2.ZERO


func logical_scale() -> float:
	return _root.scale.x if _root else 1.0


# --- modais ---------------------------------------------------------------------------------

## actions: [{label, kind ("primary"|"secondary"|"destructive"|"info"), callback (opcional),
## cancel: true (é o "cancelar": Esc/voltar chamam ele)}]. Toda ação fecha o modal.
## `body`: controles próprios abaixo do texto (janelas de filtro, opções); ocupam a largura toda.
## Um `body` ScrollContainer cresce até mostrar o conteúdo inteiro; só rola se nem a tela toda bastar.
func modal(heading: String, text: String, actions: Array, icon_id: String = "", body: Control = null) -> int:
	_next_id += 1
	var id := _next_id
	var dim := ColorRect.new()
	dim.color = DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "Modal"
	panel.add_theme_stylebox_override("panel", DesignTokens.style_window())
	dim.add_child(panel)
	var v := UiKit.vbox(DesignTokens.SPACING_MD)
	panel.add_child(v)
	var head := UiKit.hbox(DesignTokens.SPACING_SM)
	if icon_id != "" and GameIcons.has(icon_id):
		head.add_child(GameIcons.rect(icon_id, 30))
	var t := UiKit.title(heading)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	v.add_child(head)
	if text != "":
		var body_label := UiKit.label(text, UiKit.FONT_BODY, UiKit.INK, true)
		body_label.name = "Body"
		v.add_child(body_label)
	if body != null:
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(body)
		if body is ScrollContainer and body.get_child_count() > 0:
			body.set_meta("fit_content", true)
			# Texto que quebra linha muda de altura depois do layout: reajusta a janela.
			(body.get_child(0) as Control).minimum_size_changed.connect(func() -> void:
				_fit_modal.call_deferred(dim))
	var row := UiKit.hbox(DesignTokens.SPACING_SM)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	var on_cancel := Callable()
	var focus_target: Button = null
	# Destrutivo sempre à direita: os outros primeiro, na ordem dada.
	var ordered := actions.filter(func(a): return str(a.get("kind", "")) != "destructive")
	ordered.append_array(actions.filter(func(a): return str(a.get("kind", "")) == "destructive"))
	for a in ordered:
		var kind := str(a.get("kind", "secondary"))
		var b := UiKit.button(str(a.get("label", "")), kind)
		b.custom_minimum_size.x = 120
		var cb: Callable = a.get("callback", Callable())
		b.pressed.connect(func() -> void:
			close(id)
			if cb.is_valid():
				cb.call()
		)
		row.add_child(b)
		if bool(a.get("cancel", false)):
			on_cancel = cb if cb.is_valid() else Callable()
		if kind != "destructive" and focus_target == null:
			focus_target = b
	_modals.append({"id": id, "node": dim, "on_cancel": on_cancel})
	# A altura de texto com quebra de linha só sai depois de um passo de layout: mede de novo no
	# quadro seguinte, com o painel invisível até lá.
	panel.modulate.a = 0.0
	_fit_modal(dim)
	_settle_modal.call_deferred(dim)
	if focus_target:
		focus_target.grab_focus.call_deferred()
	return id


func _fit_modal(dim: Control) -> void:
	var panel: Control = dim.get_node_or_null("Modal")
	if panel == null:
		return
	var w := minf(MODAL_MAX_W, _root.size.x - 32.0)
	panel.custom_minimum_size.x = w
	# Texto que quebra linha: a altura mínima depende da largura; dá a largura certa antes de medir.
	var inner := w - 48.0
	# Dentro de um `body` rolável a largura já vem da rolagem (e os cartões têm margem própria).
	for l in panel.find_children("*", "Label", true, false):
		if (l as Label).autowrap_mode != TextServer.AUTOWRAP_OFF and not _in_scroll(l, panel):
			(l as Label).custom_minimum_size.x = inner
	# Corpo rolável: altura do conteúdo, limitada ao que sobra da tela (margem de 12 em cima e embaixo).
	var fits: Array = panel.find_children("*", "ScrollContainer", true, false).filter(
		func(s: Node) -> bool: return s.has_meta("fit_content"))
	for s: ScrollContainer in fits:
		s.custom_minimum_size.y = 0.0
	panel.size = Vector2(w, 0)
	var sz := panel.get_combined_minimum_size()
	for s: ScrollContainer in fits:
		var want := (s.get_child(0) as Control).get_combined_minimum_size().y
		var room := _root.size.y - 24.0 - sz.y
		s.custom_minimum_size.y = clampf(want, 0.0, maxf(room, 120.0))
		sz = panel.get_combined_minimum_size()
	panel.size = Vector2(w, sz.y)
	panel.position = (_root.size - panel.size) / 2.0


static func _in_scroll(n: Node, stop: Node) -> bool:
	var p := n.get_parent()
	while p != null and p != stop:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func _settle_modal(dim: Control) -> void:
	if not is_instance_valid(dim):
		return
	_fit_modal(dim)
	var panel: Control = dim.get_node_or_null("Modal")
	if panel:
		panel.modulate.a = 1.0


## Cancelar + confirmar. `destructive`: confirmar em vermelho (ação irreversível).
func confirm(heading: String, text: String, confirm_label: String, on_confirm: Callable,
		destructive: bool = false, cancel_label: String = "", on_cancel: Callable = Callable()) -> int:
	return modal(heading, text, [
		{"label": cancel_label if cancel_label != "" else tr("UI_CANCELAR"), "kind": "secondary", "cancel": true, "callback": on_cancel},
		{"label": confirm_label, "kind": "destructive" if destructive else "primary", "callback": on_confirm},
	], "bloqueado" if destructive else "")


func has_modal() -> bool:
	return not _modals.is_empty()


func close(id: int) -> void:
	for i in range(_modals.size() - 1, -1, -1):
		if _modals[i].id == id:
			_modals[i].node.queue_free()
			_modals.remove_at(i)
			modal_closed.emit(id)
			return


## Fecha o que estiver por cima (modal ou dica guiada), como "cancelar". false se não havia nada.
func close_top() -> bool:
	if not _modals.is_empty():
		var m: Dictionary = _modals.back()
		close(m.id)
		var cb: Callable = m.on_cancel
		if cb.is_valid():
			cb.call()
		return true
	if _coach:
		_coach.skip()
		return true
	return false


## Remove tudo (troca de cena).
func clear() -> void:
	for m in _modals:
		m.node.queue_free()
	_modals.clear()
	if _coach:
		_coach.queue_free()
		_coach = null
	if _toasts:
		for t in _toasts.get_children():
			t.queue_free()


# --- toasts ---------------------------------------------------------------------------------

## kind: "success" | "info" | "error". Erro fica até ser fechado (toque).
func toast(text: String, kind: String = "success") -> void:
	if _toasts == null:
		return
	var color: Color = {"success": UiKit.GREEN, "error": UiKit.RED}.get(kind, UiKit.BLUE)
	var p := UiKit.card(DesignTokens.COLOR_BG_CARD, "ui_aviso")
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var h := UiKit.hbox(DesignTokens.SPACING_SM)
	p.add_child(h)
	var mark := ColorRect.new()
	mark.color = color
	mark.custom_minimum_size = Vector2(6, 24)
	h.add_child(mark)
	h.add_child(GameIcons.rect({"success": "confirmar", "error": "fechar"}.get(kind, "historico"), 22))
	var l := UiKit.label(text, UiKit.FONT_BODY, UiKit.INK, true)
	l.custom_minimum_size.x = minf(420.0, _root.size.x - 120.0)
	h.add_child(l)
	_toasts.add_child(p)
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			p.queue_free()
	)
	if kind != "error":
		get_tree().create_timer(TOAST_SECONDS, true).timeout.connect(func() -> void:
			if is_instance_valid(p):
				p.queue_free()
		)


# --- dica guiada ------------------------------------------------------------------------------

## steps: [{target: Control (ou Rect2 em coordenadas do viewport), title, text}]. Máximo 3 passos,
## sempre puláveis. `on_done(skipped)` ao terminar.
func coach(steps: Array, on_done: Callable = Callable()) -> CoachMark:
	if _coach:
		_coach.queue_free()
	_coach = CoachMark.new()
	_coach.size = _root.size
	_root.add_child(_coach)
	_coach.finished.connect(func(skipped: bool) -> void:
		_coach = null
		if on_done.is_valid():
			on_done.call(skipped)
	)
	_coach.start(steps.slice(0, CoachMark.MAX_STEPS), self)
	return _coach


func has_coach() -> bool:
	return _coach != null
