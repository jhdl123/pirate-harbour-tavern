extends StaticBody2D

func interact(player: Node) -> void:
	if player.carrying_item == ItemType.Type.NONE:
		player.set_carried_item(ItemType.Type.GROG)
		print("Picked up grog")
	else:
		print("Already carrying something")
