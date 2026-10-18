class_name ButtonPieces
extends RefCounted
## Peças de futebol de botão (assets/botoes) que representam os jogadores na partida.
## As artes são neutras (creme e cinza): a cor do time entra multiplicando a textura, então a face
## fica na cor do clube e os relevos do aro viram tons mais escuros dela.
## Estilo por time: TeamSetup/MatchTeam ext "button_style" (quando a criação de clube tiver
## escolha de peça); sem isso, DEFAULT_HOME / DEFAULT_AWAY.

const DIR := "res://assets/botoes/"
const STYLES := {
	"varzea": DIR + "ps3_0000_varzea.png",
	"tampinha": DIR + "ps3_0001_tampinha.png",
	"anel": DIR + "ps3_0002_anel.png",
	"bolacha": DIR + "ps3_0003_bolacha.png",
	"arquibancada": DIR + "ps3_0004_arquibancada.png",
	"turbina": DIR + "ps3_0005_turbina.png",
	"flutuante": DIR + "ps3_0006_flutuante.png",
	"octogno": DIR + "ps3_0007_octogno.png",
	"baquelite": DIR + "ps3_0008_baquelite.png",
	"porcelana": DIR + "ps3_0009_porcelana.png",
	"arte_deco": DIR + "ps3_0010_arte_deco.png",
	"coliseu": DIR + "ps3_0011_coliseu.png",
	"orbita": DIR + "ps3_0012_orbita.png",
	"monolito": DIR + "ps3_0013_monolito.png",
	"coroa": DIR + "ps3_0014_coroa.png",
	"disco_vinil": DIR + "ps3_0015_disco_vinil.png",
}
const DEFAULT_HOME := "coliseu"
const DEFAULT_AWAY := "turbina"
## Fração do lado da textura ocupada pelo disco (as artes têm ~20 px de margem em 491 × 478).
const DISC_FRACTION := 0.93

static var _cache := {}


static func texture(style: String) -> Texture2D:
	if _cache.has(style):
		return _cache[style]
	var path: String = STYLES.get(style, "")
	var tex: Texture2D = load(path) if path != "" and ResourceLoader.exists(path) else null
	_cache[style] = tex
	return tex


static func style_for(team: MatchTeam) -> String:
	var s := str(team.ext.get("button_style", ""))
	if STYLES.has(s):
		return s
	return DEFAULT_HOME if team.side == "home" else DEFAULT_AWAY


## Desenha a peça com centro `c` e raio visual `r` (o disco, sem a margem da textura).
## Devolve false se a textura não existe (quem chama desenha o círculo simples).
static func draw(ci: CanvasItem, style: String, c: Vector2, r: float, tint: Color) -> bool:
	var tex := texture(style)
	if tex == null:
		return false
	var ts := tex.get_size()
	var k := (r * 2.0 / DISC_FRACTION) / maxf(ts.x, ts.y)
	ci.draw_texture_rect(tex, Rect2(c - ts * k / 2.0, ts * k), false, tint)
	return true
