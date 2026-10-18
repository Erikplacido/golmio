extends SceneTree
## Executa todos os tests/unit/test_*.gd sem abrir janela.
##   godot --headless --path jogo --script res://tests/run_tests.gd
## (ou ./tests/run.sh, que também falha se houver SCRIPT ERROR no log)
## Para rodar só alguns arquivos: -- --only=test_packs,test_athlete (trechos do nome do arquivo).

func _init() -> void:
	var dir := "res://tests/unit"
	var only := _only_filter()
	var files := Array(DirAccess.get_files_at(dir)).filter(func(f): return f.begins_with("test_") and f.ends_with(".gd") \
		and (only.is_empty() or only.any(func(o): return f.contains(o))))
	files.sort()
	var total := 0
	var failed := 0
	var t0 := Time.get_ticks_msec()
	for f in files:
		var script: Script = load(dir.path_join(f))
		for m in script.get_script_method_list():
			if not str(m.name).begins_with("test_"):
				continue
			var inst: TestCase = script.new()
			var t := Time.get_ticks_msec()
			inst.call(m.name)
			total += 1
			var ms := Time.get_ticks_msec() - t
			if inst.failures.is_empty():
				print("  ok    %s :: %s  (%d ms)" % [f.get_basename(), m.name, ms])
			else:
				failed += 1
				print("  FALHA %s :: %s" % [f.get_basename(), m.name])
				for msg in inst.failures:
					print("        - %s" % msg)
	print("\n%d testes, %d falhas (%.1f s)" % [total, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if failed > 0 else 0)


func _only_filter() -> Array:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			return Array(arg.trim_prefix("--only=").split(",", false))
	return []
