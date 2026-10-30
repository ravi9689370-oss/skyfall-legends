# run_tests.gd — headless entry: `godot --headless --path . -s res://game/tests/run_tests.gd`
# Spawns an in-tree TestRunner node so we can use frames + real networking.
extends SceneTree


func _initialize() -> void:
	var runner := Node.new()
	runner.set_script(load("res://game/tests/test_runner.gd"))
	root.add_child(runner)
