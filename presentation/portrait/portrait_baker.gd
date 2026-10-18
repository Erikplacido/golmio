class_name PortraitBaker
extends RefCounted
## Renderiza um retrato para textura, com cache em disco (docs/RETRATOS.md 4.5):
##   user://portraits/<sha256(receita, kit normalizado, catálogo, tamanho, versão)>.png
## Abrir um pacote de 6 desenha 6 retratos uma única vez; elenco, carta, mercado e álbum reusam o
## PNG. Mudou o uniforme (transferência) ou o catálogo: a chave muda e o retrato é refeito.
## "Catálogo" aqui é PortraitCatalog.fingerprint(): o catalog.json inteiro (com o hash dos pixels
## de cada textura e os mapas do uniforme) mais as três âncoras. Recalibrar um soquete, um
## encaixe, um torso ou um braço, ou redesenhar um PNG e rodar o exportador, invalida o cache:
## corrigir uma calibração conserta todos os retratos (RETRATOS 1 e 4.7).
##
## Uso (corrotina):
##   var tex: Texture2D = await PortraitBaker.bake(face, kit, Vector2i(256, 320), self)
## `host` é qualquer nó dentro da árvore: o SubViewport temporário vira filho dele até o quadro
## ser desenhado (await RenderingServer.frame_post_draw). Se o host sair da árvore ou for
## liberado nesse meio tempo (tela fechada), bake devolve null e não grava nada no cache.

const CACHE_DIR := "user://portraits"
## Suba quando a montagem ou o shader mudarem de forma visível (invalida o cache).
## 2: mapas do uniforme pré-calculados pelo exportador; chave com a impressão digital do catálogo.
const RENDERER_VERSION := 2


## Chave de cache: SHA-256 do JSON canônico de {face, kit normalizado, versão e impressão digital
## do catálogo, tamanho, versão do renderer}.
static func cache_key(face: Dictionary, kit: Dictionary, size: Vector2i, catalog: PortraitCatalog = null) -> String:
	var cat := catalog if catalog != null else PortraitCatalog.shared()
	return AthleteDna.sha256({
		"face": face,
		"kit": UniformMaps.normalize_kit(kit),
		"catalog": cat.version,
		"catalog_fingerprint": cat.fingerprint(),
		"size": [size.x, size.y],
		"renderer": RENDERER_VERSION,
	})


static func cache_path(key: String) -> String:
	return CACHE_DIR.path_join("%s.png" % key)


## Textura do cache, ou null se ainda não foi desenhada.
static func cached(face: Dictionary, kit: Dictionary, size: Vector2i, catalog: PortraitCatalog = null) -> Texture2D:
	var path := cache_path(cache_key(face, kit, size, catalog))
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


## Desenha (ou lê do cache) o retrato em size pixels, fundo transparente.
static func bake(face: Dictionary, kit: Dictionary, size: Vector2i, host: Node, catalog: PortraitCatalog = null,
		use_cache: bool = true) -> Texture2D:
	var cat := catalog if catalog != null else PortraitCatalog.shared()
	var key := cache_key(face, kit, size, cat)
	if use_cache:
		var hit := cached(face, kit, size, cat)
		if hit != null:
			return hit
	if host == null or not host.is_inside_tree():
		push_warning("PortraitBaker: host fora da árvore; não dá para desenhar")
		return null
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var renderer := PortraitRenderer.new()
	renderer.fit_size = Vector2(size)
	renderer.setup(face, kit, cat)
	viewport.add_child(renderer)
	host.add_child(viewport)
	await RenderingServer.frame_post_draw
	# Durante o await a tela pode ter fechado: o host (e o SubViewport, filho dele) pode ter sido
	# liberado ou tirado da árvore. _capture confere antes de tocar no viewport.
	var img := _capture(viewport)
	if img == null or img.is_empty():
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	unpremultiply(img)
	if use_cache:
		DirAccess.make_dir_recursive_absolute(CACHE_DIR)
		var err := img.save_png(cache_path(key))
		if err != OK:
			push_warning("PortraitBaker: não salvou %s (%s)" % [cache_path(key), error_string(err)])
	return ImageTexture.create_from_image(img)


## O SubViewport transparente guarda cor x alfa nas bordas semitransparentes (mistura sobre
## preto transparente); divide de volta para o PNG ter alfa "reto" e não escurecer as bordas.
static func unpremultiply(img: Image) -> void:
	var data := img.get_data()
	var n := data.size()
	var i := 3
	while i < n:
		var a := data[i]
		if a > 0 and a < 255:
			var f := 255.0 / a
			data[i - 3] = mini(255, roundi(data[i - 3] * f))
			data[i - 2] = mini(255, roundi(data[i - 2] * f))
			data[i - 1] = mini(255, roundi(data[i - 1] * f))
		i += 4
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)


## Lê o quadro desenhado no SubViewport e o descarta. null (sem erro) se o viewport já foi
## liberado (o host foi liberado junto) ou está fora da árvore (não foi desenhado).
static func _capture(viewport: Variant) -> Image:
	if not is_instance_valid(viewport):
		return null
	var vp := viewport as SubViewport
	if vp == null:
		return null
	var img: Image = vp.get_texture().get_image() if vp.is_inside_tree() else null
	var parent := vp.get_parent()
	if parent != null:
		parent.remove_child(vp)
	vp.queue_free()
	return img


## Apaga o cache em disco (ex.: catálogo novo).
static func clear_cache() -> void:
	var dir := DirAccess.open(CACHE_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".png"):
			dir.remove(f)
