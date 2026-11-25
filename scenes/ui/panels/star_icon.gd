class_name StarIcon
extends Control
## Gwiazdka rysowana wielokatem. Znak "★" (U+2605) nie istnieje w czcionce
## Baloo 2, a w przegladarce nie ma czcionki zapasowej - wlasciciel widzial
## w rogu ekranu prostokat z napisem "26 05" (zgloszenie 25.11).

@export var fill := Color("#F2B233")
@export var outline := Color("#7A4A12")
@export var outline_width := 6.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


## Wierzcholki pieciopromiennej gwiazdy wpisanej w kontrolke, czubkiem do gory.
func points() -> PackedVector2Array:
	var center := size / 2.0
	var outer := minf(size.x, size.y) / 2.0 - outline_width
	var inner := outer * 0.45
	var out := PackedVector2Array()
	for i in 10:
		var angle := -PI / 2.0 + PI / 5.0 * i
		var radius := outer if i % 2 == 0 else inner
		out.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return out


func _draw() -> void:
	var pts := points()
	if pts.size() < 3 or size.x < 4.0:
		return
	draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, outline, outline_width, true)
