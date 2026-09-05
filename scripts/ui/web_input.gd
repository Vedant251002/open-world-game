extends RefCounted
class_name WebInput
## A real HTML text field, laid over the canvas, for giving orders on a phone.
##
## Godot cannot raise the keyboard on iOS Safari, and it is not a bug in Godot.
## Safari only opens the keyboard when an input is focused inside the user
## gesture that asked for it, and Godot's input pipeline is a queue: the touch
## on TALK is dispatched a frame later, so by the time any GDScript runs the
## gesture is over and the browser refuses. Nothing arranged on the Godot side
## can get inside that window.
##
## So the field is not a Godot field. It is an ordinary <input> element sitting
## above the canvas, and tapping an ordinary input opens the keyboard on every
## browser there is — no gesture timing to lose, because the tap IS on the
## input. The phrases come along for the ride so the whole panel is one thing.
##
## Everything here is inert off the web, where the Godot LineEdit is fine.

const SETUP := """
(function () {
  if (window.__dgt) { return; }
  var wrap = document.createElement('div');
  wrap.style.cssText = 'position:fixed;left:0;right:0;bottom:0;z-index:2147483000;'
    + 'display:none;box-sizing:border-box;padding:10px 12px 14px 12px;'
    + 'background:rgba(15,14,13,0.96);border-top:1px solid rgba(255,255,255,0.16);'
    + 'font-family:-apple-system,BlinkMacSystemFont,system-ui,sans-serif;';

  var label = document.createElement('div');
  label.style.cssText = 'color:#bdb8ae;font-size:15px;margin:0 0 8px 2px;';

  var chips = document.createElement('div');
  chips.style.cssText = 'display:flex;flex-wrap:wrap;gap:8px;margin-bottom:10px;';

  var row = document.createElement('div');
  row.style.cssText = 'display:flex;gap:8px;align-items:stretch;';

  var input = document.createElement('input');
  input.type = 'text';
  input.autocomplete = 'off';
  input.autocorrect = 'on';
  input.autocapitalize = 'sentences';
  input.enterKeyHint = 'send';
  input.style.cssText = 'flex:1;min-width:0;font-size:17px;padding:13px 12px;'
    + 'border-radius:8px;border:1px solid #6a655c;background:#1d1b19;'
    + 'color:#f4f0e9;-webkit-appearance:none;';

  function btn(text, bg) {
    var b = document.createElement('button');
    b.type = 'button';
    b.textContent = text;
    b.style.cssText = 'font-size:16px;padding:13px 16px;border-radius:8px;'
      + 'border:1px solid #6a655c;background:' + bg + ';color:#f4f0e9;'
      + 'white-space:nowrap;-webkit-appearance:none;';
    return b;
  }
  var send = btn('Send', '#4a4238');
  var shut = btn('\\u2715', '#2a2724');

  row.appendChild(input);
  row.appendChild(send);
  row.appendChild(shut);
  wrap.appendChild(label);
  wrap.appendChild(chips);
  wrap.appendChild(row);
  document.body.appendChild(wrap);

  var state = { sent: null, closed: false };

  function submit(text) {
    if (!text) { return; }
    state.sent = text;
    input.value = '';
    input.blur();
    wrap.style.display = 'none';
  }
  send.addEventListener('click', function () { submit(input.value.trim()); });
  shut.addEventListener('click', function () {
    state.closed = true;
    input.value = '';
    input.blur();
    wrap.style.display = 'none';
  });
  input.addEventListener('keydown', function (e) {
    if (e.key === 'Enter') { e.preventDefault(); submit(input.value.trim()); }
  });

  window.__dgt = {
    show: function (cfg) {
      label.textContent = cfg.title || '';
      input.placeholder = cfg.hint || '';
      input.value = '';
      state.sent = null;
      state.closed = false;
      while (chips.firstChild) { chips.removeChild(chips.firstChild); }
      (cfg.phrases || []).forEach(function (p) {
        var c = btn(p, '#332f2a');
        c.addEventListener('click', function () { submit(p); });
        chips.appendChild(c);
      });
      wrap.style.display = 'block';
      // Worth a try: it works on Android and on desktop browsers. Where it is
      // refused the player taps the field, which is the whole point of the
      // field being real.
      try { input.focus({ preventScroll: true }); } catch (err) { input.focus(); }
    },
    hide: function () { wrap.style.display = 'none'; input.blur(); },
    take: function () { var s = state.sent; state.sent = null; return s; },
    takeClosed: function () { var c = state.closed; state.closed = false; return c; },
    open: function () { return wrap.style.display !== 'none'; }
  };
})();
"""

var _ready_done := false


static func available() -> bool:
	return OS.has_feature("web")


func setup() -> void:
	if _ready_done or not available():
		return
	JavaScriptBridge.eval(SETUP, true)
	_ready_done = true


func show_bar(title: String, hint: String, phrases: Array) -> void:
	if not available():
		return
	setup()
	var cfg := JSON.stringify({"title": title, "hint": hint, "phrases": phrases})
	JavaScriptBridge.eval("window.__dgt && window.__dgt.show(%s)" % cfg, true)


func hide_bar() -> void:
	if not available():
		return
	JavaScriptBridge.eval("window.__dgt && window.__dgt.hide()", true)


## Whatever the player has sent since the last call, or "" for nothing yet.
func take() -> String:
	if not available():
		return ""
	var v: Variant = JavaScriptBridge.eval(
		"(window.__dgt && window.__dgt.take()) || ''", true)
	return str(v) if v != null else ""


## True once, if the player dismissed the panel rather than sending anything.
func take_closed() -> bool:
	if not available():
		return false
	var v: Variant = JavaScriptBridge.eval(
		"!!(window.__dgt && window.__dgt.takeClosed())", true)
	return bool(v) if v != null else false
