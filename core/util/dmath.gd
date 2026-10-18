class_name DMath
extends RefCounted
## Matemática DETERMINÍSTICA: resultado bit a bit idêntico em qualquer CPU, sistema e navegador
## (x86, ARM, WebAssembly; Windows, macOS, Linux, Android, iOS, Web).
##
## Só usa + - * / e sqrt — operações que a norma IEEE 754 obriga a arredondar igual em todo lugar —
## executadas uma a uma pela VM do GDScript (sem fusão FMA). Evita:
##   - libm (sin, cos, atan2, pow, exp...): cada sistema tem a sua implementação;
##   - métodos C++ compostos do Vector2 (length, distance_to, normalized, dot, angle, lerp...):
##     alguns compiladores fundem a*b+c em FMA em ARM e o último bit muda.
## Regra verificada por tests/unit/test_determinism.gd em todo código de core/ e mechanics/.

const HALF_PI := PI / 2.0


static func dist(a: Vector2, b: Vector2) -> float:
	var dx := a.x - b.x
	var dy := a.y - b.y
	return sqrt(dx * dx + dy * dy)


static func dist2(a: Vector2, b: Vector2) -> float:
	var dx := a.x - b.x
	var dy := a.y - b.y
	return dx * dx + dy * dy


static func length(v: Vector2) -> float:
	return sqrt(v.x * v.x + v.y * v.y)


static func length2(v: Vector2) -> float:
	return v.x * v.x + v.y * v.y


static func normalized(v: Vector2) -> Vector2:
	var l := sqrt(v.x * v.x + v.y * v.y)
	if l == 0.0:
		return Vector2.ZERO
	return Vector2(v.x / l, v.y / l)


static func dot(a: Vector2, b: Vector2) -> float:
	return a.x * b.x + a.y * b.y


static func lerp(a: float, b: float, t: float) -> float:
	return a + (b - a) * t


## Arredonda para múltiplos de `step` (substitui snappedf).
static func round_to(x: float, step: float) -> float:
	return floor(x / step + 0.5) * step


## Seno por série de Taylor com redução de faixa (erro < 1e-7). Mesmo valor em qualquer plataforma.
static func dsin(x: float) -> float:
	x = x - TAU * floor((x + PI) / TAU)
	if x > HALF_PI:
		x = PI - x
	elif x < -HALF_PI:
		x = -PI - x
	var x2 := x * x
	return x * (1.0 - x2 / 6.0 * (1.0 - x2 / 20.0 * (1.0 - x2 / 42.0 * (1.0 - x2 / 72.0 * (1.0 - x2 / 110.0)))))


static func dcos(x: float) -> float:
	return dsin(x + HALF_PI)


## Gira um vetor por `angle` radianos.
static func rotated(v: Vector2, angle: float) -> Vector2:
	var s := dsin(angle)
	var c := dcos(angle)
	return Vector2(v.x * c - v.y * s, v.x * s + v.y * c)


static func dist_point_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var abx := b.x - a.x
	var aby := b.y - a.y
	var l2 := abx * abx + aby * aby
	if l2 == 0.0:
		return dist(p, a)
	var t := clampf(((p.x - a.x) * abx + (p.y - a.y) * aby) / l2, 0.0, 1.0)
	var dx := p.x - (a.x + abx * t)
	var dy := p.y - (a.y + aby * t)
	return sqrt(dx * dx + dy * dy)
