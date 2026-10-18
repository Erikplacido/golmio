extends SceneTree
## Impressão digital da simulação (ver SimFingerprint). Compare entre plataformas:
##   arch -arm64  godot --headless --path jogo --script res://tests/fingerprint.gd
##   arch -x86_64 godot --headless --path jogo --script res://tests/fingerprint.gd
## Opções: --matches=3 --minutes=90 --seed=777 --write-golden (atualiza tests/golden/determinism.json)

const GOLDEN := "res://tests/golden/determinism.json"


func _init() -> void:
	var args := {"matches": "3", "minutes": "90", "seed": str(SimFingerprint.DEFAULT_SEED)}
	var write := false
	for a in OS.get_cmdline_user_args():
		if a == "--write-golden":
			write = true
			args.matches = "2"
			args.minutes = "20"
			continue
		var kv := a.trim_prefix("--").split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var reg := MechanicRegistry.new()
	reg.discover()
	reg.apply_ruleset(Ruleset.load_file("res://rulesets/default.json"))
	var fp := SimFingerprint.compute(reg, int(args.matches), float(args.minutes), int(args.seed))
	for m in fp.matches:
		print("semente %d: checksum %s  placar %s" % [m.seed, m.checksum, m.score])
	print("FINGERPRINT %s   (motor v%d, assinatura %s)" % [fp.fingerprint, fp.signature.engine, fp.signature.hash])
	if write:
		var out := {"matches": int(args.matches), "minutes": float(args.minutes), "seed": int(args.seed),
			"signature_hash": fp.signature.hash, "fingerprint": fp.fingerprint}
		var f := FileAccess.open(GOLDEN, FileAccess.WRITE)
		f.store_string(JSON.stringify(out, "  "))
		f.close()
		print("golden atualizado em %s" % GOLDEN)
	reg.dispose()
	quit()
