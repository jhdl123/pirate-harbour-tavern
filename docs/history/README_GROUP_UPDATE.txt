GROUP BASIC LOOP UPDATE

Replace the matching files in your project by copying this folder over the project root.

Updated files:
- systems/groups/group_order_service.gd
- systems/groups/group_manager.gd

What changed:
1. Added `basic_loop_ignore_stock` (default true) to GroupOrderService.
   While true, milestone Ale table-cask groups can order and drink even when service stock is empty.
   Turn it off later in the Inspector when stock/restocking is ready for full testing.
2. The group order still requires a correctly configured capable station and shared vessel.
3. Orphan shared servings now call empty_now() before removal, ensuring their vessel is returned.
4. Existing staggered drinking, post-keg social wait, staggered departure and spawning fixes remain unchanged.

Expected test:
- Every group should assemble, receive the square keg placeholder, consume it over time, linger, and leave.
- Later groups should continue receiving kegs even after normal drink stock reaches zero.
