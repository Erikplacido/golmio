class_name UiSegmented
extends Container
## Fileira do controle segmentado (UiKit.segmented). Com espaço, uma linha que reparte a largura
## como um HBox (o desktop não muda). Quando a soma das larguras naturais não cabe (celular em
## retrato, ~360 px lógicos), quebra em linhas equilibradas (5 abas -> 3 + 2) em vez de empurrar a
## tela para fora da borda direita.

var separation := DesignTokens.SPACING_XS:
	set(v):
		separation = v
		queue_sort()

var _reported_h := -1.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		var y := 0.0
		for line in _lines(size.x):
			var h := 0.0
			for c: Control in line:
				h = maxf(h, c.get_combined_minimum_size().y)
			var widths := _share(line, size.x)
			var x := 0.0
			for i in line.size():
				fit_child_in_rect(line[i], Rect2(x, y, widths[i], h))
				x += widths[i] + separation
			y += h + separation
		# A altura depende da largura: avisa o pai quando o número de linhas muda.
		if not is_equal_approx(y - separation if y > 0.0 else 0.0, _reported_h):
			update_minimum_size()


func _get_minimum_size() -> Vector2:
	var w := 0.0
	for c in _items():
		w = maxf(w, c.get_combined_minimum_size().x)
	_reported_h = _height(size.x)
	return Vector2(w, _reported_h)


func _items() -> Array[Control]:
	var out: Array[Control] = []
	for c in get_children():
		if c is Control and (c as Control).visible and not (c as Control).top_level:
			out.append(c)
	return out


## Menos linhas possível; as linhas têm o mesmo número de itens (a última pode ter menos).
func _lines(width: float) -> Array:
	var items := _items()
	var n := items.size()
	if n == 0:
		return []
	for rows in range(1, n + 1):
		var cols := ceili(float(n) / rows)
		var lines := []
		var fits := true
		for start in range(0, n, cols):
			var line := items.slice(start, mini(start + cols, n))
			var need := separation * (line.size() - 1)
			for c: Control in line:
				need += c.get_combined_minimum_size().x
			fits = fits and (width <= 0.0 or need <= width + 0.5)
			lines.append(line)
		if fits:
			return lines
	return items.map(func(c: Control) -> Array: return [c])


func _height(width: float) -> float:
	var lines := _lines(width)
	var h := separation * maxf(lines.size() - 1, 0)
	for line in lines:
		var lh := 0.0
		for c: Control in line:
			lh = maxf(lh, c.get_combined_minimum_size().y)
		h += lh
	return h


## Reparte a linha como o BoxContainer com todos expandindo: partes iguais, e quem não cabe na
## parte fica com o próprio mínimo.
func _share(line: Array, width: float) -> Array:
	var free := width - separation * (line.size() - 1)
	var fixed := {}
	var share := 0.0
	while true:
		var flexible := line.size() - fixed.size()
		share = free / maxf(flexible, 1)
		var changed := false
		for i in line.size():
			if not fixed.has(i) and (line[i] as Control).get_combined_minimum_size().x > share:
				fixed[i] = true
				free -= (line[i] as Control).get_combined_minimum_size().x
				changed = true
		if not changed or fixed.size() == line.size():
			break
	var out := []
	for i in line.size():
		out.append((line[i] as Control).get_combined_minimum_size().x if fixed.has(i) else share)
	return out
