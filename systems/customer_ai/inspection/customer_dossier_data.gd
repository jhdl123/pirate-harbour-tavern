class_name CustomerDossierData
extends RefCounted

## The player-facing counterpart to [CustomerInspectionData].
##
## Same architecture rule (DECISIONS.md §25/§34):
## [code]Customer -> CustomerDossierData -> CustomerDossierUI[/code]. The UI
## never reads a [Customer] or its internals directly.
##
## Where the developer snapshot exists to show everything for tuning, this
## one exists to show only what a player looking at this customer could
## plausibly know (GAME_DESIGN.md's "Customer knowledge" - player knowledge
## is distinct from simulation knowledge). Needs, motivation, candidate
## scores and execution outcomes belong on [CustomerInspectionData], never
## here.
##
## Sections that depend on a future information/relationship/history system
## are represented as empty arrays/strings rather than invented now
## (`docs/DECISIONS_UI_UX_APPEND.md` §33/§57) - [CustomerDossierUI] hides a
## section entirely when its data is empty instead of showing a placeholder.


## Player-facing name - currently always known, since the customer is right
## in front of the player.
var customer_name: String = ""

## The customer type's display name, e.g. "Sailor", "Merchant".
var type_display_name: String = ""

## Authored flavour text from [member CustomerType.description]. Empty when
## the type has none authored.
var description: String = ""

## One short, current-status line - the same phrasing the hover summary uses,
## so the dossier and the glance layer never disagree about what this
## customer is doing.
var status_line: String = ""

## The customer's actual in-game sprite, enlarged rather than replaced with
## separate portrait art (`docs/DECISIONS_UI_UX_APPEND.md` §36).
var portrait_texture: Texture2D = null

## Reserved for the future relationship system. Empty means "no known
## relationship to show" - never rendered as "Unknown".
var relationship_label: String = ""

## Reserved for the future history/memory system. Each entry is a short,
## already-worded line - not raw event data.
var history_lines: Array[String] = []
