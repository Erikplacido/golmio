class_name ShopScreen
extends ScreenBase
## L01 · Loja: cosméticos por créditos, sempre sem efeito esportivo. Enquanto a mecânica cosmetics
## (Fase 6) não existe, a tela diz o que vai ter e reforça a regra: nada de atletas, pacotes ou
## moedas por dinheiro, sem contagem regressiva nem "só hoje" inventado.

const CATEGORIES := [["LOJA_BOTOES", "clube"], ["LOJA_UNIFORMES", "uniforme"], ["LOJA_CAMPOS", "estadio"],
	["LOJA_REDES", "gol"], ["LOJA_MOLDURAS", "colecao"]]


func refresh() -> void:
	ScreenBase.clear(content)
	var rule := UiKit.card(Color("#e3f0f6"), "ui_aviso")
	var rh := UiKit.hbox(DesignTokens.SPACING_SM)
	rh.add_child(UiKit.icon("confirmar", 28))
	rh.add_child(UiKit.label(tr("LOJA_SEM_BONUS"), UiKit.FONT_BODY, UiKit.INK, true))
	rule.add_child(rh)
	content.add_child(rule)
	var cats := HFlowContainer.new()
	cats.add_theme_constant_override("h_separation", DesignTokens.SPACING_SM)
	cats.add_theme_constant_override("v_separation", DesignTokens.SPACING_SM)
	for c in CATEGORIES:
		cats.add_child(UiKit.chip(tr(c[0]), UiKit.BLUE, c[1]))
	content.add_child(cats)
	content.add_child(UiKit.empty_state("loja", tr("LOJA_EM_BREVE"), tr("LOJA_EM_BREVE_TEXTO")))
	show_ready()
