extends Node

## Developer controls for inspecting and balancing customer behaviour.
##
## [b]Deliberately keyboard-only and off by default.[/b] The brief asks not
## to clutter the player UI, so this draws nothing until toggled and adds no
## nodes to the HUD - it prints to the console and writes JSON, the same way
## the existing beverage and group diagnostics panels behave.
##
## Nothing here reaches into customer internals directly. Force-spawning goes
## through GameManager's ordinary spawn path (setting
## [code]forced_customer_type[/code] and letting the production code run),
## which is the lesson from the group work: a diagnostic spawn that bypasses
## the real path tests the diagnostic, not the game.

@export_category("Wiring")

## Where force-spawns are routed. Found by group if left unset.
@export var game_manager: Node

## Types offered by the force-spawn cycle.
@export var customer_types: Array[CustomerType] = []

## Written into the identity seed when deterministic mode is on.
@export var deterministic_seed_base: int = 20260806


@export_category("Keys")

@export var toggle_key: Key = KEY_F9
@export var cycle_type_key: Key = KEY_F11
@export var force_spawn_key: Key = KEY_F12
@export var deterministic_key: Key = KEY_K
@export var verbose_scoring_key: Key = KEY_L
@export var print_profile_key: Key = KEY_P
@export var export_report_key: Key = KEY_O
@export var stress_test_key: Key = KEY_U

## Exports the navigation quality report - path efficiency, stalls,
## recoveries and whether organic movement actually reached each actor.
@export var export_navigation_key: Key = KEY_N

## Cycles which live customer P/L/verbose scoring targets. Previously both
## always meant "customer 0" - there was no in-game customer-picker at all.
@export var cycle_customer_key: Key = KEY_I

## Where the behaviour report is written.
@export var report_path: String = "user://customer_behaviour_report.json"

## Where the navigation report is written.
@export var navigation_report_path: String = "user://navigation_report.json"

## How many customers a stress run spawns, cycling through every type.
@export var stress_test_customers: int = 24


var enabled: bool = false
var deterministic: bool = false
var verbose_scoring: bool = false

var _selected_type_index: int = 0
var _selected_customer_index: int = 0
var _report: CustomerBehaviourReport = null


func _ready() -> void:
	_report = CustomerBehaviourReport.new()
	_report.attach()

	if game_manager == null:
		game_manager = get_tree().get_first_node_in_group(&"game_manager")

	if customer_types.is_empty() and game_manager != null:
		var borrowed: Variant = game_manager.get(&"customer_types")

		if borrowed is Array:
			for entry: Variant in borrowed:
				var type: CustomerType = entry as CustomerType

				if type != null:
					customer_types.append(type)


func _unhandled_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey

	if key_event == null or not key_event.pressed or key_event.echo:
		return

	if key_event.keycode == toggle_key:
		enabled = not enabled
		print(
			"[CustomerBehaviour] developer controls %s"
			% ("ENABLED" if enabled else "disabled")
		)
		_print_help()
		get_viewport().set_input_as_handled()
		return

	if not enabled:
		return

	match key_event.keycode:
		cycle_type_key:
			_cycle_type()
		force_spawn_key:
			_force_spawn()
		deterministic_key:
			_toggle_deterministic()
		verbose_scoring_key:
			_toggle_verbose()
		print_profile_key:
			_print_selected_profile()
		export_report_key:
			_export_report()
		stress_test_key:
			_run_stress_test()
		export_navigation_key:
			_export_navigation_report()
		cycle_customer_key:
			_cycle_customer()
		_:
			return

	get_viewport().set_input_as_handled()


func _print_help() -> void:
	if not enabled:
		return

	print("  F11 cycle type   F12 force spawn   K deterministic")
	print("  L verbose scores  P print profile   O export report")
	print("  U mixed-type stress test   N navigation report")
	print("  I cycle inspected customer (targets L and P)")


func _cycle_type() -> void:
	if customer_types.is_empty():
		print("[CustomerBehaviour] no customer types wired.")
		return

	_selected_type_index = (
		_selected_type_index + 1
	) % customer_types.size()

	var type: CustomerType = customer_types[_selected_type_index]

	print(
		"[CustomerBehaviour] selected '%s' (%s)"
		% [type.display_name, type.get_type_id()]
	)

	_print_intent_weights(type)


func _print_intent_weights(type: CustomerType) -> void:
	if type.visit_intent_weights.is_empty():
		print("    intents: (unweighted - any enabled intent)")
		return

	var parts: Array[String] = []

	for intent_id: String in type.visit_intent_weights:
		parts.append(
			"%s %s" % [intent_id, type.visit_intent_weights[intent_id]]
		)

	print("    intents: " + ", ".join(parts))


func _force_spawn() -> void:
	if game_manager == null or customer_types.is_empty():
		print("[CustomerBehaviour] cannot force-spawn: nothing wired.")
		return

	var type: CustomerType = customer_types[_selected_type_index]

	if not type.enabled:
		print(
			"[CustomerBehaviour] '%s' is disabled and will not spawn."
			% type.display_name
		)
		return

	game_manager.set(&"forced_customer_type", type)

	if game_manager.has_method("spawn_customer"):
		game_manager.call("spawn_customer")
		print("[CustomerBehaviour] force-spawned a %s." % type.display_name)
	else:
		print(
			"[CustomerBehaviour] queued a %s for the next spawn."
			% type.display_name
		)


func _toggle_deterministic() -> void:
	deterministic = not deterministic

	if game_manager != null:
		game_manager.set(
			&"deterministic_identity_seed",
			deterministic_seed_base if deterministic else 0
		)

	print(
		"[CustomerBehaviour] deterministic decisions %s"
		% ("ON" if deterministic else "off")
	)


## Targets only the inspected customer (see _cycle_customer()) rather than
## every customer in the room - a per-decision score dump for one customer
## is readable; one for the whole tavern at once is a firehose nobody reads.
func _toggle_verbose() -> void:
	verbose_scoring = not verbose_scoring

	var customers: Array[Node] = get_tree().get_nodes_in_group(&"navigation_customers")

	for customer: Node in customers:
		var brain: Variant = customer.get(&"_brain")

		if brain == null:
			continue

		brain.set(&"deterministic_decisions", deterministic)

	var inspected: Node = _get_selected_customer(customers)

	if inspected == null:
		print("[CustomerBehaviour] no customers in the tavern.")
		return

	var brain: Variant = inspected.get(&"_brain")

	if brain != null:
		brain.set(&"verbose_scoring", verbose_scoring)

	print(
		"[CustomerBehaviour] verbose scoring %s on %s"
		% [("ON" if verbose_scoring else "off"), inspected.name]
	)


## Moves which customer P (profile) and L (verbose scoring) target. There is
## no click-to-select in this deliberately keyboard-only panel - cycling is
## the whole "picker".
func _cycle_customer() -> void:
	var customers: Array[Node] = get_tree().get_nodes_in_group(&"navigation_customers")

	if customers.is_empty():
		print("[CustomerBehaviour] no customers in the tavern.")
		return

	_selected_customer_index = (_selected_customer_index + 1) % customers.size()

	print(
		"[CustomerBehaviour] inspecting %s (%d/%d)"
		% [
			customers[_selected_customer_index].name,
			_selected_customer_index + 1, customers.size(),
		]
	)

	if verbose_scoring:
		# Move the live filter along with the selection, rather than leaving
		# it on whichever customer happened to hold it before.
		for customer: Node in customers:
			var brain: Variant = customer.get(&"_brain")

			if brain != null:
				brain.set(&"verbose_scoring", false)

		var brain: Variant = customers[_selected_customer_index].get(&"_brain")

		if brain != null:
			brain.set(&"verbose_scoring", true)


## Wraps the selection index defensively - the roster can shrink (customers
## leave) between a selection and the next key press.
func _get_selected_customer(customers: Array[Node]) -> Node:
	if customers.is_empty():
		return null

	return customers[_selected_customer_index % customers.size()]


## Dumps one live customer's full behaviour profile - identity, traits,
## intent, current action and cooldowns. The customer currently selected via
## _cycle_customer() (I), defaulting to the first one found.
func _print_selected_profile() -> void:
	var customers: Array[Node] = get_tree().get_nodes_in_group(&"navigation_customers")
	var customer: Node = _get_selected_customer(customers)

	if customer == null:
		print("[CustomerBehaviour] no customers in the tavern.")
		return

	var identity: Variant = customer.get(&"identity")

	if identity == null:
		print("[CustomerBehaviour] that customer has no identity.")
		return

	print("\n=== Customer Behaviour Profile: %s ===" % customer.name)
	print(JSON.stringify(identity.get_diagnostics(), "\t"))

	var brain: Variant = customer.get(&"_brain")

	if brain != null:
		var current: Variant = brain.call("get_current_activity")

		print(
			"current action: %s"
			% (String(current.activity_id) if current != null else "(none)")
		)
		print("cooldowns: %s" % JSON.stringify(brain.call("get_cooldowns")))

	var needs: Variant = customer.get(&"needs")

	if needs != null:
		print(
			"wealth %s  thirst %.2f  mood %.2f  visit remaining %.1fm"
			% [
				needs.get(&"wealth"), needs.get(&"thirst"),
				needs.get(&"mood"), needs.get(&"remaining_visit_minutes"),
			]
		)

	if customer.has_method("get_diagnostics_snapshot"):
		print(
			"snapshot: %s"
			% JSON.stringify(customer.call("get_diagnostics_snapshot"))
		)


func _export_report() -> void:
	print("\n" + _report.format_summary())

	if _report.export_json(report_path):
		print(
			"[CustomerBehaviour] report written to %s"
			% ProjectSettings.globalize_path(report_path)
		)


## Spawns a mixed run covering every enabled type, then prints the aggregate.
## Uses the ordinary spawn path one type at a time rather than a bulk
## shortcut, so the run exercises what play exercises.
func _run_stress_test() -> void:
	if game_manager == null or customer_types.is_empty():
		print("[CustomerBehaviour] cannot run stress test: nothing wired.")
		return

	var enabled_types: Array[CustomerType] = []

	for type: CustomerType in customer_types:
		if type != null and type.enabled:
			enabled_types.append(type)

	if enabled_types.is_empty():
		print("[CustomerBehaviour] no enabled types to stress.")
		return

	_report.clear()

	print(
		"[CustomerBehaviour] stress test: %d customers across %d types"
		% [stress_test_customers, enabled_types.size()]
	)

	for index: int in stress_test_customers:
		game_manager.set(
			&"forced_customer_type", enabled_types[index % enabled_types.size()]
		)

		if game_manager.has_method("spawn_customer"):
			game_manager.call("spawn_customer")

		await get_tree().create_timer(0.4).timeout

	print("[CustomerBehaviour] stress spawns complete - press O for the report.")


func get_report() -> CustomerBehaviourReport:
	return _report


## Prints and writes the navigation quality report.
##
## Separate from the behaviour report because it answers a different
## question: the behaviour report says what customers chose to do, this says
## whether they could physically get there without grinding.
func _export_navigation_report() -> void:
	var report: Dictionary = NavigationReport.build(get_tree())

	print("\n" + NavigationReport.format_summary(report))

	if NavigationReport.export_json(get_tree(), navigation_report_path):
		print(
			"[CustomerBehaviour] navigation report written to %s"
			% ProjectSettings.globalize_path(navigation_report_path)
		)
