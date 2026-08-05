extends Node

## Verification for the daily cycle, modifier and demand framework.
##
## [codeblock]
## godot --headless --fixed-fps 60 res://tests/phase_4_daily_cycle_test.tscn
## [/codeblock]

const MAIN_SCENE_PATH: String = "res://scenes/main/main.tscn"

var _main: Node = null
var _failures: Array[String] = []
var _passes: Array[String] = []


func _ready() -> void:
	_main = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()
	add_child(_main)
	await get_tree().process_frame
	await _wait_frames(30)

	_test_schedule_maths()
	_test_midnight_crossing()
	await _test_lifecycle_transitions()
	_test_modifier_order()
	_test_stacking()
	_test_scoped_modifiers()
	_test_expiry()
	_test_unknown_target()
	_test_demand_profile()
	await _test_arrival_gate()
	await _test_end_day_skip()
	await _test_idempotency_and_freeze()
	_test_warnings_configured()

	_report()


# --- Schedule ----------------------------------------------------------------

func _test_schedule_maths() -> void:
	var schedule: TavernSchedule = Tavern.schedule

	if schedule == null:
		_fail("SCHED", "No schedule loaded.")
		return

	_pass("SCHED", schedule.describe())

	# 17:00 prep, 18:00 open, 00:30 last orders, 01:00 closing, 01:30 closed.
	var cases: Array = [
		[17 * 60 + 30, TavernLifecycle.State.PREPARING],
		[19 * 60, TavernLifecycle.State.OPEN],
		[23 * 60, TavernLifecycle.State.OPEN],
		[0 * 60 + 45, TavernLifecycle.State.LAST_ORDERS],
		[1 * 60 + 10, TavernLifecycle.State.CLOSING],
		[2 * 60, TavernLifecycle.State.CLOSED],
		[12 * 60, TavernLifecycle.State.CLOSED],
	]

	for entry: Array in cases:
		var minutes: int = entry[0]
		var expected: TavernLifecycle.State = entry[1]
		var actual: TavernLifecycle.State = schedule.get_state_at(minutes)

		if actual != expected:
			_fail(
				"SCHED",
				"%02d:%02d gave %s, expected %s."
				% [
					minutes / 60,
					minutes % 60,
					TavernLifecycle.State.keys()[actual],
					TavernLifecycle.State.keys()[expected],
				]
			)
			return

	_pass("SCHED", "All 7 time points resolve to the correct state.")


func _test_midnight_crossing() -> void:
	var schedule: TavernSchedule = Tavern.schedule

	# 23:50 -> last orders at 00:30 is 40 minutes, not a negative number.
	var remaining: int = schedule.get_minutes_until_next_transition(
		23 * 60 + 50
	)

	if remaining != 40:
		_fail(
			"MIDNIGHT",
			"23:50 to last orders gave %d minutes, expected 40." % remaining
		)
		return

	_pass("MIDNIGHT", "23:50 -> 00:30 correctly measured as 40 minutes.")

	var next: TavernLifecycle.State = schedule.get_next_state(23 * 60 + 50)

	if next != TavernLifecycle.State.LAST_ORDERS:
		_fail("MIDNIGHT", "Next state after 23:50 was not LAST_ORDERS.")
		return

	_pass("MIDNIGHT", "Next state across midnight is LAST_ORDERS.")


## Walk a whole trading day and confirm every state is entered in order.
func _test_lifecycle_transitions() -> void:
	var seen: Array[String] = []

	Tavern.operating_state_changed.connect(
		func(_p: TavernLifecycle.State, n: TavernLifecycle.State, _r: StringName) -> void:
			seen.append(TavernLifecycle.State.keys()[n])
	)

	WorldTime.set_time(WorldTime.get_day(), 16, 55)
	await _wait_frames(5)

	# The starting hour is now 17:00, so PREPARING may already be the current
	# state rather than one transitioned into during the walk.
	seen.append(TavernLifecycle.State.keys()[Tavern.get_state()])

	# Walk the clock forward in steps rather than one jump, so each
	# transition is entered the way it would be during play.
	for step: int in range(20):
		WorldTime.advance_minutes(30)
		await _wait_frames(3)

	for expected: String in ["PREPARING", "OPEN", "LAST_ORDERS", "CLOSING", "CLOSED"]:
		if not seen.has(expected):
			_fail(
				"CYCLE",
				"State %s was never entered. Saw: %s"
				% [expected, ", ".join(seen)]
			)
			return

	_pass("CYCLE", "Full day entered: %s." % ", ".join(seen))


# --- Modifiers ---------------------------------------------------------------

func _test_modifier_order() -> void:
	Modifiers.clear_all()

	# base 1.0, +1.0 add, x2.0 multiply, max 3.0  ->  (1+1)*2 = 4, clamped 3.
	Modifiers.add(_make(&"t_add", Modifier.Operation.ADD, 1.0))
	Modifiers.add(_make(&"t_mul", Modifier.Operation.MULTIPLY, 2.0))
	Modifiers.add(_make(&"t_max", Modifier.Operation.MAXIMUM, 3.0))

	var result: float = Modifiers.evaluate(
		ModifierTargets.CUSTOMER_SPENDING, 1.0
	)

	if not is_equal_approx(result, 3.0):
		_fail("ORDER", "Expected 3.0 (add, then multiply, then clamp), got %.2f" % result)
		return

	_pass("ORDER", "add -> multiply -> clamp gives 3.00 as documented.")

	# Override ignores everything above it.
	Modifiers.add(_make(&"t_over", Modifier.Operation.OVERRIDE, 0.0))

	result = Modifiers.evaluate(ModifierTargets.CUSTOMER_SPENDING, 1.0)

	if not is_equal_approx(result, 0.0):
		_fail("ORDER", "Override did not win; got %.2f" % result)
		return

	_pass("ORDER", "Override applied last and absolutely.")

	print(Modifiers.explain_text(ModifierTargets.CUSTOMER_SPENDING, 1.0))

	Modifiers.clear_all()


func _test_stacking() -> void:
	Modifiers.clear_all()

	var preset: ModifierPreset = load(
		"res://Data/modifiers/busy_harbour.tres"
	) as ModifierPreset

	if preset == null:
		_fail("STACK", "Could not load the busy_harbour preset.")
		return

	for modifier: Modifier in preset.build_modifiers():
		Modifiers.add(modifier)

	var once: float = Modifiers.evaluate(
		ModifierTargets.CUSTOMER_ARRIVAL_RATE, 1.0
	)

	# Trigger the same event a second time. REPLACE stacking means the value
	# must not compound.
	for modifier: Modifier in preset.build_modifiers():
		Modifiers.add(modifier)

	var twice: float = Modifiers.evaluate(
		ModifierTargets.CUSTOMER_ARRIVAL_RATE, 1.0
	)

	if not is_equal_approx(once, twice):
		_fail(
			"STACK",
			"Re-triggering the event changed demand %.2f -> %.2f."
			% [once, twice]
		)
		return

	_pass("STACK", "Re-triggering an event did not compound (%.2f)." % twice)

	Modifiers.remove_source(preset.preset_id)

	var cleared: float = Modifiers.evaluate(
		ModifierTargets.CUSTOMER_ARRIVAL_RATE, 1.0
	)

	if not is_equal_approx(cleared, 1.0):
		_fail("STACK", "remove_source left %.2f behind." % cleared)
		return

	_pass("STACK", "remove_source() removed every contribution.")


func _test_scoped_modifiers() -> void:
	Modifiers.clear_all()

	var sailor_only: Modifier = _make(
		&"ship_arrival", Modifier.Operation.MULTIPLY, 2.0
	)
	sailor_only.target = ModifierTargets.CUSTOMER_TYPE_WEIGHT
	sailor_only.required_tags = [&"sailor"]
	sailor_only.scope = &"sailor"

	Modifiers.add(sailor_only)

	var for_sailor: float = Modifiers.evaluate(
		ModifierTargets.CUSTOMER_TYPE_WEIGHT, 1.0, { "tags": [&"sailor"] }
	)

	var for_merchant: float = Modifiers.evaluate(
		ModifierTargets.CUSTOMER_TYPE_WEIGHT, 1.0, { "tags": [&"merchant"] }
	)

	if not is_equal_approx(for_sailor, 2.0):
		_fail("SCOPE", "Sailor weight was %.2f, expected 2.0." % for_sailor)
		return

	if not is_equal_approx(for_merchant, 1.0):
		_fail("SCOPE", "Merchant weight was %.2f, expected 1.0." % for_merchant)
		return

	_pass("SCOPE", "Tagged modifier applied to sailors only (2.00 vs 1.00).")

	Modifiers.clear_all()


func _test_expiry() -> void:
	Modifiers.clear_all()

	var temporary: Modifier = _make(
		&"short_event", Modifier.Operation.MULTIPLY, 3.0
	)
	temporary.end_minutes = WorldTime.get_total_minutes_precise() + 10.0

	Modifiers.add(temporary)

	var during: float = Modifiers.evaluate(
		ModifierTargets.CUSTOMER_SPENDING, 1.0
	)

	# Skip past the expiry in one jump, as ending a day would.
	WorldTime.advance_minutes(60)

	var after: float = Modifiers.evaluate(
		ModifierTargets.CUSTOMER_SPENDING, 1.0
	)

	if not is_equal_approx(during, 3.0) or not is_equal_approx(after, 1.0):
		_fail(
			"EXPIRY",
			"Expected 3.00 then 1.00, got %.2f then %.2f." % [during, after]
		)
		return

	_pass("EXPIRY", "Modifier expiring during a time skip stopped applying.")

	Modifiers.clear_all()


func _test_unknown_target() -> void:
	var bogus: Modifier = Modifier.create(
		&"typo_source", &"custmoer_arrival_rate",
		Modifier.Operation.MULTIPLY, 5.0
	)

	Modifiers.add(bogus)

	var report: Dictionary = Modifiers.build_report_section()

	if report.get("unknown_targets", {}).is_empty():
		_fail("UNKNOWN", "A misspelt target was accepted without warning.")
		return

	_pass("UNKNOWN", "Misspelt target recorded: %s" % str(
		report["unknown_targets"].keys()
	))

	Modifiers.clear_all()


## Modifier maths is tested on CUSTOMER_SPENDING rather than the arrival rate.
##
## The demand controller continuously owns modifiers on the arrival rate and
## re-adds them every few world minutes, so a test asserting an exact value
## there would be measuring the controller as well as the maths.
func _make(
	source: StringName,
	operation: Modifier.Operation,
	value: float
) -> Modifier:
	var modifier: Modifier = Modifier.create(
		source, ModifierTargets.CUSTOMER_SPENDING, operation, value
	)
	modifier.stacking = Modifier.Stacking.REPLACE
	return modifier


# --- Demand ------------------------------------------------------------------

func _test_demand_profile() -> void:
	var profile: DemandProfile = load(
		"res://Data/tavern/default_demand_profile.tres"
	) as DemandProfile

	if profile == null:
		_fail("DEMAND", "Could not load the demand profile.")
		return

	var quiet: float = profile.get_multiplier_at(11 * 60)
	var peak: float = profile.get_multiplier_at(21 * 60)

	if peak <= quiet:
		_fail(
			"DEMAND",
			"Peak (%.2f) is not above quiet (%.2f)." % [peak, quiet]
		)
		return

	_pass(
		"DEMAND",
		"11:00 = %.2f (%s), 21:00 = %.2f (%s)."
		% [quiet, profile.describe_level(quiet), peak, profile.describe_level(peak)]
	)

	# Interpolation: a point between two keyframes must sit between them.
	var between: float = profile.get_multiplier_at(19 * 60)
	var at_18: float = profile.get_multiplier_at(18 * 60)
	var at_21: float = profile.get_multiplier_at(21 * 60)

	if between <= min(at_18, at_21) or between >= max(at_18, at_21):
		_fail("DEMAND", "19:00 (%.2f) is not between 18:00 and 21:00." % between)
		return

	_pass("DEMAND", "Interpolation is smooth: 19:00 = %.2f." % between)


func _test_arrival_gate() -> void:
	var manager: Node = _main.get_node_or_null("Managers/GameManager")

	if manager == null:
		_fail("GATE", "No GameManager.")
		return

	# Force a closed period and confirm arrivals are refused for that reason.
	WorldTime.set_time(WorldTime.get_day(), 12, 0)
	await _wait_frames(10)

	if Tavern.is_accepting_arrivals():
		_fail("GATE", "Tavern reports it is accepting arrivals at midday.")
		return

	_pass("GATE", "At 12:00 the tavern is %s and refuses arrivals."
		% Tavern.get_state_name())

	var before: int = int(manager.call(&"get_arrival_rejections").get(
		"tavern_not_open", 0
	))

	manager.call(&"spawn_customer")

	var after: int = int(manager.call(&"get_arrival_rejections").get(
		"tavern_not_open", 0
	))

	if after <= before:
		_fail("GATE", "A spawn during closed hours was not refused.")
		return

	_pass("GATE", "Spawn refused and recorded as 'tavern_not_open'.")


func _test_end_day_skip() -> void:
	# Put the tavern into a closed state so End Day is available.
	WorldTime.set_time(WorldTime.get_day(), 2, 0)
	await _wait_frames(10)

	if not Tavern.can_end_day():
		_fail("ENDDAY", "End Day unavailable while closed (%s)."
			% Tavern.get_state_name())
		return

	_pass("ENDDAY", "End Day available while %s." % Tavern.get_state_name())

	# A scheduled event inside the skipped window must fire exactly once.
	var fired: Array[int] = [0]

	WorldTime.schedule_in(
		240,
		func() -> void: fired[0] += 1,
		&"test_delivery"
	)

	var summary: Dictionary = Tavern.end_day()

	if summary.is_empty():
		_fail("ENDDAY", "end_day() returned no summary.")
		return

	_pass("ENDDAY", "Summary produced with %d fields." % summary.size())

	var result: Dictionary = Tavern.advance_to_next_day()

	await _wait_frames(10)

	if result.is_empty():
		_fail("ENDDAY", "advance_to_next_day() did nothing.")
		return

	_pass(
		"ENDDAY",
		"Skipped %d minutes to %s."
		% [result["minutes_skipped"], result["resumed_at"]]
	)

	if fired[0] != 1:
		_fail(
			"ENDDAY",
			"Scheduled event during the skip fired %d times, expected 1."
			% fired[0]
		)
		return

	_pass("ENDDAY", "Event inside the skipped window fired exactly once.")

	if Tavern.get_state() != TavernLifecycle.State.PREPARING:
		_fail("ENDDAY", "New day did not begin in PREPARING (%s)."
			% Tavern.get_state_name())
		return

	_pass("ENDDAY", "New trading day began in PREPARING.")


## End Day and Start Next Day must be safe to press repeatedly, and the
## summary must not move once frozen.
func _test_idempotency_and_freeze() -> void:
	WorldTime.set_time(WorldTime.get_day(), 2, 0)
	await _wait_frames(10)

	Tavern.stats.record_sale(&"test_ale", 10.0, 2.0)
	Tavern.stats.record(&"customers_served")

	var first: Dictionary = Tavern.end_day()

	if first.is_empty():
		_fail("FREEZE", "end_day() produced nothing while closed.")
		return

	var income_first: float = first["statistics"]["total_income"]

	# Repeated presses must not produce a second, different summary.
	var second: Dictionary = Tavern.end_day()
	var third: Dictionary = Tavern.end_day()

	if second["statistics"]["total_income"] != income_first:
		_fail("FREEZE", "A second end_day() produced different totals.")
		return

	if third["statistics"]["total_income"] != income_first:
		_fail("FREEZE", "A third end_day() produced different totals.")
		return

	_pass("FREEZE", "end_day() is idempotent (income stayed %.0f)." % income_first)

	# Recording after the freeze must not alter the frozen record.
	Tavern.stats.record_sale(&"test_ale", 999.0, 0.0)

	var frozen: Dictionary = Tavern.get_frozen_summary()

	if frozen["statistics"]["total_income"] != income_first:
		_fail(
			"FREEZE",
			"The frozen summary changed after new sales were recorded."
		)
		return

	_pass("FREEZE", "The frozen summary did not move after later sales.")

	# build_record() is the live view; get_record() deliberately returns the
	# frozen one once the day is finalised, which is what the summary screen
	# reads.
	var live: Dictionary = Tavern.stats.build_record()

	if live["total_income"] == income_first:
		_fail("FREEZE", "Live counters stopped updating after the freeze.")
		return

	_pass("FREEZE", "Live counters kept updating (%.0f) behind the frozen record."
		% live["total_income"])

	# Starting the next day resets per-day figures but not the day count.
	var result: Dictionary = Tavern.advance_to_next_day()

	await _wait_frames(10)

	if result.is_empty():
		_fail("FREEZE", "advance_to_next_day() refused after a valid end_day().")
		return

	if Tavern.stats.build_record()["total_income"] != 0.0:
		_fail("FREEZE", "Per-day income was not reset for the new day.")
		return

	_pass("FREEZE", "New day reset per-day totals to zero.")

	# And a second press must do nothing rather than skipping another day.
	var repeat: Dictionary = Tavern.advance_to_next_day()

	if not repeat.is_empty():
		_fail("FREEZE", "advance_to_next_day() ran twice from one end_day().")
		return

	_pass("FREEZE", "advance_to_next_day() is guarded against repeat presses.")


func _test_warnings_configured() -> void:
	var schedule: TavernSchedule = Tavern.schedule

	if schedule.warning_offsets_minutes.is_empty():
		_fail("WARN", "No transition warnings are configured.")
		return

	_pass(
		"WARN",
		"Warnings configured at %s minutes before each transition."
		% str(schedule.warning_offsets_minutes)
	)


# --- Harness -----------------------------------------------------------------

func _wait_frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame


func _pass(scenario: String, message: String) -> void:
	var line: String = "  [PASS] %s: %s" % [scenario, message]
	_passes.append(line)
	print(line)


func _fail(scenario: String, message: String) -> void:
	var line: String = "  [FAIL] %s: %s" % [scenario, message]
	_failures.append(line)
	print(line)


func _report() -> void:
	print("")
	print("==================================================")
	print("PHASE 4 DAILY CYCLE TEST")
	print("  passed: %d" % _passes.size())
	print("  failed: %d" % _failures.size())
	for line: String in _failures:
		print(line)
	print("==================================================")
	get_tree().quit(0 if _failures.is_empty() else 1)
