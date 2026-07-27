# Interaction Menu Framework and Supply Ledger

## What this adds

- `InteractionMenu` autoload: opens one context-specific menu, pauses the simulation, closes it and restores the previous state.
- `InteractionMenuView`: small base class for all future contextual menus.
- Supplier catalogue resources that can also support future visiting traders.
- `OrderManager`: validates payment and records pending orders.
- A physical `OrderLedger` interactable.
- A working stock-order menu for grog barrels and ale kegs.

## Current scope

Submitting an order:

1. spends the money;
2. records the order in `OrderManager.pending_orders`;
3. records an expected arrival day;
4. does not yet create or deliver physical stock.

This is intentional. A later delivery system can consume the pending orders without changing the menu.

## Test

1. Run the main scene.
2. Walk to the small ledger placeholder near the bar.
3. Press `E` when the prompt says `Read Supply Ledger`.
4. Confirm customers, time and player movement stop.
5. Add quantities with `+` and `-`.
6. Confirm the total and affordability update.
7. Place an affordable order.
8. Confirm money is deducted and an expected arrival message appears.
9. Close with the button or Escape.
10. Confirm the simulation resumes.

## Future menus

Reuse the same framework by creating a scene whose root extends `InteractionMenuView`, then call:

```gdscript
InteractionMenu.open_menu(menu_scene, context)
```

Suitable future uses include pricing books, traders, contracts, staff boards and upgrade catalogues.
