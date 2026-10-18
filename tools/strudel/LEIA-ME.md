# Trilha da abertura (Strudel)

| Arquivo | Vira | Uso no jogo |
|---|---|---|
| `tema_abertura.strudel.js` | `assets/audio/tema_abertura.ogg` (30 s, loop sem emenda) | tema da `title_screen`, barramento `Music`; entra no impacto do logo |
| `grito_gol.strudel.js` | `assets/audio/grito_gol.ogg` (7,4 s) | efeito da entrada, barramento `SFX`: apito → impacto em **0,76 s** (o instante em que o logo bate) → "GOOOL" com eco |

Para ouvir/editar: cole o arquivo em <https://strudel.cc> e aperte `Ctrl+Enter`.

Para regravar: toque o código no Strudel e grave a saída (ex.: ligue um `ScriptProcessor` em
`getSuperdoughAudioController().output.destinationGain`). No tema, grave duas voltas (32 ciclos) e
use a **segunda** (do ciclo 16 ao 32), que já traz os rabos de reverb e eco da primeira; assim o loop
fecha sem emenda. No grito, corte a partir do primeiro som (o apito), para o impacto cair em 0,76 s.
Se mudar o tempo do impacto em `title_screen.gd` (`_intro`), mude os `~@76` do grito junto.

## Efeitos sonoros (`efeitos.strudel.js` → `assets/audio/sfx/<nome>.ogg`)

Um banco só: mude `const TOCAR = 'gol'` (aspas **simples**: é um nome, não um padrão) e toque.
Cada ciclo dura 8 s e `at(t, dur, padrão)` põe um som em segundos. No jogo, quem toca é o autoload
`Sfx` (`presentation/audio/sfx_service.gd`, barramento `SFX`): `SfxService.play("gol")`.

| Onde | Evento | Efeito |
|---|---|---|
| Partida (`match_view.gd`) | começo · saída de bola | `apito_inicio` |
| | chute no alvo · para fora · bloqueado | `chute` · `chute_fora` · `bloqueio` |
| | defesa · gol | `defesa` · `gol` |
| | falta · amarelo · vermelho · pênalti marcado | `apito_falta` · `cartao_amarelo` · `cartao_vermelho` · `penalti` |
| | impedimento · substituição · escanteio | `impedimento` · `substituicao` · `escanteio` |
| | fim do 1º tempo · fim de jogo · prorrogação | `apito_intervalo` · `apito_final` · `prorrogacao` |
| | disputa de pênaltis (espaçados 1,8 s) | `penalti_gol` · `penalti_perdido` |
| | fundo, em loop | `torcida_ambiente` |
| Pacote (`pack_ritual.gd`) | entrada · tensão · rasgo | `pacote_entrada` · `pacote_tensao` · `pacote_rasgo` |
| | antecipação (3+ estrelas: longa) | `pacote_antecipacao` · `pacote_antecipacao_longa` |
| | revelação por estrelas (≤2 · 3 · 4 · 5) | `revelar_comum` · `revelar_raro` · `revelar_epico` · `revelar_lendario` |
| | inspeção | `carta_brilho` |
| Interface | qualquer botão · voltar · JOGAR/Abrir · erro | `ui_clique` · `ui_voltar` · `ui_confirmar` · `ui_erro` |

Um botão troca o som com `set_meta(SfxService.META, "ui_voltar")`, ou fica mudo com `""`.

Para regravar: grave cada `TOCAR` como no tema (saída de `destinationGain`) em `sfx_<nome>.wav`
e rode `python acabamento_efeitos.py` (precisa de `numpy` e `soundfile`): ele corta o silêncio
inicial e o rabo, normaliza por tipo (interface mais baixa, gol e lendário no topo) e grava em
OGG Vorbis. O `torcida_ambiente` usa o segundo ciclo inteiro (8 s), com crossfade na emenda.
