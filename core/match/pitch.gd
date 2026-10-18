class_name Pitch
extends RefCounted
## Geometria do campo em coordenadas do motor (origem no canto superior esquerdo do gramado).
## A apresentação só desloca/escala; o motor nunca conhece pixels de tela.

const W := 950.0
const H := 580.0
const GOAL_H := 96.0
const GOAL_DEPTH := 24.0
const PENALTY_BOX_W := 145.0
const PENALTY_BOX_H := 290.0
const GOAL_AREA_W := 50.0
const GOAL_AREA_H := 150.0
const CENTER_CIRCLE_R := 70.0
const PENALTY_SPOT_X := 105.0
const CORNER_ARC_R := 16.0


static func center() -> Vector2:
	return Vector2(W / 2.0, H / 2.0)


static func goal_top() -> float:
	return (H - GOAL_H) / 2.0


static func goal_bottom() -> float:
	return (H + GOAL_H) / 2.0


static func dist_point_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	return DMath.dist_point_segment(p, a, b)
