extends CanvasLayer
class_name ChallengeScreen
## The weekly challenge, as a page: this week's goal, how to begin, your own
## attempts best-first, and — when a run has just ended — the result with a
## button to share it. Opened from the pause menu, and by itself when a run
## finishes.

signal start_requested(fresh: bool)
signal leave_requested

var challenge: Challenge
var player: Player
var open := false

var _root: Control
var _holder: Control
var _owns_pause := false
var _was_input := true


func setup(c: Challenge, p: Player) -> void:
	challenge = c
	player = p
	layer = 31
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	UiTheme.apply(_root)
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.02, 0.02, 0.7)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	visible = false


func open_screen() -> void:
	if open:
		return
	open = true
	visible = true
	_owns_pause = not get_tree().paused
	if _owns_pause:
		get_tree().paused = true
		if player != null:
			_was_input = player.input_enabled
			player.set_input_enabled(false)
	_rebuild()


func close_screen() -> void:
	if not open:
		return
	open = false
	visible = false
	if _owns_pause:
		get_tree().paused = false
		if player != null:
			player.set_input_enabled(_was_input)
	_owns_pause = false


func _input(event: InputEvent) -> void:
	if not open:
		return
	if event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		close_screen()


func _rebuild() -> void:
	if _holder != null:
		_holder.queue_free()
	_holder = CenterContainer.new()
	_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_holder)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_menu())
	_holder.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var h := get_viewport().get_visible_rect().size.y
	scroll.custom_minimum_size = Vector2(0, minf(UiTheme.px(640), h - UiTheme.px(110)))
	panel.add_child(scroll)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(UiTheme.px(500), 0)
	col.add_theme_constant_override("separation", int(UiTheme.px(9)))
	scroll.add_child(col)

	var w := Challenge.current_week()
	var spec := Challenge.for_week(int(w["year"]), int(w["week"]))
	var playing := Challenge.mode and not challenge.spec.is_empty()
	# A run in progress is described by its own goal, not this week's: one
	# begun last week and carried over showed this week's goal over last
	# week's progress ("Feed 12 people" above "0 / 6 built").
	if playing:
		spec = challenge.spec
	var show_result := playing and challenge.done

	var t := UiTheme.title("WEEKLY CHALLENGE", 26, UiTheme.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var sub := UiTheme.label("No. %d of %d  ·  the same village for everyone this week" % [
		int(spec["week"]), int(spec["year"])], 13, UiTheme.DIM, 500)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(_rule())

	if show_result:
		_result_block(col)
	else:
		var goal := UiTheme.label(str(spec["text"]), 22, UiTheme.INK, 800)
		goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(goal)
		var rule := "Fewer days and fewer orders score higher."
		if int(spec["max_orders"]) > 0:
			rule = "At most %d orders in all. Fewer days score higher." % int(spec["max_orders"])
		var r := UiTheme.label(rule, 14, UiTheme.DIM, 500)
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(r)
		if playing and challenge.active:
			var p := UiTheme.label("In progress: %s  ·  day %d  ·  %d orders" % [
				Challenge.progress_phrase(challenge.spec, challenge.progress),
				challenge.clock.day if challenge.clock != null else 1, challenge.orders],
				14, UiTheme.GOLD, 700)
			p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(p)

	col.add_child(_rule())
	_buttons_block(col, spec, playing)
	col.add_child(_rule())
	col.add_child(UiTheme.title("YOUR ATTEMPTS", 13, UiTheme.DIM))
	_board_block(col)


func _result_block(col: VBoxContainer) -> void:
	var ok := challenge.success
	var head := UiTheme.title("COMPLETE" if ok else "NOT THIS TIME", 28,
		UiTheme.GOOD if ok else UiTheme.ALERT)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	var goal := UiTheme.label(str(challenge.spec["text"]), 16, UiTheme.DIM, 600)
	goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(goal)
	var res := challenge.result()
	var line := "%d %s   ·   %d orders   ·   %d points" % [
		int(res["days"]), "day" if int(res["days"]) == 1 else "days", int(res["orders"]), int(res["score"])] if ok \
		else "%s   ·   %d orders   (%s)" % [
			Challenge.progress_phrase(challenge.spec, challenge.progress),
			challenge.orders, challenge.reason]
	var l := UiTheme.label(line, 18, UiTheme.INK, 700)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(l)
	# The card people will paste.
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.card(1.0, 10))
	col.add_child(card)
	var share := UiTheme.label(challenge.share_text(), 16, UiTheme.ACCENT, 700)
	share.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	share.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(share)
	var status := UiTheme.label("", 13, UiTheme.GOOD, 600)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var do_share := func() -> void:
		var how := Challenge.share(challenge.share_text())
		status.text = "Shared." if how == "shared" else "Copied to the clipboard."
	col.add_child(_button("Share result", do_share, true))
	col.add_child(status)


func _buttons_block(col: VBoxContainer, spec: Dictionary, playing: bool) -> void:
	if playing:
		col.add_child(_button("Back to the challenge", close_screen, not challenge.done))
		col.add_child(_button("Start over this week's challenge",
			func() -> void: start_requested.emit(true)))
		col.add_child(_button("Return to my village", func() -> void: leave_requested.emit()))
	else:
		var resume := Challenge.saved_run_matches(spec)
		if resume:
			col.add_child(_button("Resume your attempt", func() -> void: start_requested.emit(false), true))
			col.add_child(_button("Begin a new attempt", func() -> void: start_requested.emit(true)))
		else:
			col.add_child(_button("Begin the challenge", func() -> void: start_requested.emit(true), true))
		var note := UiTheme.label("Your own village is saved first and waits for you.", 12,
			UiTheme.FAINT, 500)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(note)
		col.add_child(_button("Close", close_screen))


func _board_block(col: VBoxContainer) -> void:
	var rows := Challenge.leaderboard(6)
	if rows.is_empty():
		col.add_child(UiTheme.label("None yet. The first attempt is the one to beat.", 14,
			UiTheme.DIM, 500))
		return
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", int(UiTheme.px(14)))
	grid.add_theme_constant_override("v_separation", int(UiTheme.px(4)))
	col.add_child(grid)
	for head: String in ["", "WEEK", "RESULT", "DAYS / ORDERS", "PTS"]:
		grid.add_child(UiTheme.title(head, 11, UiTheme.FAINT))
	var i := 0
	for e: Dictionary in rows:
		i += 1
		var ok := bool(e.get("success", false))
		var tint := UiTheme.INK if ok else UiTheme.DIM
		grid.add_child(UiTheme.label(str(i), 14, UiTheme.GOLD, 800))
		grid.add_child(UiTheme.label("#%d" % int(e.get("week", 0)), 14, tint, 700))
		grid.add_child(UiTheme.label("done" if ok else "%d / %d" % [
			int(e.get("progress", 0)), int(e.get("target", 0))], 14,
			UiTheme.GOOD if ok else UiTheme.ALERT, 600))
		grid.add_child(UiTheme.label("%d / %d" % [int(e.get("days", 0)), int(e.get("orders", 0))],
			14, tint, 600))
		grid.add_child(UiTheme.label(str(int(e.get("score", 0))), 14, tint, 800))


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = UiTheme.EDGE
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _button(text: String, pressed: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, UiTheme.px(44))
	b.focus_mode = Control.FOCUS_ALL
	UiTheme.style_button(b, 16, primary)
	b.pressed.connect(pressed)
	return b
