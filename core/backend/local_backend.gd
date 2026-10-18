class_name LocalBackend
extends Backend
## Backend offline para desenvolvimento: arquivos em res:// (leitura) e user:// (gravação).
## Argumentos de desenvolvimento (depois de `--` na linha de comando):
##   --ruleset=dev          usa res://rulesets/dev.json (mecânicas experimentais ligadas)
##   --profile=nome         save separado em user://save/nome/ (capturas e testes manuais sem
##                          tocar no save do jogador)
##   --date=AAAA-MM-DD      finge que o relógio do servidor está nesse dia (12:00 UTC)

const RULESET_PATH := "res://rulesets/default.json"
const RULESETS_DIR := "res://rulesets"
const RULESET_OVERRIDE := "user://ruleset_override.json"   # para testar regras sem editar o projeto
## Build de teste exportada com a feature "dev_ruleset" (preset Android de teste): sem linha de
## comando no celular, é assim que ela usa rulesets/dev.json, o mesmo do --ruleset=dev no desktop.
const DEV_FEATURE := "dev_ruleset"
const DEV_RULESET := "dev"
const SAVE_DIR := "user://save"
const WORLD_FILE := "world.json"
const RESULTS_FILE := "results.jsonl"
## Caminhos do perfil padrão (sem --profile).
const WORLD_PATH := SAVE_DIR + "/" + WORLD_FILE
const RESULTS_PATH := SAVE_DIR + "/" + RESULTS_FILE
## 6 bytes = 48 bits: new_seed() fica em [0, AthleteDna.SEED_LIMIT).
const SEED_BYTES := 6
## Rodadas do ajuste de força do adversário (fetch_opponent_snapshot).
const SHIFT_STEPS := 8

## Pasta do save. Mude antes de usar (testes) ou passe --profile=nome.
var save_dir := SAVE_DIR
## "" = relógio do sistema; AAAA-MM-DD fixa o dia (testes e --date).
var date_override := ""


func _init() -> void:
	var profile := _arg("profile")
	if profile.is_valid_filename() and profile != "":
		save_dir = SAVE_DIR.path_join(profile)
	date_override = _arg("date")


func world_path() -> String:
	return save_dir.path_join(WORLD_FILE)


func results_path() -> String:
	return save_dir.path_join(RESULTS_FILE)


func fetch_ruleset() -> Dictionary:
	var path := RULESET_PATH
	var named := _arg("ruleset")
	if named == "" and OS.has_feature(DEV_FEATURE):
		named = DEV_RULESET
	if named != "" and named.is_valid_filename() and FileAccess.file_exists(RULESETS_DIR.path_join(named + ".json")):
		path = RULESETS_DIR.path_join(named + ".json")
	elif FileAccess.file_exists(RULESET_OVERRIDE):
		path = RULESET_OVERRIDE
	return Ruleset.load_file(path).to_dict()


func bak_path() -> String:
	return world_path() + ".bak"


func tmp_path() -> String:
	return world_path() + ".tmp"


func load_world() -> Dictionary:
	var wp := world_path()
	var bp := bak_path()
	if FileAccess.file_exists(wp):
		var content := FileAccess.get_file_as_string(wp)
		if not content.is_empty():
			var parsed: Variant = JSON.parse_string(content)
			if parsed is Dictionary and not parsed.is_empty():
				return parsed
	# Fallback automático: se world.json não existir, for vazio ou inválido, tenta o backup
	if FileAccess.file_exists(bp):
		var bcontent := FileAccess.get_file_as_string(bp)
		if not bcontent.is_empty():
			var bparsed: Variant = JSON.parse_string(bcontent)
			if bparsed is Dictionary and not bparsed.is_empty():
				return bparsed
	return {}


func save_world(data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(save_dir)
	var wp := world_path()
	var tp := tmp_path()
	var bp := bak_path()

	var f := FileAccess.open(tp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.flush()
	f.close()

	if not FileAccess.file_exists(tp) or FileAccess.get_file_as_string(tp).is_empty():
		return false

	# Backup seguro do arquivo existente
	if FileAccess.file_exists(wp):
		DirAccess.copy_absolute(wp, bp)

	# Troca atômica do temporário para o destino final
	var err := DirAccess.rename_absolute(tp, wp)
	if err != OK:
		DirAccess.copy_absolute(tp, wp)
		DirAccess.remove_absolute(tp)
	return true


## Sem servidor, os clubes de demonstração fazem o papel dos outros jogadores. criteria:
##   club_file   clube de data/demo (padrão DemoData.AWAY_CLUB);
##   target_ovr  força desejada: os atributos do clube são deslocados para que o OVR médio dos
##               titulares fique nela, como o pareamento por força/Elo do servidor faria
##               (elo_matchmaking). Mantém as diferenças entre os atletas; limita a 1..99.
## Devolve os dados do clube no formato de data/demo (DemoData.team_setup_from_dict) + club_file.
func fetch_opponent_snapshot(criteria: Dictionary) -> Dictionary:
	var path := str(criteria.get("club_file", DemoData.AWAY_CLUB))
	var d: Variant = DemoData.read_json(path) if FileAccess.file_exists(path) else null
	if not (d is Dictionary):
		return {}
	var snap: Dictionary = (d as Dictionary).duplicate(true)
	snap["club_file"] = path
	if criteria.has("target_ovr"):
		_shift_strength(snap, float(criteria.target_ovr))
	return snap


## Desloca todos os atributos do clube pelo mesmo tanto, até a média dos titulares bater no alvo.
## Atributos presos no piso ou no teto puxam a média: repete o deslocamento com o que faltou.
static func _shift_strength(snap: Dictionary, target_ovr: float) -> void:
	var lo := AttributeCatalog.min_value()
	var hi := AttributeCatalog.max_value()
	var target := clampf(target_ovr, lo, hi)
	for _i in SHIFT_STEPS:
		var mean := _lineup_mean(snap)
		if mean < 0.0 or absf(target - mean) < 0.5:
			return
		var delta := roundf(target - mean) if absf(target - mean) >= 1.0 else signf(target - mean)
		for ad in snap.get("athletes", []):
			var attrs: Dictionary = ad.get("attributes", {})
			for k in attrs:
				attrs[k] = clampf(float(attrs[k]) + delta, lo, hi)


## Média do OVR (média dos atributos) dos titulares; -1 sem titulares.
static func _lineup_mean(snap: Dictionary) -> float:
	var lineup: Array = snap.get("lineup", [])
	var total := 0.0
	var n := 0
	for ad in snap.get("athletes", []):
		var attrs: Dictionary = ad.get("attributes", {})
		if lineup.has(ad.get("id")) and not attrs.is_empty():
			var sum := 0.0
			for k in attrs:
				sum += float(attrs[k])
			total += sum / attrs.size()
			n += 1
	return total / n if n > 0 else -1.0


func submit_match_result(result: Dictionary) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(save_dir)
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(results_path()) else FileAccess.WRITE
	var f := FileAccess.open(results_path(), mode)
	if f:
		f.seek_end()
		f.store_line(JSON.stringify(result))
	return {"accepted": true}


func fetch_match_results(club_id: String = "", limit: int = 0) -> Array:
	if not FileAccess.file_exists(results_path()):
		return []
	var out: Array = []
	var lines := FileAccess.get_file_as_string(results_path()).split("\n", false)
	for i in range(lines.size() - 1, -1, -1):
		var r: Variant = JSON.parse_string(lines[i])
		if not (r is Dictionary):
			continue
		if club_id != "" and str(r.get("home", {}).get("club_id", "")) != club_id \
				and str(r.get("away", {}).get("club_id", "")) != club_id:
			continue
		out.append(r)
		if limit > 0 and out.size() >= limit:
			break
	return out


func server_time() -> int:
	if date_override != "":
		var t := Time.get_unix_time_from_datetime_string(date_override + "T12:00:00")
		if t > 0:
			return t
	return int(Time.get_unix_time_from_system())


## 48 bits do gerador criptográfico do sistema (Crypto), em [0, 2^48).
func new_seed() -> int:
	var bytes := Crypto.new().generate_random_bytes(SEED_BYTES)
	var v := 0
	for b in bytes:
		v = (v << 8) | b
	return v


static func _arg(name: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	return ""
