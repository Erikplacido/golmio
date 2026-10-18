# FOTEBA — projeto Godot

Godot **4.7** · GDScript · renderer Compatibility (roda em desktop, mobile e web).

## Rodar

- **Editor:** abra `jogo/project.godot` no Godot. A cena principal é o boot: abertura e depois a estreia guiada (sem clube) ou o Início (com clube). Cada tela também abre sozinha com F6.
- **Linha de comando:**

  ```bash
  godot --path jogo
  ```

- **Teclas da partida:** `Espaço` pausa · `9` (¼×), `0` (½×) e `1` a `5` velocidade (1x = 90 min em 150 s; ½× em 5 min; ¼× em 10 min) · `C` pula para o próximo lance crítico · `P` replay · `V` vinhetas · `F10` configurações. Na partida do seu clube: `F` vê o resultado e `Esc` pergunta antes de sair. Na de demonstração (cena aberta sozinha): `T` táticas, `R` nova partida, `S` laboratório. Em telas de toque, os mesmos comandos ficam numa barra no rodapé.
- **Regras de desenvolvimento** (`dev.json`: pacotes, gerador de atletas, oficial diário...): `godot --path jogo -- --ruleset=dev`.

## Telas e navegação

O app segue o [`docs/PLANO_DE_TELAS.md`](../docs/PLANO_DE_TELAS.md): uma casca (`presentation/shell/app_shell.tscn`) com barra superior e os cinco destinos (Início, Elenco, Coleção, Clube, Loja), que viram barra inferior no celular em retrato, trilho no celular deitado e abas no topo no desktop. Cada aba guarda a própria pilha; `Esc` (ou o voltar do Android) desfaz o último passo.

| Peça | Onde | Para quê |
|---|---|---|
| `Router` (autoload) | `presentation/shell/router.gd`, rotas em `routes.gd` | `Router.go("athlete", {"id": ...})`, `back()`, `switch_tab()`, `open_link("foteba://atleta/<id>")`; modal, toast e dica guiada em `Router.overlays` |
| `Game` (autoload) | `presentation/state/game_store.gd` | O estado do jogador para as telas: clube, elenco, tática, força, oficial do dia, histórico; prepara e registra partidas (uma vez só) e guarda a etapa da estreia |
| `ScreenBase` + `UiKit` | `presentation/ui/` | Base das telas (5 estados: carregando, vazio, erro, offline, pronto) e kit de componentes Golmio |

Telas: Início e Modos (`home/`), Pré-jogo (`prematch/`), Resultado (`result/`), Elenco e Ficha (`squad/`), Escalação (`tactics/`), Coleção (`collection/`), Clube (`club/`), Loja (`shop/`) e a estreia (`onboarding/`: criar clube, pacote inicial, primeira escalação). A partida (`match_view/`) usa o clube do jogador quando vem do Pré-jogo, com intervalo e fim de jogo; aberta sozinha, continua a demonstração Rubro × Anil.

Tela nova: estenda `ScreenBase`, monte em `build()`/`refresh()` com `UiKit`, ponha a cena em `Routes.TABLE` e os textos em `i18n/termos.csv` (o `test_ui_texts` barra texto fixo).

Argumentos de desenvolvimento (depois de `--`): `--route=<id>` ou `--link=foteba://...` abrem uma tela direto; `--profile=<nome>` usa um save separado em `user://save/<nome>/`; `--date=AAAA-MM-DD` fixa o relógio do servidor (o oficial libera no dia seguinte).

Capturas de todas as telas nas quatro resoluções de referência (390×844, 844×390, 1280×800 e 1920×1080), num perfil próprio que não toca no seu save:

```bash
./tools/capturar_telas.sh /tmp/telas
```

## Configurações do jogador

Painel global (autoload `Settings`): engrenagem no cabeçalho de cada tela (ou flutuante no canto), barra de toque da partida ou `F10`. `F11`/`Alt+Enter` alternam tela cheia. Tudo vale na hora e fica em `user://settings.cfg` (no navegador, no armazenamento do site). Nada disso entra na simulação nem no save do mundo.

| Aba | Opções |
|---|---|
| Tela | modo (janela, maximizada, tela cheia, exclusiva), tamanho da janela, monitor, ajuste à tela (preencher/manter proporção), escala da interface, orientação (celular) |
| Desempenho | V-Sync, limite de FPS, MSAA 2D, economia de bateria, contador de FPS |
| Partida | velocidade inicial, vinhetas e duração, replay no lance crítico, pausar ao sair do jogo |
| Controles | barra de toque e dicas de teclado (automático/sempre/nunca), lista de atalhos |
| Áudio | volumes geral, música e efeitos (barramentos `Music` e `SFX`), silenciar, silenciar em segundo plano |
| Acessibilidade | reduzir movimento, marcadores de time que não dependem de cor |

Só aparece o que a plataforma suporta (ex.: navegador não tem tamanho de janela nem V-Sync; app de celular é sempre tela cheia). Mudanças de janela no desktop voltam sozinhas em 12 s se não forem confirmadas.

Formatos de tela: `aspect="expand"` sobre a base 1100×720, então ultrawide, 4:3, retrato e celulares usam a área toda. A partida encaixa o campo na área livre e o gira em telas altas; painel, HUD e barra de toque crescem em telas que encolhem o layout (`Settings.readability_scale()`). Celular em retrato vê um aviso para girar o aparelho. Telas novas: ancore no `PRESET_FULL_RECT` e, se tiverem botão de opções próprio (`GearButton`), entrem no grupo `settings_button_host`.

Capturas para conferir layouts (desenham de verdade, sem `--headless`; `--set` não salva nada):

```bash
godot --path . --resolution 390x844 res://presentation/match_view/match_view.tscn -- --shot=/tmp/partida.png --set=touch_controls=on
godot --path . --resolution 1280x800 res://presentation/tactics/tactics_view.tscn -- --shot=/tmp/painel.png --shot-panel=display
```

## Identidade visual (Golmio) e peças de interface

Tema claro em papel creme. Paleta oficial em `tools/tokens.ase`, aplicada em `presentation/theme/design_tokens.gd` (os tons que não estão no arquivo são marcados como "derivado"). Telas novas: `theme = DesignTokens.base_theme()` na raiz e `UiFrames.paper_background()` como fundo.

Peças desenhadas (botões, painéis, campos, chips, barras, interruptores, papel):

1. Abra `../visuais/ui/ui_template.psd` e pinte na camada **arte** de cada grupo. As guias rosa são os cortes 9-slice: os cantos ficam fixos e o miolo estica. Peças com cor (botões, painéis, chips) têm o preenchimento **branco**, porque o jogo aplica a cor; contorno e sombra ficam em tinta preta. Sem texto nem ícone dentro das peças.
2. Salve e dê dois cliques em `../visuais/ui/Exportar UI.command`: gera `assets/ui/<peça>@2x.png` e `assets/ui/ui_frames.json` e reimporta com mipmaps.

Medidas, fatias e margens: `../visuais/ui/ui_manifest.jsxinc` (mudou algo, rode `criar_template_ui.jsx` para um template novo). No jogo, `UiFrames` desenha as molduras com os cantos em meia escala (a arte é @2x); sem uma peça, `DesignTokens` usa a versão desenhada por código.

Tela de abertura (`presentation/title/`): as camadas de `assets/Estádio iluminado, gramado e torcida.tif` são exportadas por `../visuais/abertura/Exportar Abertura.command` para `assets/abertura/` (PNG por camada + `camadas.json` com as posições); o logo é `assets/Logo GOL MIO com acabamento artesanal.png`. Camada nova ou renomeada: ajuste `LAYER_IDS` no `exportar_abertura.jsx` e `TitleScreen.MOTION`. Som ambiente opcional: `assets/audio/torcida_loop.ogg`. Pular a abertura: `-- --skip-intro` (ou `?skip` na URL).

Campos de partida: `../visuais/campo/` (mesmo fluxo, `Exportar Campo.command`; campos novos entram em `presentation/match_view/pitch_skins.gd`).

## Testar

```bash
./tests/run.sh
```

Esse script faz a importação e roda a suíte headless: contrato das mecânicas, determinismo, golden, memória etc.

Balanceamento em paralelo, com metas reais ao lado:

```bash
./tests/balance.sh 96
```

Com ajustes sem editar arquivos:

```bash
./tests/balance.sh 96 "--set=shot_prob_far=0.2,cross_prob=0.15"
```

Impressão digital de determinismo (tem que ser igual em toda plataforma):

```bash
godot --headless --path . --script res://tests/fingerprint.gd
```

## Retratos, figurinhas e pacotes

As mecânicas `athlete_generator` e `packs` são experimentais: ficam ligadas só em `rulesets/dev.json`. Detalhes em [`../docs/RETRATOS.md`](../docs/RETRATOS.md), seções 4, 6, 7 e 9 (molduras).

Os comandos abaixo desenham de verdade, então **não use `--headless`**.

Tela de demonstração da abertura de pacotes (inventário, prévia com probabilidades, revelação e elenco):

```bash
godot --path . res://presentation/packs/pack_opening_view.tscn
godot --path . res://presentation/packs/pack_opening_view.tscn -- --snapshot=/tmp/pacote.png --seed=25 --pack=gol
```

Opções do snapshot: `--screen=reveal|squad|inventory` e `--fill-squad` (elenco cheio).

Ritual de abertura GOLMIO (protótipo 2.5D, `PackRitual`): o pacote é aberto no servidor antes da animação; Pular, Repetir e Ensaio (troca só o nível desenhado) não geram recompensa. Camadas em `assets/packs/`, exportadas de `../visuais/pacote_*.png` por `python3 visuais/exportar_pacote.py`.

```bash
godot --path . res://presentation/packs/pack_ritual_demo.tscn
godot --path . res://presentation/packs/pack_ritual_demo.tscn -- --seed=25 --tier=deus --sheet=/tmp/ritual.png
```

Opções: `--pack=comum|raro|gol`, `--tier=bronze..deus` (ensaio), `--speed=0.5`, `--frame=<png> --at=<s>`.

Conferência visual:

```bash
# grade de retratos com kits variados; --collar-blend=1 usa a gola da web
godot --path . --script res://tools/portrait_snapshot.gd -- --out=/tmp/retratos.png
# 12 atletas do gerador real, de Bronze a Deus, como figurinhas
godot --path . --script res://tools/athlete_sheet.gd -- --out=/tmp/folha_atletas.png
# o mesmo atleta nas 6 molduras (normal, raro, lendário, mítico, divino, estrela convidada)
godot --path . --script res://tools/card_frames_sheet.gd -- --out=/tmp/molduras.png
```

Mudou uma moldura no `../visuais/card_studio.html` (o `card_config.json` ou um `card_*.png`)? Republique as molduras (precisa de Pillow). Com imagem nova, importe no Godot e rode de novo para ligar os mipmaps:

```bash
python3 visuais/exportar_cards.py
```

Mudou uma peça, um encaixe ou uma calibração em `../visuais/`? Republique o catálogo (texturas, mapas do uniforme de torsos e braços, âncoras; precisa de Pillow e NumPy) e o golden de paridade (a partir da raiz do repositório). O `content_hash` do catálogo cobre calibrações e pixels, então o golden sempre precisa ser regenerado depois, e o cache de retratos (`PortraitBaker`) se invalida sozinho:

```bash
python3 visuais/exportar_catalogo.py
node visuais/gerar_paridade_layout.js
```

Peça nova: rode o exportador, depois `godot --headless --path jogo --import`, o exportador de novo (liga os mipmaps) e outro import.

## Mapa

| Pasta | Conteúdo |
|---|---|
| `core/` | Núcleo: motor de partida, modelo de dados, hooks, registro de mecânicas, ruleset, save, backend |
| `mechanics/` | Mecânicas plugáveis. Veja [`mechanics/README.md`](mechanics/README.md) |
| `rulesets/` | Quais mecânicas estão ligadas e com quais parâmetros |
| `data/` | Atributos, formações, clubes de demonstração (nomes fictícios), catálogo de retratos (`portraits/`), níveis das molduras (`cards/card_config.json`) |
| `assets/` | Peças dos retratos (`portraits/`) e molduras das figurinhas (`cards/`) exportadas de `../visuais/` (não edite à mão: rode os exportadores) |
| `presentation/` | Cenas e interface: casca e rotas (`shell/`), estado do jogador (`state/`), kit (`ui/`), telas (`home/`, `prematch/`, `result/`, `squad/`, `club/`, `collection/`, `shop/`, `onboarding/`), partida, retratos (`portrait/`), pacotes e figurinhas (`packs/`) |
| `tools/` | Snapshots para conferência visual e capturas das telas (`capturar_telas.sh`) |
| `tests/` | Suíte headless, fixtures, goldens e balanceamento |

Arquitetura: [`../docs/ARQUITETURA.md`](../docs/ARQUITETURA.md) · GDD: [`../docs/GDD_v1.5.md`](../docs/GDD_v1.5.md) · Catálogo: [`../docs/MECANICAS.md`](../docs/MECANICAS.md)

## Exportação

O preset **Web** já vem configurado em `export_presets.cfg`: sem threads, então roda em qualquer servidor estático sem cabeçalhos COOP/COEP. Ele já exclui `tests/*` e `mechanics/_template/*` e inclui `*.json`.

Para exportar:

```bash
godot --headless --path . --export-release "Web" ../build/web/index.html
```

Para testar localmente, sirva a pasta:

```bash
python3 -m http.server 8060 --directory ../build/web
```

Depois abra `http://localhost:8060`. Com `?diag` na URL, o jogo abre o diagnóstico de determinismo em vez da partida.

Os templates de exportação 4.7.2 estão instalados em `~/Library/Application Support/Godot/export_templates/4.7.2.stable`.
