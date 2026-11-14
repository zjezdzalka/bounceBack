class_name LaserMinigame
extends Node2D
## Randomly generated laser mirror puzzle (Godot 4.x). Always solvable.
##
## Setup: create a Node2D scene, attach this script, run it.
## Click a mirror = rotate 45 degrees. Guide the laser into the goal.
## Keys: R = reset this puzzle, N = new puzzle (also click after winning).
##
## Result: `minigame_finished(success: bool)` emits true on win; `is_won()` also works.

signal minigame_finished(success: bool)

const CELL := 80.0
const MARGIN := 80.0
const MIRROR_LEN := 90.0
const CLICK_RADIUS := 24.0
const MAX_BOUNCES := 40

@export var min_turns := 2            # mirrors that redirect the beam on the solution path
@export var max_turns := 5
@export var max_blockers := 3         # mirrors sitting ON the path that must be turned out of the way
@export var max_decoys := 4           # extra mirrors off the path
@export var max_walls := 4
@export var goal_radius := 26.0

var emitter_pos := Vector2.ZERO
var emitter_angle_deg := -45.0
var goal_pos := Vector2.ZERO
var mirrors: Array[Dictionary] = []   # {pos, angle, start_angle}
var walls: Array[Rect2] = []
var beam_points := PackedVector2Array()
var won := false
var puzzles_solved := 0

var _cols := 0
var _rows := 0


func _ready() -> void:
	randomize()
	new_puzzle()


func is_won() -> bool:
	return won


# ====================== generation ======================

func new_puzzle() -> void:
	var size := get_viewport_rect().size
	_cols = int((size.x - MARGIN * 2.0) / CELL)
	_rows = int((size.y - MARGIN * 2.0) / CELL)
	won = false
	for attempt in 300:
		if _generate():
			break
	_trace()


func _world(g: Vector2i) -> Vector2:
	return Vector2(MARGIN, MARGIN) + Vector2(g) * CELL


func _max_steps(c: Vector2i, d: Vector2i) -> int:
	var kx := (_cols - c.x) if d.x > 0 else c.x
	var ky := (_rows - c.y) if d.y > 0 else c.y
	return mini(kx, ky)


func _generate() -> bool:
	mirrors.clear()
	walls.clear()

	var cur := Vector2i(randi_range(0, _cols), randi_range(0, _rows))
	var dir := Vector2i(1 if randf() < 0.5 else -1, 1 if randf() < 0.5 else -1)
	emitter_pos = _world(cur)
	emitter_angle_deg = rad_to_deg(Vector2(dir).angle())

	var segs: Array = []          # [a, b] in world coords
	var recs: Array[Dictionary] = []  # {pos, sol, segs}
	var turns := randi_range(min_turns, max_turns)
	var blockers_left := randi_range(0, max_blockers)

	for i in turns:
		var maxk := _max_steps(cur, dir)
		if maxk < 1:
			return false
		var k := randi_range(1, maxk)
		var nxt := cur + dir * k
		segs.append([_world(cur), _world(nxt)])
		# blockers: mirrors on the interior of this segment, solved by being parallel to the beam
		for j in range(1, k):
			if blockers_left > 0 and randf() < 0.5:
				blockers_left -= 1
				recs.append({"pos": _world(cur + dir * j), "sol": 45.0 if dir.x * dir.y > 0 else 135.0, "segs": [i]})
		var sol := 0.0
		if randf() < 0.5:
			dir.x = -dir.x
			sol = 90.0
		else:
			dir.y = -dir.y
			sol = 0.0
		recs.append({"pos": _world(nxt), "sol": sol, "segs": [i, i + 1]})
		cur = nxt

	var maxk2 := _max_steps(cur, dir)
	if maxk2 < 1:
		return false
	var gk := randi_range(1, maxk2)
	var gcell := cur + dir * gk
	segs.append([_world(cur), _world(gcell)])
	goal_pos = _world(gcell)

	# --- validate path ---
	for i in segs.size():
		for j in range(i + 2, segs.size()):
			if Geometry2D.segment_intersects_segment(segs[i][0], segs[i][1], segs[j][0], segs[j][1]) != null:
				return false
	for r in recs:
		for i in segs.size():
			if i in r["segs"]:
				continue
			var cp := Geometry2D.get_closest_point_to_segment(r["pos"], segs[i][0], segs[i][1])
			if cp.distance_to(r["pos"]) < 58.0:
				return false
	for i in range(1, segs.size()):
		if Geometry2D.get_closest_point_to_segment(emitter_pos, segs[i][0], segs[i][1]).distance_to(emitter_pos) < 50.0:
			return false
	for i in range(0, segs.size() - 1):
		if Geometry2D.get_closest_point_to_segment(goal_pos, segs[i][0], segs[i][1]).distance_to(goal_pos) < 50.0:
			return false

	# --- decoy mirrors (off the path) ---
	var occupied: Array[Vector2] = [emitter_pos, goal_pos]
	for r in recs:
		occupied.append(r["pos"])
	for d in randi_range(0, max_decoys):
		for t in 40:
			var p := Vector2(randf_range(MARGIN, MARGIN + _cols * CELL), randf_range(MARGIN, MARGIN + _rows * CELL))
			if _far_from_segs(p, segs, 85.0) and _far_from_points(p, occupied, 100.0):
				recs.append({"pos": p, "sol": 0.0, "segs": [], "decoy": true})
				occupied.append(p)
				break

	# --- walls ---
	for w in randi_range(0, max_walls):
		for t in 40:
			var long_side := randf_range(70.0, 220.0)
			var rect := Rect2(
				Vector2(randf_range(MARGIN, MARGIN + _cols * CELL), randf_range(MARGIN, MARGIN + _rows * CELL)),
				Vector2(30.0, long_side) if randf() < 0.5 else Vector2(long_side, 30.0))
			var grown := rect.grow(30.0)
			var ok := true
			for s in segs:
				if _rect_hits_segment(grown, s[0], s[1]):
					ok = false
					break
			if ok:
				for p in occupied:
					if rect.grow(60.0).has_point(p):
						ok = false
						break
			if ok:
				for other in walls:
					if rect.grow(20.0).intersects(other):
						ok = false
						break
			if ok:
				walls.append(rect)
				break

	# --- build mirrors, check solvable with solution angles ---
	for r in recs:
		mirrors.append({"pos": r["pos"], "angle": r["sol"], "start_angle": r["sol"], "decoy": r.get("decoy", false)})
	if not _trace(true):
		return false

	# --- scramble until the puzzle is not already solved ---
	for t in 20:
		for m in mirrors:
			var a := 45.0 * randi_range(0, 7)
			if not m["decoy"]:
				a = fposmod(m["angle"] + 45.0 * randi_range(1, 3), 360.0)
			m["angle"] = a
			m["start_angle"] = a
		if not _trace(true):
			return true
	return false


func _far_from_segs(p: Vector2, segs: Array, dist: float) -> bool:
	for s in segs:
		if Geometry2D.get_closest_point_to_segment(p, s[0], s[1]).distance_to(p) < dist:
			return false
	return true


func _far_from_points(p: Vector2, pts: Array[Vector2], dist: float) -> bool:
	for q in pts:
		if p.distance_to(q) < dist:
			return false
	return true


func _rect_hits_segment(r: Rect2, a: Vector2, b: Vector2) -> bool:
	if r.has_point(a) or r.has_point(b):
		return true
	var c := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for k in 4:
		if Geometry2D.segment_intersects_segment(a, b, c[k], c[(k + 1) % 4]) != null:
			return true
	return false


# ====================== input ======================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_N:
			new_puzzle()
		elif event.keycode == KEY_R:
			for m in mirrors:
				m["angle"] = m["start_angle"]
			won = false
			_trace()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if won:
			new_puzzle()
			return
		var mp := get_local_mouse_position()
		for m in mirrors:
			var cp := Geometry2D.get_closest_point_to_segment(mp, _mirror_a(m), _mirror_b(m))
			if mp.distance_to(cp) <= CLICK_RADIUS:
				m["angle"] = fposmod(m["angle"] + 45.0, 360.0)
				_trace()
				break


# ====================== laser ======================

func _mirror_dir(m: Dictionary) -> Vector2:
	return Vector2.RIGHT.rotated(deg_to_rad(m["angle"]))

func _mirror_a(m: Dictionary) -> Vector2:
	return m["pos"] - _mirror_dir(m) * MIRROR_LEN * 0.5

func _mirror_b(m: Dictionary) -> Vector2:
	return m["pos"] + _mirror_dir(m) * MIRROR_LEN * 0.5

func _ray_segment(p: Vector2, d: Vector2, a: Vector2, b: Vector2) -> float:
	var e := b - a
	var denom := d.cross(e)
	if absf(denom) < 0.0001:
		return -1.0
	var ap := a - p
	var t := ap.cross(e) / denom
	var s := ap.cross(d) / denom
	if t > 0.01 and s >= 0.0 and s <= 1.0:
		return t
	return -1.0

func _ray_circle(p: Vector2, d: Vector2, c: Vector2, r: float) -> float:
	var f := p - c
	var b := f.dot(d)
	var disc := b * b - (f.dot(f) - r * r)
	if disc < 0.0:
		return -1.0
	var t := -b - sqrt(disc)
	return t if t > 0.01 else -1.0


## Traces the beam. Returns true if it reaches the goal.
## check_only = true: no drawing/win side effects (used for generation).
func _trace(check_only := false) -> bool:
	var pts := PackedVector2Array()
	var p := emitter_pos
	var d := Vector2.RIGHT.rotated(deg_to_rad(emitter_angle_deg))
	pts.append(p)
	var hit_goal := false

	for i in MAX_BOUNCES:
		var best_t := 99999.0
		var kind := "none"
		var best_normal := Vector2.ZERO

		for m in mirrors:
			var t := _ray_segment(p, d, _mirror_a(m), _mirror_b(m))
			if t > 0.0 and t < best_t:
				best_t = t
				kind = "mirror"
				var md := _mirror_dir(m)
				best_normal = Vector2(-md.y, md.x)

		for w in walls:
			var c := [w.position, Vector2(w.end.x, w.position.y), w.end, Vector2(w.position.x, w.end.y)]
			for k in 4:
				var t := _ray_segment(p, d, c[k], c[(k + 1) % 4])
				if t > 0.0 and t < best_t:
					best_t = t
					kind = "wall"

		var tg := _ray_circle(p, d, goal_pos, goal_radius)
		if tg > 0.0 and tg < best_t:
			best_t = tg
			kind = "goal"

		if kind == "none":
			pts.append(p + d * 2000.0)
			break
		p += d * best_t
		pts.append(p)
		if kind == "goal":
			hit_goal = true
			break
		elif kind == "wall":
			break
		else:
			d = d.bounce(best_normal).normalized()

	if not check_only:
		beam_points = pts
		if hit_goal and not won:
			won = true
			puzzles_solved += 1
			minigame_finished.emit(true)
		queue_redraw()
	return hit_goal


# ====================== drawing ======================

func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.08, 0.12))

	for w in walls:
		draw_rect(w, Color(0.35, 0.35, 0.4))

	var goal_col := Color(0.3, 1.0, 0.4) if won else Color(0.9, 0.8, 0.2)
	draw_circle(goal_pos, goal_radius, goal_col.darkened(0.5))
	draw_arc(goal_pos, goal_radius, 0, TAU, 32, goal_col, 3.0)

	var edir := Vector2.RIGHT.rotated(deg_to_rad(emitter_angle_deg))
	draw_circle(emitter_pos, 14, Color(0.8, 0.2, 0.2))
	draw_line(emitter_pos, emitter_pos + edir * 26, Color(1, 0.5, 0.5), 6.0)

	if beam_points.size() >= 2:
		draw_polyline(beam_points, Color(1, 0.1, 0.1, 0.25), 9.0)
		draw_polyline(beam_points, Color(1, 0.4, 0.4), 3.0)

	for m in mirrors:
		draw_line(_mirror_a(m), _mirror_b(m), Color(0.6, 0.85, 1.0), 6.0)
		draw_circle(m["pos"], 5, Color(1, 1, 1))

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(20, 30), "Click mirrors to rotate 45°  |  R = reset  |  N = new puzzle  |  Solved: %d" % puzzles_solved,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.8, 0.8, 0.9))

	if won:
		draw_rect(Rect2(0, size.y * 0.4, size.x, 130), Color(0, 0, 0, 0.7))
		draw_string(font, Vector2(0, size.y * 0.4 + 70), "YOU WIN!",
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 56, Color(0.3, 1.0, 0.4))
		draw_string(font, Vector2(0, size.y * 0.4 + 110), "Click or press N for a new puzzle",
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color(0.8, 0.8, 0.9))
