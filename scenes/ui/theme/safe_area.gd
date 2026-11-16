class_name SafeArea
extends RefCounted
## Marginesy bezpiecznego obszaru ekranu (wyciecie na aparat, pasek gestow),
## przeliczone z pikseli ekranu na jednostki viewportu. Na PC zawsze 0.


static func top_inset(viewport: Viewport) -> int:
	var scale := _scale(viewport)
	if scale <= 0.0:
		return 0
	return int(maxf(DisplayServer.get_display_safe_area().position.y, 0.0) * scale)


static func bottom_inset(viewport: Viewport) -> int:
	var scale := _scale(viewport)
	if scale <= 0.0:
		return 0
	var window_height := DisplayServer.window_get_size().y
	return int(maxf(window_height - DisplayServer.get_display_safe_area().end.y, 0.0) * scale)


static func _scale(viewport: Viewport) -> float:
	if not OS.has_feature("mobile"):
		return 0.0
	var window_height := DisplayServer.window_get_size().y
	if window_height <= 0:
		return 0.0
	return viewport.get_visible_rect().size.y / float(window_height)
