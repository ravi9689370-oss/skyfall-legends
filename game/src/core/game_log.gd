# game_log.gd — tiny stdout logger with tags. Used by server and client alike.
class_name GameLog
extends RefCounted


static var enabled := true


static func info(tag: String, msg: String) -> void:
	if not enabled:
		return
	print("[INFO %s] %s" % [tag, msg])


static func warn(tag: String, msg: String) -> void:
	if not enabled:
		return
	print("[WARN %s] %s" % [tag, msg])


static func error(tag: String, msg: String) -> void:
	if not enabled:
		return
	print("[ERROR %s] %s" % [tag, msg])
