# Loads one script, scene or resource and, for a script or scene, checks that it compiles or instantiates. Run by the
# plugin's edit hook (hooks/edit-check.ps1) after each edit, so a broken file is reported when it breaks and not at the end
# of the turn:
#   godot --headless --path <project> -s <this file> -- res://path/to/file.gd
# It is validate.gd for one file (the same loads and checks, without the stale-key and shader passes), so it costs about
# the engine's start-up (0.2 s) whatever the project's size. Exit code 1 and a "@@editcheck" line when the file is broken.
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		print("@@editcheck usage: -- res://path")
		quit(2)
		return
	var problem := _check(args[0])
	if problem != "":
		print("@@editcheck %s: %s" % [args[0], problem])
	quit(1 if problem != "" else 0)


func _check(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "file not found"
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null:
		return "failed to load"
	if resource is Script:
		var script := resource as Script
		var abstract: bool = script.has_method("is_abstract") and script.call("is_abstract")
		if not script.can_instantiate() and not abstract:
			return "script does not compile"
	elif resource is PackedScene:
		# Instantiate without adding to the tree: constructors run, _ready does not.
		var node := (resource as PackedScene).instantiate()
		if node == null:
			return "scene does not instantiate"
		node.free()
	return ""
