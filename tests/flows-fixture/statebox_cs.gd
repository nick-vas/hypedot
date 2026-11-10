extends Node
# A second autoload whose reset method has the name a C# autoload gives it (Godot calls a C# method by the name it is written with).

var coins := 0


func add_coin() -> void:
	coins += 1


func HyperdotResetFlowState() -> String:
	var found := "" if coins == 0 else "%d coin(s) left by the last flow" % coins
	coins = 0
	return found
