class_name TestTitleScreen
extends TestCase
## Tela de abertura: camadas exportadas (assets/abertura/camadas.json) batem com o que a cena espera.


func _manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(TitleScreen.MANIFEST))


func test_camadas_exportadas_existem() -> void:
	check(FileAccess.file_exists(TitleScreen.MANIFEST), "camadas.json existe")
	var m := _manifest()
	check(not m.get("layers", []).is_empty(), "há camadas")
	for l in m.get("layers", []):
		check(ResourceLoader.exists(TitleScreen.DIR + str(l.id) + ".png"), "PNG da camada %s" % l.id)
		check(float(l.w) > 0.0 and float(l.h) > 0.0, "tamanho da camada %s" % l.id)
	check(ResourceLoader.exists(TitleScreen.LOGO), "logo existe")


func test_camadas_animadas_existem_no_manifesto() -> void:
	var ids: Array = _manifest().get("layers", []).map(func(l): return str(l.id))
	for id in TitleScreen.MOTION:
		check(ids.has(id), "camada animada '%s' está no camadas.json (renomeada no PSD?)" % id)
	check(ids.has("fundo"), "camada 'fundo' (usada nas laterais) existe")
