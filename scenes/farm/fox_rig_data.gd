class_name FoxRigData
extends RefCounted
## Ramki i punkty obrotu czesci lisa. PLIK GENEROWANY: tools/gen_fox.py.
## Wspolrzedne w ukladzie starego fox.svg (196 x 116, lis patrzy w prawo).

const ORIGIN := Vector2(98, 120)
const JOINT := Vector2(96, 70)
const NECK := Vector2(140, 60)
const TAIL_BASE := Vector2(52, 60)
const SHADOW := Vector2(96, 107)
const LEG_LEN := 27.0
const HIPS := {
	"hind_far": Vector2(66, 80),
	"hind_near": Vector2(79, 82),
	"front_far": Vector2(131, 80),
	"front_near": Vector2(119, 82),
}
## nazwa -> [sciezka tekstury, srodek ramki, punkt obrotu]
const PARTS := {
	"rear": ["res://assets/sprites/animals/fox_parts/fox_rear.svg", Vector2(76, 64), Vector2(96, 70)],
	"front": ["res://assets/sprites/animals/fox_parts/fox_front.svg", Vector2(118, 64), Vector2(96, 70)],
	"head": ["res://assets/sprites/animals/fox_parts/fox_head.svg", Vector2(159, 38), Vector2(140, 60)],
	"tail": ["res://assets/sprites/animals/fox_parts/fox_tail.svg", Vector2(32, 45), Vector2(52, 60)],
	"leg": ["res://assets/sprites/animals/fox_parts/fox_leg.svg", Vector2(1, 13.5), Vector2(0, 0)],
	"shadow": ["res://assets/sprites/animals/fox_parts/fox_shadow.svg", Vector2(96, 107), Vector2(96, 107)],
}
