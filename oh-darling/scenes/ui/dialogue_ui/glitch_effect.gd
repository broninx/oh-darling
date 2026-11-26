@tool
class_name GlitchTextEffect
extends RichTextEffect
## Custom BBCode effect: [glitch]text[/glitch]
## Some letters jump, flicker and turn red for a moment, like a broken signal.
## Options: rate (changes per second), level (jump in pixels),
## chance (0 to 1, part of the letters that glitch at the same time),
## tint (0 to 1, how red a glitching letter turns; 0 = no red, default 0.7).
## Example: [glitch rate=14 level=5 chance=0.2]Someone CHOSE you.[/glitch]
## Subtle:  [glitch rate=6 level=1 chance=0.03 tint=0.3]...[/glitch]

var bbcode: String = "glitch"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var rate: float = char_fx.env.get("rate", 12.0)
	var level: float = char_fx.env.get("level", 4.0)
	var chance: float = char_fx.env.get("chance", 0.15)
	var tint: float = clampf(char_fx.env.get("tint", 0.7), 0.0, 1.0)
	var tick: int = int(char_fx.elapsed_time * rate)
	var h: int = hash(Vector2i(char_fx.range.x, tick))
	if float(absi(h) % 1000) / 1000.0 < chance:
		var angle: float = float(absi(h) % 628) / 100.0
		char_fx.offset = Vector2(cos(angle), sin(angle)) * level
		char_fx.color = char_fx.color.lerp(Color(1.0, 0.15, 0.25), tint)
		if absi(h) % 3 == 0:
			char_fx.color.a *= 0.3
	return true
