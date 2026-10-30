# names.gd — display-name sanitizing + original bot callsign generator.
class_name Names
extends RefCounted


const MAX_LEN := 24


static func sanitize(raw: String) -> String:
	var s := raw.strip_edges()
	var allowed := ""
	var prev_sep := false
	for ch in s:
		var c := ch
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "-" or c == "_" or c == " " or c == ".":
			allowed += c
			prev_sep = false
		else:
			if not prev_sep:
				allowed += "_"
				prev_sep = true
	allowed = allowed.strip_edges()
	var had_trailing := allowed != "" and (allowed.ends_with("_") or allowed.ends_with(" "))
	while allowed != "" and (allowed.ends_with("_") or allowed.ends_with(" ")):
		allowed = allowed.left(allowed.length() - 1)
	if had_trailing and allowed != "" and not (allowed.ends_with("_") or allowed.ends_with(" ")):
		allowed += "_"
	if allowed.length() > MAX_LEN:
		allowed = allowed.substr(0, MAX_LEN)
	if allowed == "":
		allowed = "Skyfarer_%03d" % (randi() % 1000)
	return allowed


const CALL_PREFIX := ["Frost", "Windward", "Cinder", "Northsail", "Vantage", "Kestrel", "Brackish", "Warden", "Halcyon", "Drift", "Overlook", "Banana Reef", "Oaklatch"]
const CALL_SUFFIX := ["1652", "3", "OLIVE", "Tide", "B7", "Nova", "Vector", "Marlow", "Anchor", "914"]


static func random_callsign() -> String:
	return "%s_%s" % [CALL_PREFIX[randi() % CALL_PREFIX.size()], CALL_SUFFIX[randi() % CALL_SUFFIX.size()]]
