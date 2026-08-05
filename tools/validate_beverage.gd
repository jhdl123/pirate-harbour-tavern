extends SceneTree

func _init() -> void:
	var registry: BeverageRegistry = load("res://Data/beverage/beverage_registry.tres")
	var report := BeverageValidator.validate(registry)

	print("=== BEVERAGE VALIDATION ===")
	print(report.get_summary())
	print("")

	for line in report.get_lines():
		print("  " + line)

	quit(1 if report.has_errors() else 0)
