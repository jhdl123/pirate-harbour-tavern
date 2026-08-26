extends Node

## The single source of the game's visual language.
##
## Registered as the [code]UITheme[/code] autoload. Every UI system - HUD,
## management menus, debug panels, the interaction prompt, hover summaries,
## the customer dossier - should look like one game rather than a collection
## of separately-styled screens (`DECISIONS.md` §46, `GAME_DESIGN.md`'s
## "Visual consistency").
##
## The palette is not invented here: it is lifted directly from
## [code]BarManagementMenu.tscn[/code], the one screen that already had a
## deliberate pirate-tavern look before this pass. Everything else adopts it.
##
## [b]How this reaches every Control.[/b] [method _ready] assigns the built
## [Theme] to the root [Window]. Theme lookups walk up the scene tree to the
## Window when a [Control] has no closer theme, so every button, label and
## panel in the game picks this up automatically with zero per-scene wiring -
## including screens built entirely in code, which is most of them.
##
## Code that wants an exact colour or a one-off [StyleBoxFlat] - the hover
## summary, the dossier, the action-choice menu - should use the constants and
## helpers below rather than re-declaring the palette.


## -- Palette -------------------------------------------------------------

const COLOR_WOOD_DARK: Color = Color(0.105, 0.075, 0.047, 0.98)
const COLOR_WOOD_MID: Color = Color(0.145, 0.105, 0.065, 0.95)
const COLOR_WOOD_LIGHT: Color = Color(0.19, 0.14, 0.09, 0.95)

const COLOR_BORDER_AMBER: Color = Color(0.53, 0.36, 0.18, 1.0)
const COLOR_BORDER_DIM: Color = Color(0.36, 0.25, 0.13, 1.0)

const COLOR_GOLD: Color = Color(0.94, 0.76, 0.42, 1.0)
const COLOR_PARCHMENT: Color = Color(0.88, 0.83, 0.73, 1.0)
const COLOR_PARCHMENT_MUTED: Color = Color(0.78, 0.72, 0.62, 1.0)
const COLOR_VALUE: Color = Color(0.94, 0.88, 0.71, 1.0)

const COLOR_GOOD: Color = Color(0.73, 0.78, 0.65, 1.0)
const COLOR_WARN: Color = Color(0.86, 0.68, 0.4, 1.0)
const COLOR_BAD: Color = Color(0.82, 0.42, 0.36, 1.0)

const COLOR_DIM_OVERLAY: Color = Color(0.025, 0.018, 0.012, 0.72)

const FONT_SIZE_BODY: int = 15
const FONT_SIZE_SMALL: int = 12
const FONT_SIZE_TITLE: int = 22
const FONT_SIZE_HEADING: int = 17


var _theme: Theme = null


func _ready() -> void:
	_theme = _build_theme()

	var window: Window = get_tree().root

	if window != null:
		window.theme = _theme


## The shared [Theme]. Prefer letting Controls inherit it; use this only when
## something needs to reference it directly (a Control created detached from
## the tree, for example).
func get_theme() -> Theme:
	return _theme


# -----------------------------------------------------------------------------
# Reusable style helpers
# -----------------------------------------------------------------------------

## The dark-wood/amber-border panel used for menus, the dossier and hover UI.
func make_panel_style(
	border_width: float = 2.0,
	bg_color: Color = COLOR_WOOD_DARK
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.set_border_width_all(border_width)
	style.border_color = COLOR_BORDER_AMBER
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	style.shadow_size = 8
	style.set_content_margin_all(10.0)

	return style


## A lighter inset panel, for a sub-section inside a larger themed panel.
func make_inset_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_WOOD_MID
	style.set_border_width_all(1.0)
	style.border_color = COLOR_BORDER_DIM
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8.0)

	return style


## A compact, low-chrome panel for transient overlays (hover summary, prompt
## backdrops) that must stay unobtrusive rather than look like a menu.
func make_glance_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.05, 0.035, 0.85)
	style.set_border_width_all(1.0)
	style.border_color = Color(0.53, 0.36, 0.18, 0.7)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6.0)

	return style


func _make_button_style(
	bg_color: Color,
	border_color: Color
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.set_border_width_all(1.0)
	style.border_color = border_color
	style.set_corner_radius_all(4)
	style.content_margin_left = 12.0
	style.content_margin_top = 6.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 6.0

	return style


# -----------------------------------------------------------------------------
# Theme construction
# -----------------------------------------------------------------------------

func _build_theme() -> Theme:
	var theme := Theme.new()

	theme.set_default_font_size(FONT_SIZE_BODY)

	_style_label(theme)
	_style_button(theme, &"Button")
	_style_destructive_button(theme)
	_style_panel_container(theme)
	_style_line_edit(theme)
	_style_scrollbars(theme)
	_style_tooltip(theme)

	return theme


func _style_label(theme: Theme) -> void:
	theme.set_color(&"font_color", &"Label", COLOR_PARCHMENT)
	theme.set_font_size(&"font_size", &"Label", FONT_SIZE_BODY)

	theme.set_type_variation(&"TitleLabel", &"Label")
	theme.set_color(&"font_color", &"TitleLabel", COLOR_GOLD)
	theme.set_font_size(&"font_size", &"TitleLabel", FONT_SIZE_TITLE)

	theme.set_type_variation(&"HeadingLabel", &"Label")
	theme.set_color(&"font_color", &"HeadingLabel", COLOR_GOLD)
	theme.set_font_size(&"font_size", &"HeadingLabel", FONT_SIZE_HEADING)

	theme.set_type_variation(&"MutedLabel", &"Label")
	theme.set_color(&"font_color", &"MutedLabel", COLOR_PARCHMENT_MUTED)
	theme.set_font_size(&"font_size", &"MutedLabel", FONT_SIZE_SMALL)


func _style_button(
	theme: Theme,
	type_name: StringName
) -> void:
	theme.set_font_size(&"font_size", type_name, FONT_SIZE_BODY)
	theme.set_color(&"font_color", type_name, COLOR_PARCHMENT)
	theme.set_color(&"font_hover_color", type_name, COLOR_GOLD)
	theme.set_color(&"font_pressed_color", type_name, COLOR_GOLD)
	theme.set_color(
		&"font_disabled_color", type_name, Color(0.6, 0.57, 0.52, 0.55)
	)

	theme.set_stylebox(
		&"normal",
		type_name,
		_make_button_style(COLOR_WOOD_MID, COLOR_BORDER_DIM)
	)
	theme.set_stylebox(
		&"hover",
		type_name,
		_make_button_style(COLOR_WOOD_LIGHT, COLOR_BORDER_AMBER)
	)
	theme.set_stylebox(
		&"pressed",
		type_name,
		_make_button_style(COLOR_WOOD_DARK, COLOR_BORDER_AMBER)
	)
	theme.set_stylebox(
		&"disabled",
		type_name,
		_make_button_style(
			Color(0.1, 0.09, 0.08, 0.6), Color(0.3, 0.27, 0.22, 0.5)
		)
	)
	theme.set_stylebox(
		&"focus",
		type_name,
		_make_button_style(COLOR_WOOD_MID, COLOR_GOLD)
	)


## A distinct look for consequential/irreversible actions (`DECISIONS.md`
## §53) - end the day, discard, and similar. Opt in with
## [code]button.theme_type_variation = &"DestructiveButton"[/code].
func _style_destructive_button(theme: Theme) -> void:
	const TYPE_NAME: StringName = &"DestructiveButton"

	theme.set_type_variation(TYPE_NAME, &"Button")

	theme.set_font_size(&"font_size", TYPE_NAME, FONT_SIZE_BODY)
	theme.set_color(&"font_color", TYPE_NAME, Color(0.95, 0.85, 0.82, 1.0))
	theme.set_color(&"font_hover_color", TYPE_NAME, Color(1.0, 0.92, 0.9, 1.0))
	theme.set_color(
		&"font_disabled_color", TYPE_NAME, Color(0.6, 0.57, 0.52, 0.55)
	)

	theme.set_stylebox(
		&"normal",
		TYPE_NAME,
		_make_button_style(Color(0.32, 0.12, 0.1, 0.95), COLOR_BAD)
	)
	theme.set_stylebox(
		&"hover",
		TYPE_NAME,
		_make_button_style(Color(0.42, 0.15, 0.12, 0.95), Color(0.9, 0.5, 0.42))
	)
	theme.set_stylebox(
		&"pressed",
		TYPE_NAME,
		_make_button_style(Color(0.26, 0.09, 0.08, 0.95), COLOR_BAD)
	)
	theme.set_stylebox(
		&"disabled",
		TYPE_NAME,
		_make_button_style(
			Color(0.1, 0.09, 0.08, 0.6), Color(0.3, 0.27, 0.22, 0.5)
		)
	)


func _style_panel_container(theme: Theme) -> void:
	theme.set_stylebox(&"panel", &"PanelContainer", make_panel_style())


func _style_line_edit(theme: Theme) -> void:
	theme.set_color(&"font_color", &"LineEdit", COLOR_PARCHMENT)
	theme.set_font_size(&"font_size", &"LineEdit", FONT_SIZE_BODY)
	theme.set_stylebox(
		&"normal", &"LineEdit", make_inset_panel_style()
	)


func _style_scrollbars(theme: Theme) -> void:
	# Contextual scrollbars (`DECISIONS.md` §52): thin, only visible where a
	# ScrollContainer actually needs one, coloured to match the panel wood
	# rather than the engine default blue.
	for type_name: StringName in [&"VScrollBar", &"HScrollBar"]:
		var grabber := StyleBoxFlat.new()
		grabber.bg_color = COLOR_BORDER_AMBER
		grabber.set_corner_radius_all(3)
		grabber.set_content_margin_all(4.0)

		var grabber_hover := StyleBoxFlat.new()
		grabber_hover.bg_color = COLOR_GOLD
		grabber_hover.set_corner_radius_all(3)
		grabber_hover.set_content_margin_all(4.0)

		var track := StyleBoxFlat.new()
		track.bg_color = Color(0.0, 0.0, 0.0, 0.25)
		track.set_corner_radius_all(3)

		theme.set_stylebox(&"grabber", type_name, grabber)
		theme.set_stylebox(&"grabber_highlight", type_name, grabber_hover)
		theme.set_stylebox(&"grabber_pressed", type_name, grabber_hover)
		theme.set_stylebox(&"scroll", type_name, track)


func _style_tooltip(theme: Theme) -> void:
	theme.set_stylebox(
		&"panel", &"TooltipPanel", make_glance_panel_style()
	)
	theme.set_color(&"font_color", &"TooltipLabel", COLOR_PARCHMENT)
	theme.set_font_size(&"font_size", &"TooltipLabel", FONT_SIZE_SMALL)
