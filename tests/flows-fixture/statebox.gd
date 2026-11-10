extends Node
# An autoload that holds run state, as a game's run or save manager would, and resets itself for the flows runner.

var relics := 0


func add_relic() -> void:
	relics += 1


func hyperdot_reset_flow_state() -> String:
	var found := "" if relics == 0 else "%d relic(s) left by the last flow" % relics
	relics = 0
	return found
