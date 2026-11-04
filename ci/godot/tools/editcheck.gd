# Loads one script, scene, resource or shader and checks that a script or shader compiles. A scene is loaded, not instantiated: loading
# compiles its scripts and reports a missing reference, and instantiating would run the project's own code (_init) from a
# hook that starts without being asked. Run by the
# plugin's edit hook (hooks/edit-check.ps1) after each edit, so a broken file is reported when it breaks and not at the end
# of the turn:
#   godot --headless --path <project> -s <this file> -- res://path/to/file.gd
# It is validate.gd for one file (the same loads and script check, without instantiating scenes or the stale-key and
# shader passes), so it costs about the engine's start-up (0.2 s) whatever the project's size. Exit code 1 and a "@@editcheck" line when the file is broken.
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
	elif resource is Shader:
		# Loading does not compile a shader headless; asking for its uniforms does, and prints SHADER ERROR if it is broken
		# (validate.gd does the same, with different text so no compile cache can skip it).
		var fresh := Shader.new()
		fresh.code = (resource as Shader).code + "\n// validate\n"
		fresh.get_shader_uniform_list()
	return ""
