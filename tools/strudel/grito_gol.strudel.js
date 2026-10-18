// GOL MIO - efeito da entrada do logo (8 s, um ciclo). Tudo medido em centesimos de segundo:
// apito do juiz (0,00-0,45 s) -> sopro subindo -> IMPACTO quando o logo bate (0,76 s)
// -> "GOOOOOL" da torcida com eco (0,80-4,2 s) -> rugido do estadio se apagando.
// Cole em https://strudel.cc e aperte Ctrl+Enter.
setcpm(7.5)
all(x => x.postgain(.5))

// apito do juiz
$: s("ballwhistle:0@45 ~@755").clip(1).release(.05).gain(2).room(.6).size(6)

// sopro subindo ate o impacto
$: s("~@38 white@38 ~@724").hpf(500).lpf(800).lpenv(5).lpattack(.36)
  .attack(.3).release(.02).gain(.18)

// IMPACTO
$: s("~@76 bd@724").bank("RolandTR909").gain(1.3).distort(1.5)
$: s("~@76 cr@724").bank("RolandTR909").gain(.7).room(.6)
$: note("~@76 c1@724").s("gm_timpani").gain(1.2)
$: note("~@76 c2@724").s("gm_taiko_drum").gain(1)
$: note("~@76 [c4,g4,c5,e5]@724").s("gm_orchestra_hit").gain(.9).clip(.3).room(.5)

// "GOOOOOOOL!" - a torcida inteira, com eco de estadio
$: note("~@80 [c3,g3,c4,e4]@340 ~@380").layer(
    x => x.s("gm_choir_aahs").gain(.85),
    x => x.transpose(-12).s("gm_voice_oohs").gain(.6),
    x => x.s("supersaw").unison(9).detune(.8).vowel("o").lpf(2600).gain(.25)
  ).attack(.06).release(.8).room(1).size(9)
  .delay(.4).delaytime(.38).delayfeedback(.42)
// o "L" do fim: a voz sobe e fecha
$: note("~@380 [d3,a3,d4,fs4]@60 ~@360").s("supersaw").unison(9).detune(.8)
  .vowel("i").lpf(1800).attack(.05).release(.5).gain(.2).room(1).size(9)
  .delay(.55).delaytime(.38).delayfeedback(.5)  // eco: "...ol ...ol ...ol"

// rugido do estadio
$: s("~@78 pink@450 ~@272").bpf(900).bpq(.5).attack(.15).release(1.5).gain(.32)
$: note("~@78 c4@450 ~@272").s("gm_applause").gain(.5).release(1.5)
