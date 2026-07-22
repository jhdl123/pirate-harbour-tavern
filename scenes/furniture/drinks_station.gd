extends StaticBody2D


func interact(player: Node) -> void:
	if player.carrying_item == "":
		player.set_carried_item("grog")
		print("Picked up grog")
	else:
		print("Already carrying something")
