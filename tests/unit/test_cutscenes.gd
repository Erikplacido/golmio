class_name TestCutscenes
extends TestCase
## Valida o carregamento dos assets e mapeamento de cutscenes/vinhetas de lances.


func test_assets_placeholders_existem() -> void:
	var dir := "res://assets/cutscenes/"
	check(FileAccess.file_exists(dir + "placeholder_cutscene.png"), "placeholder padrão PNG existe")
	check(FileAccess.file_exists(dir + "foul_yellow.png"), "placeholder foul_yellow existe")
	check(FileAccess.file_exists(dir + "foul_red.png"), "placeholder foul_red existe")
	check(FileAccess.file_exists(dir + "penalty.png"), "placeholder penalty existe")
	check(FileAccess.file_exists(dir + "throw_in.png"), "placeholder throw_in existe")
	check(FileAccess.file_exists(dir + "corner.png"), "placeholder corner existe")
	check(FileAccess.file_exists(dir + "goal.png"), "placeholder goal existe")
	check(FileAccess.file_exists(dir + "save.png"), "placeholder save existe")
	check(FileAccess.file_exists(dir + "offside.png"), "placeholder offside existe")


func test_overlay_mapeia_eventos_corretamente() -> void:
	var overlay := CutsceneOverlay.new()
	check(overlay.ASSET_MAP.has("foul_yellow"), "mapeia foul_yellow")
	check(overlay.ASSET_MAP.has("foul_red"), "mapeia foul_red")
	check(overlay.ASSET_MAP.has("penalty"), "mapeia penalty")
	check(overlay.ASSET_MAP.has("throw_in"), "mapeia throw_in")
	check(overlay.ASSET_MAP.has("corner"), "mapeia corner")
	check(overlay.ASSET_MAP.has("goal"), "mapeia goal")
	check(overlay.ASSET_MAP.has("save"), "mapeia save")
	check(overlay.ASSET_MAP.has("offside"), "mapeia offside")
	overlay.free()
