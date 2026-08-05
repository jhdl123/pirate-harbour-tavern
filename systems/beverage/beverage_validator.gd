class_name BeverageValidator
extends RefCounted

## Checks every beverage resource and reports what is wrong with it.
##
## Validation exists so a broken drink says so at load, in one readable list,
## rather than silently failing at the moment a customer orders it. Every check
## here answers a question the debug panel asks:
##
## [codeblock]
## are ids present and unique
## does every reference resolve
## do drinks and formats agree with each other
## can every recipe ingredient be found
## can every drink actually be made by something
## [/codeblock]


class Issue extends RefCounted:
	enum Severity { ERROR, WARNING }

	var severity: Severity = Severity.ERROR
	var subject: String = ""
	var message: String = ""

	static func error(issue_subject: String, text: String) -> Issue:
		var issue: Issue = Issue.new()
		issue.severity = Severity.ERROR
		issue.subject = issue_subject
		issue.message = text
		return issue

	static func warning(issue_subject: String, text: String) -> Issue:
		var issue: Issue = Issue.new()
		issue.severity = Severity.WARNING
		issue.subject = issue_subject
		issue.message = text
		return issue

	func get_text() -> String:
		var prefix: String = "ERROR" if severity == Severity.ERROR else "WARN "
		return "[%s] %s: %s" % [prefix, subject, message]


class Report extends RefCounted:
	var issues: Array[Issue] = []
	var checked_count: int = 0

	func add(issue: Issue) -> void:
		issues.append(issue)

	func get_errors() -> Array[Issue]:
		var found: Array[Issue] = []
		for issue: Issue in issues:
			if issue.severity == Issue.Severity.ERROR:
				found.append(issue)
		return found

	func get_warnings() -> Array[Issue]:
		var found: Array[Issue] = []
		for issue: Issue in issues:
			if issue.severity == Issue.Severity.WARNING:
				found.append(issue)
		return found

	func has_errors() -> bool:
		return not get_errors().is_empty()

	func is_clean() -> bool:
		return issues.is_empty()

	func get_summary() -> String:
		return "%d checked, %d errors, %d warnings" % [
			checked_count,
			get_errors().size(),
			get_warnings().size(),
		]

	func get_lines() -> PackedStringArray:
		var lines: PackedStringArray = PackedStringArray()
		for issue: Issue in issues:
			lines.append(issue.get_text())
		return lines


## Runs every check against [param registry].
static func validate(registry: BeverageRegistry) -> Report:
	var report: Report = Report.new()

	if registry == null:
		report.add(Issue.error("registry", "No BeverageRegistry was provided."))
		return report

	registry.rebuild()

	_validate_spoilage_profiles(registry, report)
	_validate_storage_profiles(registry, report)
	_validate_contents(registry, report)
	_validate_containers(registry, report)
	_validate_serving_formats(registry, report)
	_validate_recipes(registry, report)
	_validate_drinks(registry, report)

	return report


static func _validate_spoilage_profiles(
	registry: BeverageRegistry,
	report: Report
) -> void:
	for profile: SpoilageProfileDefinition in registry.spoilage_profiles:
		report.checked_count += 1

		if profile == null:
			report.add(Issue.error("spoilage", "An empty entry is listed."))
			continue

		if profile.profile_id.is_empty():
			report.add(Issue.error(
				profile.resource_path, "No profile_id."
			))
			continue

		if profile.expiry_result == SpoilageProfileDefinition.ExpiryResult.TRANSFORMS:
			if profile.spoiled_item_id.is_empty():
				report.add(Issue.error(
					String(profile.profile_id),
					"Transforms on expiry but names no spoiled_item_id."
				))


static func _validate_storage_profiles(
	registry: BeverageRegistry,
	report: Report
) -> void:
	for profile: StorageProfileDefinition in registry.storage_profiles:
		report.checked_count += 1

		if profile == null:
			report.add(Issue.error("storage", "An empty entry is listed."))
			continue

		if profile.profile_id.is_empty():
			report.add(Issue.error(profile.resource_path, "No profile_id."))
			continue

		if profile.get_effective_storage_tags().is_empty():
			report.add(Issue.warning(
				String(profile.profile_id),
				"Allows no storage location, so stock using it has nowhere "
				+ "to go."
			))

		if profile.content_tags.is_empty():
			report.add(Issue.warning(
				String(profile.profile_id),
				"Names no content_tags, so no stock will ever match it."
			))


static func _validate_contents(
	registry: BeverageRegistry,
	report: Report
) -> void:
	for content: BeverageContentDefinition in registry.contents:
		report.checked_count += 1

		if content == null:
			report.add(Issue.error("content", "An empty entry is listed."))
			continue

		if content.content_id.is_empty():
			report.add(Issue.error(content.resource_path, "No content_id."))
			continue

		var subject: String = String(content.content_id)

		if content.can_spoil and content.spoilage_profile == null:
			report.add(Issue.warning(
				subject,
				"Marked can_spoil but names no spoilage profile, so it will "
				+ "never spoil."
			))

		if content.tags.is_empty():
			report.add(Issue.warning(
				subject,
				"Has no tags, so no container will be able to identify it."
			))

		if registry.get_containers_for_content(content).is_empty():
			report.add(Issue.error(
				subject, "No container in the registry can hold this."
			))


static func _validate_containers(
	registry: BeverageRegistry,
	report: Report
) -> void:
	for container: ContainerDefinition in registry.containers:
		report.checked_count += 1

		if container == null:
			report.add(Issue.error("container", "An empty entry is listed."))
			continue

		if container.container_id.is_empty():
			report.add(Issue.error(container.resource_path, "No container_id."))
			continue

		var subject: String = String(container.container_id)

		if container.maximum_capacity <= 0:
			report.add(Issue.error(
				subject,
				"Capacity is %d." % container.maximum_capacity
			))

		if container.historical_name.strip_edges().is_empty():
			report.add(Issue.error(subject, "No historical_name to display."))

		if container.bulk_storage and container.customer_serving:
			report.add(Issue.warning(
				subject,
				"Is marked both bulk storage and customer serving. The brief "
				+ "keeps supplier-sized and serving containers separate."
			))


static func _validate_serving_formats(
	registry: BeverageRegistry,
	report: Report
) -> void:
	for format: ServingFormatDefinition in registry.serving_formats:
		report.checked_count += 1

		if format == null:
			report.add(Issue.error("format", "An empty entry is listed."))
			continue

		if format.format_id.is_empty():
			report.add(Issue.error(format.resource_path, "No format_id."))
			continue

		var subject: String = String(format.format_id)

		if not format.required_container_id.is_empty():
			if registry.get_container(format.required_container_id) == null:
				report.add(Issue.error(
					subject,
					"Requires unknown container '%s'."
					% String(format.required_container_id)
				))

		if format.minimum_group_size > format.maximum_group_size:
			report.add(Issue.error(
				subject,
				"minimum_group_size is above maximum_group_size."
			))

		if format.is_shared and format.portion_count <= 1:
			report.add(Issue.warning(
				subject,
				"Is shared but has one portion, so a group cannot take turns."
			))

		if format.creates_group_anchor and not format.is_shared:
			report.add(Issue.warning(
				subject,
				"Creates a group anchor but is not shared."
			))


static func _validate_recipes(
	registry: BeverageRegistry,
	report: Report
) -> void:
	for recipe: DrinkRecipeDefinition in registry.recipes:
		report.checked_count += 1

		if recipe == null:
			report.add(Issue.error("recipe", "An empty entry is listed."))
			continue

		if recipe.recipe_id.is_empty():
			report.add(Issue.error(recipe.resource_path, "No recipe_id."))
			continue

		var subject: String = String(recipe.recipe_id)

		if recipe.ingredients.is_empty():
			report.add(Issue.error(
				subject, "Has no ingredients: it would create stock from nothing."
			))

		var index: int = 0

		for ingredient: RecipeIngredient in recipe.ingredients:
			if ingredient == null:
				report.add(Issue.error(
					subject, "Ingredient %d is empty." % index
				))
				index += 1
				continue

			if not ingredient.is_valid():
				report.add(Issue.error(
					subject,
					"Ingredient %d has no source id or a quantity of %d."
					% [index, ingredient.quantity]
				))
				index += 1
				continue

			if ingredient.is_content():
				if registry.get_content(ingredient.content_id) == null:
					report.add(Issue.error(
						subject,
						"Ingredient %d refers to unknown content '%s'."
						% [index, String(ingredient.content_id)]
					))
			elif registry.item_registry != null:
				if not registry.item_registry.has_definition(ingredient.item_id):
					report.add(Issue.error(
						subject,
						"Ingredient %d refers to unknown item '%s'."
						% [index, String(ingredient.item_id)]
					))

			var access: StringName = ingredient.required_access_capability

			if not access.is_empty() and not StationCapabilities.is_known(access):
				report.add(Issue.warning(
					subject,
					"Ingredient %d needs unrecognised capability '%s'."
					% [index, String(access)]
				))

			index += 1

		if registry.item_registry != null and not recipe.output_drink_id.is_empty():
			if not registry.item_registry.has_definition(recipe.output_drink_id):
				report.add(Issue.error(
					subject,
					"Produces unknown drink '%s'."
					% String(recipe.output_drink_id)
				))

		if not recipe.output_content_id.is_empty():
			if registry.get_content(recipe.output_content_id) == null:
				report.add(Issue.error(
					subject,
					"Produces unknown content '%s'."
					% String(recipe.output_content_id)
				))

		if not recipe.output_serving_format_id.is_empty():
			if registry.get_serving_format(recipe.output_serving_format_id) == null:
				report.add(Issue.error(
					subject,
					"Names unknown serving format '%s'."
					% String(recipe.output_serving_format_id)
				))

		if not recipe.required_vessel_container_id.is_empty():
			if registry.get_container(recipe.required_vessel_container_id) == null:
				report.add(Issue.error(
					subject,
					"Requires unknown vessel '%s'."
					% String(recipe.required_vessel_container_id)
				))

		for capability: StringName in recipe.required_station_capabilities:
			if not StationCapabilities.is_known(capability):
				report.add(Issue.warning(
					subject,
					"Requires unrecognised capability '%s'."
					% String(capability)
				))


static func _validate_drinks(
	registry: BeverageRegistry,
	report: Report
) -> void:
	if registry.item_registry == null:
		report.add(Issue.warning(
			"registry",
			"No ItemRegistry is linked, so drinks could not be checked."
		))
		return

	for drink: DrinkDefinition in registry.get_all_drinks():
		report.checked_count += 1

		var subject: String = String(drink.item_id)

		if drink.item_id.is_empty():
			report.add(Issue.error(drink.resource_path, "No item_id."))
			continue

		# A drink with no content and no recipe has no stock behind it and can
		# never actually be served, which is the single most useful thing this
		# validator catches.
		if drink.content_id.is_empty() and drink.recipe_id.is_empty():
			report.add(Issue.error(
				subject,
				"Has neither content_id nor recipe_id, so nothing can supply it."
			))

		if not drink.content_id.is_empty():
			if registry.get_content(drink.content_id) == null:
				report.add(Issue.error(
					subject,
					"Refers to unknown content '%s'."
					% String(drink.content_id)
				))

		if not drink.recipe_id.is_empty():
			if registry.get_recipe(drink.recipe_id) == null:
				report.add(Issue.error(
					subject,
					"Refers to unknown recipe '%s'." % String(drink.recipe_id)
				))

		if drink.serving_format_ids.is_empty():
			report.add(Issue.warning(
				subject,
				"Declares no serving formats, so it can only be served the "
				+ "pre-framework way."
			))

		for format_id: StringName in drink.serving_format_ids:
			var format: ServingFormatDefinition = registry.get_serving_format(
				format_id
			)

			if format == null:
				report.add(Issue.error(
					subject,
					"Lists unknown serving format '%s'." % String(format_id)
				))
				continue

			# Both sides must agree. A drink listing a format the format
			# refuses is the classic silent failure this catches.
			if not format.accepts_drink(drink):
				report.add(Issue.error(
					subject,
					"Lists format '%s', but that format rejects this drink's "
					% String(format_id)
					+ "tags."
				))

		for capability: StringName in drink.required_station_capabilities:
			if not StationCapabilities.is_known(capability):
				report.add(Issue.warning(
					subject,
					"Requires unrecognised capability '%s'."
					% String(capability)
				))

		if drink.can_spoil_after_serving and drink.spoilage_profile == null:
			report.add(Issue.warning(
				subject, "Can spoil after serving but names no profile."
			))
