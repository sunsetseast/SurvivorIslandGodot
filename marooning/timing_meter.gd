class_name MarooningTimingMeter
extends Control
var simulation: MarooningRace
func _process(_delta: float) -> void:
    queue_redraw()
func _draw() -> void:
    if simulation == null:
        return
    var width := size.x
    draw_rect(Rect2(0,0,width,24),Color("31383d"))
    draw_rect(Rect2(width*(.5-.17*simulation.timing_scale),0,width*.34*simulation.timing_scale,24),Color("82774b"))
    draw_rect(Rect2(width*(.5-.065*simulation.timing_scale),0,width*.13*simulation.timing_scale,24),Color("d9c87d"))
    var x := fmod(simulation.elapsed,MarooningRace.BEAT)/MarooningRace.BEAT*width
    draw_line(Vector2(x,-4),Vector2(x,28),Color.WHITE,4)
    draw_line(Vector2(width*.5,0),Vector2(width*.5,24),Color.BLACK,2)
