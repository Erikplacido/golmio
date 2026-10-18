// GOL MIO - tema da tela de abertura (loop de 16 compassos, 128 bpm, Do maior)
// Clash Royale x futebol: fanfarra de metais, pizzicato, tuba, timpanos,
// batucada (surdo, caixa, agogo, apito de samba) e a torcida cantando "o-le, o-le" com eco.
// Cole em https://strudel.cc e aperte Ctrl+Enter.
setcpm(128/4)
all(x => x.postgain(.5))

//            A1: fanfarra   A2: torcida canta   B: ponte     A3: final
const FANF  = "<1 1 1 1       0 0 0 0             1 1 1 1      1 1 1 1>"
const CANTO = "<0 0 0 0       1 1 1 1             0 0 0 0      1 1 1 1>"
const RAIZ  = "<48 53 55 48   48 53 55 48         45 53 48 55  48 53 55 48>"  // C F G C | Am F C G

// metais: a melodia principal (trompas na ponte)
$: note(`<
  [g4 c5 ~ c5 e5 ~ d5 c5] [a4 c5 ~ f5 e5 d5 c5 ~] [b4 d5 ~ g5 f5 e5 d5 ~] [c5 ~ g4 ~ c5 [e5 g5] c6 ~]
  ~ ~ ~ ~
  [e5 ~ ~ c5 ~ ~ a4 ~] [f5 ~ ~ e5 d5 ~ c5 ~] [e5 ~ ~ g5 ~ ~ c6 ~] [b5 ~ a5 ~ g5 ~ d5 ~]
  [g4 c5 ~ c5 e5 ~ d5 c5] [a4 c5 ~ f5 e5 d5 c5 ~] [b4 d5 ~ g5 f5 e5 d5 ~] [c6 ~ g5 ~ e5 d5 c5 ~]
>`).s("<gm_brass_section!8 gm_french_horn!4 gm_brass_section!4>")
  .mask(FANF).gain(.85).room(.35).size(4)

// metais respondendo a torcida (A2)
$: note("<~ [~ ~ ~ ~ g5 g5 g5 c6] ~ [~ ~ ~ ~ a5 g5 e5 c6]>")
  .s("gm_trumpet").mask(CANTO).mask("<0 0 0 0 1 1 1 1 0 0 0 0 0 0 0 0>")
  .gain(.75).room(.4).size(4)

// pizzicato saltitante
$: note("0 7 12 19 12 7 12 7".add(RAIZ)).s("gm_pizzicato_strings")
  .gain(.55).room(.3)

// tuba no oom-pah
$: note("0 ~ 7 ~ 0 ~ 7 ~".add(RAIZ).sub(24)).s("gm_tuba").gain(.7)

// cordas sustentando os acordes
$: note(`<[c4,e4,g4] [c4,f4,a4] [b3,d4,g4] [c4,e4,g4] [c4,e4,g4] [c4,f4,a4] [b3,d4,g4] [c4,e4,g4]
          [c4,e4,a4] [c4,f4,a4] [c4,e4,g4] [b3,d4,g4] [c4,e4,g4] [c4,f4,a4] [b3,d4,g4] [c4,e4,g4]>`)
  .s("gm_string_ensemble_1").gain(.32).attack(.05).release(.4).room(.5)

// orquestra: golpe no fim de cada frase
$: note("[~ ~ ~ ~ ~ ~ [c4,g4,c5] [c4,g4,c5]]").s("gm_orchestra_hit")
  .mask("<0 0 0 1>").gain(.6).room(.4)

// timpanos marcando + rufo no fim do loop
$: note("<[c2 ~ ~ ~ g1 ~ ~ ~]!15 [c2 ~ ~ ~ g1 g1 [g1 g1] [g1 g1 g1 g1]]>")
  .s("gm_timpani").gain(.9)

// surdo de marcacao (batucada)
$: note("~ g1 ~ c2").s("gm_taiko_drum").gain(.75)

// bumbo + caixa de marcha
$: s("bd ~ ~ bd ~ ~ bd ~, ~ sd ~ sd, ~ ~ ~ [~ sd]").bank("RolandTR909").gain(.55)

// caixa de samba em semicolcheias
$: s("hh*16").bank("RolandTR909").gain("[.22 .1 .16 .1]*4").hpf(6000)

// agogo
$: note("[e5 ~ c5 ~] [c5 ~ e5 ~] [~ c5 ~ e5] [~ c5 e5 ~]").s("gm_agogo").gain(.4)

// prato no inicio das secoes
$: s("<cr ~ ~ ~ cr ~ ~ ~ cr ~ ~ ~ cr ~ ~ ~>").bank("RolandTR909").gain(.4).room(.5)

// apito de samba
$: s("[~ ~ ~ ~ ~ ~ [ballwhistle:1 ballwhistle:1] ballwhistle:1]").clip(1)
  .mask("<0 0 0 1>").gain(.35).room(.5)

// TORCIDA: "o-le, o-le, o-le... o-leeee" com eco de estadio
$: note("<[e4 c4 ~ e4 c4 ~ e4 c4] [~ e4 c4@6]>").layer(
    x => x.s("gm_choir_aahs").gain(.7),
    x => x.transpose(-12).s("gm_voice_oohs").gain(.5),
    x => x.transpose(-12).s("supersaw").unison(7).detune(.6)
          .vowel("<[o e ~ o e ~ o e] [~ o e@6]>").lpf(2200).gain(.22)
  ).mask(CANTO).room(.9).size(8)
  .delay(.45).delaytime(60/128*1.5).delayfeedback(.45)

// palmas da torcida
$: s("~ cp ~ cp").bank("RolandTR909").mask(CANTO).gain(.35).room(.8).size(6)

// murmurio do estadio ao fundo
$: s("pink").bpf(750).bpq(.6).attack(.6).release(1.2).gain(.07)
