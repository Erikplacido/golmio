// GOL MIO - banco de efeitos sonoros: partida, pacote de figurinhas e interface.
// Escolha o efeito em TOCAR (nomes no fim do arquivo), cole em https://strudel.cc e aperte Ctrl+Enter.
// Cada efeito vira assets/audio/sfx/<nome>.ogg (veja LEIA-ME.md).
const TOCAR = 'gol'   // aspas simples: aqui e um nome, nao um padrao

const T = 8                                    // um ciclo = 8 s; tudo abaixo e marcado em segundos
setcps(1 / T)
all(x => x.postgain(.5))
const at = (t, len, p) => p.compress(t / T, (t + len) / T)   // toca p dentro de [t, t + len]

// --- pecas -----------------------------------------------------------------------------------
// apito do juiz (amostra real: ballwhistle :0 longo, :1 curto)
const apito = (t, len, g = 1.6) => at(t, len, s(len > .4 ? "ballwhistle:0" : "ballwhistle:1"))
  .clip(1).release(.04).gain(g).room(.45).size(5)

// arquibancada: ruido rosa filtrado + aplausos
const torcida = (t, len, g = .3, f = 900, sobe = .12) => stack(
  at(t, len, s("pink")).bpf(f).bpq(.5).gain(g),
  at(t, len, note("c4").s("gm_applause")).gain(g * 1.4)
).attack(sobe).release(1.2)

// a torcida em coro: "uuuh", "aaah", "GOOOL", vaia
const coro = (t, len, notas, vogal, g = .5) => at(t, len, note(notas)).layer(
  x => x.s("gm_choir_aahs").gain(g),
  x => x.transpose(-12).s("gm_voice_oohs").gain(g * .7),
  x => x.s("supersaw").unison(7).detune(.7).vowel(vogal).lpf(2200).gain(g * .3)
).attack(.08).release(.6).room(.9).size(8)

// pe na bola: baque + couro + estalo
const chute = t => stack(
  at(t, .2, s("bd").bank("RolandTR909")).lpf(2500).gain(1),
  at(t, .04, s("white")).bpf(1800).bpq(1.5).decay(.04).sustain(0).gain(.6),
  at(t, .06, s("rim").bank("RolandTR909")).hpf(1500).gain(.35)
)

// bola estufando a rede
const rede = t => at(t, .45, s("white*6").bpf("5000 3800 3000 2400 1900 1500").bpq(2)
  .decay(.07).sustain(0).gain(".6 .55 .5 .45 .4 .35"))

// rufo de timpano / de caixa crescendo
const rufoTimpano = (t, len, nota = "c2") => at(t, len, note(nota).fast(Math.round(len * 22))
  .s("gm_timpani").gain(saw.range(.15, .9)))
const rufoCaixa = (t, len, g = .45) => at(t, len, s("sd").fast(Math.round(len * 26))
  .bank("RolandTR909").gain(saw.range(.05, g)))

// vuvuzela (si bemol, como manda a tradicao)
const vuvuzela = (t, len, g = .2) => at(t, len, note("bb3")).s("sawtooth").lpf(1300)
  .vib(5).vibmod(.12).attack(.06).release(.25).gain(g).room(.6).size(6)

// metais
const metais = (t, len, notas, g = .8, som = "gm_brass_section") => at(t, len, note(notas)).s(som).gain(g).room(.4).size(4)
const golpe = (t, notas = "[c3,g3,c4]", g = .8) => at(t, .3, note(notas)).s("gm_orchestra_hit").gain(g).room(.4)
const prato = (t, g = .5) => at(t, .3, s("cr").bank("RolandTR909")).gain(g).room(.5)
const brilho = (t, len, notas, g = .4) => at(t, len, note(notas)).s("gm_glockenspiel").gain(g)
  .room(.5).delay(.3).delaytime(.12).delayfeedback(.35)
// sopro subindo (riser)
const sopro = (t, len, g = .25) => at(t, len, s("white")).hpf(500).lpf(500).lpenv(5).lpattack(len)
  .attack(len * .9).release(.05).gain(g)

const SFX = {
  // --- partida --------------------------------------------------------------------------------
  // (gol e defesa nao tem o chute: no jogo o "chute" toca quando a bola sai do pe, e eles quando ela chega)
  apito_inicio:    stack(apito(0, .22), apito(.36, .8)),
  apito_falta:     stack(apito(0, .3, 1.8), torcida(.1, .8, .1, 700)),
  apito_intervalo: stack(apito(0, .7), apito(.95, 1.1), torcida(.2, 2.2, .16, 800)),
  apito_final:     stack(apito(0, .4), apito(.6, .4), apito(1.2, 1.6),
                         torcida(1.3, 3.2, .35, 900, .5), vuvuzela(1.6, 2.2)),
  chute:           chute(0),
  chute_fora:      stack(chute(0), coro(.3, 1.6, "e4 c4@2", "a", .45), torcida(.3, 1.4, .14)),
  bloqueio:        stack(at(0, .25, s("lt").bank("RolandTR909")).lpf(1500).gain(1),
                         at(0, .2, s("bd").bank("RolandTR909")).gain(.9),
                         at(0, .05, s("white")).bpf(900).decay(.05).sustain(0).gain(.5),
                         coro(.1, .7, "[g3,c4]", "o", .3)),
  defesa:          stack(at(.24, .12, s("cp").bank("RolandTR909")).lpf(3000).gain(.9),
                         at(.24, .15, s("bd").bank("RolandTR909")).lpf(800).gain(.7),
                         coro(.32, 1.7, "c4 d4@2 bb3@3", "u", .5), torcida(.3, 1.6, .22)),
  gol:             stack(rede(.18), golpe(.2, "[c3,c4]"), prato(.2, .6),
                         torcida(.22, 3.4, .45, 1000),
                         coro(.28, 2.4, "[c3,g3,c4,e4]", "o", .6).delay(.35).delaytime(.38).delayfeedback(.4),
                         metais(.6, .25, "[g4,c5,e5]"), metais(.9, .9, "[c5,e5,g5,c6]"),
                         vuvuzela(1.2, 1.8)),
  cartao_amarelo:  stack(apito(0, .35, 1.8),
                         at(.38, .5, note("e5 b5")).s("gm_vibraphone").gain(.6).room(.4),
                         at(.38, .25, note("[e3,b3]")).s("gm_pizzicato_strings").gain(.6),
                         coro(.45, 1, "g3 e3@2", "u", .3)),
  cartao_vermelho: stack(apito(0, 1, 1.8),
                         golpe(.5, "[c2,gb2,c3]", .9), at(.5, .3, note("c2")).s("gm_timpani").gain(1),
                         metais(.5, 1.4, "[c3,eb3,gb3,a3]", .7, "gm_trombone"),
                         coro(.8, 2.2, "[c3,db3]", "u", .45), torcida(.8, 2.2, .22, 500)),
  penalti:         stack(apito(0, 1.1, 1.9), rufoTimpano(.3, 1.8),
                         torcida(.3, 2.2, .35, 1000, .8), coro(.6, 1.6, "[g3,d4]", "o", .35)),
  impedimento:     stack(apito(0, .35, 1.8),
                         metais(.45, .9, "g3 fs3 f3 e3@2", .55, "gm_trombone"),
                         torcida(.4, 1, .12, 600)),
  substituicao:    stack(at(0, .3, note("e6 ~ e6")).s("sine").decay(.08).sustain(0).gain(.25),
                         at(.3, .6, note("g5 e5@2")).s("gm_vibraphone").gain(.6).room(.5),
                         torcida(.3, 1.2, .12, 1500)),
  escanteio:       stack(torcida(0, 1.6, .3, 1000, .9), rufoCaixa(0, 1.2, .3)),
  prorrogacao:     stack(apito(0, .8), rufoTimpano(.6, 1.6), golpe(2.2), prato(2.2, .5),
                         metais(2.2, 1, "[c4,eb4,g4,c5]"), torcida(1, 2.4, .25, 900, .6)),
  penalti_gol:     stack(chute(0), rede(.15), golpe(.3, "[c4,c5]", .7),
                         torcida(.2, 2.2, .4, 1000), coro(.25, 1.6, "[c3,g3,c4,e4]", "o", .5)),
  penalti_perdido: stack(chute(0), coro(.3, 1.6, "e4 c4@2", "a", .45), torcida(.3, 1.4, .14),
                         metais(.6, 1.1, "g3 fs3 f3 e3@3", .45, "gm_trombone")),
  // loop do estadio durante a partida (um ciclo inteiro, emenda sem corte)
  torcida_ambiente: stack(
    s("pink*4").bpf(800).bpq(.5).attack(.8).release(.8).gain(".13 .15 .12 .16"),
    s("brown*2").lpf(400).attack(1).release(1).gain(.1),
    note("[~ g1 ~ c2]*4").s("gm_taiko_drum").lpf(900).gain(.35).room(.8).size(8),
    s("hh*64").bank("RolandTR909").hpf(5000).lpf(8000).gain(".08 .03 .05 .03").room(.8).size(8),
    note("[[e5 ~ c5 ~] [c5 ~ e5 ~] [~ c5 ~ e5] [~ c5 e5 ~]]*4").s("gm_agogo").lpf(2500).gain(.12).room(.8).size(8),
    coro(4, 3, "e4 c4 ~ e4 c4 ~ e4 c4@2", "o", .14),
    at(1.5, 1, note("c4")).s("gm_applause").gain(.15).attack(.3).release(.8),
    at(6.2, 1, note("c4")).s("gm_applause").gain(.12).attack(.3).release(.8)
  ),

  // --- pacote de figurinhas (momentos do PackRitual) -----------------------------------------
  pacote_entrada:   stack(at(0, .5, s("white")).lpf(400).lpenv(4).lpattack(.35).attack(.3).release(.15).gain(.35),
                          at(.42, .12, s("bd").bank("RolandTR909")).lpf(500).gain(.5),
                          at(.4, .1, s("crackle")).hpf(2500).gain(.3)),
  pacote_tensao:    stack(at(0, .45, s("white*12").bpf("800 1000 1200 1400 1700 2000 2400 2800 3300 3800 4400 5000")
                            .bpq(3).decay(.03).sustain(0).gain(".2 .25 .3 .3 .35 .4 .4 .45 .5 .5 .55 .6")),
                          at(0, .45, s("crackle")).hpf(1800).gain(.25)),
  pacote_rasgo:     stack(at(0, .32, s("white*14").bpf("5000 4500 4000 3600 3200 2900 2600 2300 2000 1800 1600 1400 1200 1000")
                            .bpq(1.2).decay(.04).sustain(0).gain(".9 .7 1 .8 .9 .7 1 .8 .9 .7 1 .6 .8 .5")),
                          at(0, .35, s("crackle")).hpf(2000).gain(.4),
                          at(0, .4, s("white")).hpf(3000).attack(.005).decay(.35).sustain(0).gain(.2)),
  pacote_antecipacao:       stack(rufoCaixa(0, .4, .5), sopro(0, .4)),
  pacote_antecipacao_longa: stack(rufoCaixa(0, 1, .55), rufoTimpano(0, 1, "g1"), sopro(0, 1, .3)),
  revelar_comum:    stack(brilho(0, .45, "c5 e5 g5 c6", .45),
                          at(0, .45, note("c4 e4 g4 c5")).s("gm_pizzicato_strings").gain(.5)),
  revelar_raro:     stack(prato(0, .35), metais(0, .3, "[g4,b4,d5]", .7), metais(.15, .8, "[c5,e5,g5]", .8),
                          brilho(.15, .5, "c6 e6 g6 c7"), torcida(.1, 1.2, .14, 1500)),
  revelar_epico:    stack(golpe(0, "[c4,g4,c5]"), at(0, .3, note("c2")).s("gm_timpani").gain(1), prato(0, .55),
                          metais(.1, .9, "g4 c5 e5 [g5,c6]", .85), coro(.3, 1.7, "[c4,e4,g4]", "a", .4),
                          brilho(.6, .6, "c6 e6 g6 c7 e7")),
  revelar_lendario: stack(at(0, .3, s("bd").bank("RolandTR909")).gain(1.2).distort(1.2),
                          at(0, .3, note("c2")).s("gm_taiko_drum").gain(1), at(0, .3, note("c1")).s("gm_timpani").gain(1.1),
                          golpe(0, "[c3,g3,c4,e4]", .9), prato(0, .7),
                          metais(.15, 1.5, "c5 e5 g5 c6 [c6,e6,g6]@3", .9),
                          coro(.3, 2.6, "[c3,g3,c4,e4]", "o", .55).delay(.3).delaytime(.38).delayfeedback(.35),
                          torcida(.2, 2.8, .35, 1000), brilho(1.2, .8, "c6 e6 g6 c7 e7 g7"),
                          at(1.65, 1.6, note("c5")).s("gm_tubular_bells").gain(.5).room(.7)),
  carta_brilho:     stack(at(0, .35, note("e6 g6 b6 d7 e7 g7")).s("gm_celesta").gain(.4)
                            .room(.6).delay(.35).delaytime(.09).delayfeedback(.4),
                          at(0, .5, s("white")).hpf(9000).attack(.15).release(.3).gain(.06)),

  // --- interface -----------------------------------------------------------------------------
  ui_clique:    stack(at(0, .06, note("g5")).s("gm_woodblock").gain(.7),
                      at(0, .05, note("c6")).s("sine").decay(.04).sustain(0).gain(.2)),
  ui_voltar:    at(0, .14, note("e5 c5")).s("gm_woodblock").gain(.6),
  ui_confirmar: stack(at(0, .28, note("c5 g5 c6")).s("gm_xylophone").gain(.6).room(.3),
                      at(0, .12, s("bd").bank("RolandTR909")).lpf(600).gain(.5)),
  ui_erro:      stack(at(0, .3, note("e3 c3")).s("square").lpf(900).decay(.12).sustain(.3).release(.05).gain(.22),
                      at(0, .3, note("c4 a3")).s("gm_woodblock").gain(.4)),
}

SFX[TOCAR]
