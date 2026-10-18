class_name UiColumn
extends Container
## Coluna centralizada: cada filho ocupa a altura toda e a largura até `max_width`, no meio.
## Em telas largas o conteúdo não estica de ponta a ponta; em telas estreitas usa tudo.

@export var max_width := 980.0:
	set(v):
		max_width = v
		queue_sort()


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		var w := minf(size.x, max_width)
		var rect := Rect2(Vector2((size.x - w) / 2.0, 0.0), Vector2(w, size.y))
		for c in get_children():
			if c is Control and c.visible:
				fit_child_in_rect(c, rect)


func _get_minimum_size() -> Vector2:
	var m := Vector2.ZERO
	for c in get_children():
		if c is Control and c.visible:
			m = m.max(c.get_combined_minimum_size())
	return m
