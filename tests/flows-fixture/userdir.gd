extends Control
# Prints where user:// is, so the flows self-test can check that the runner points it at a throwaway folder.


func _ready() -> void:
	print("[userdir] ", OS.get_user_data_dir())
