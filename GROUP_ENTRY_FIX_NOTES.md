# Group Entry Fix

Changed files:

- `scripts/Entities/customer.gd`
- `scripts/Interactables/customer_door.gd`
- `systems/groups/group_spawner.gd`
- `systems/groups/customer_group.gd`
- `systems/groups/group_manager.gd`

Main changes:

- Groups queue in a line extending away from the doorway.
- Default member spacing increased from 14 px to 30 px.
- `member_entry_delay` is now used.
- Members wait outside with navigation parked.
- Members cross the doorway one at a time.
- Final chair or standing destinations are assigned only after crossing inside.
- Doorway crossing has an 8-second per-member timeout.
- Failed group entry explicitly removes members so population slots are not leaked.

Validation note:

The execution environment did not contain a Godot executable, so the project could not be launched here. The changes were inspected for consistency against the existing navigation and group APIs, but should be tested in Godot using a forced group of six.
