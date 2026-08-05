# Group and Arrival Recovery Fix

## Fixed

- Group visits no longer depend on a single signal delivery to advance after members reach `IN_GROUP`.
- The group manager now performs one guarded state-machine tick per world minute, using `minute_passed` normally and `_process` as a recovery path.
- Customer arrivals now recover automatically if the pending WorldTime spawn booking is missing or dead.
- Completing a customer visit also repairs a missing arrival booking when the tavern is open.
- The currently firing spawn handle is cleared before the next arrival is scheduled.

## Expected test result

A standing group should progress through `IN_GROUP` to ordering, receive the Ale table cask, drink portions, pay once, and leave. After the tavern empties, further solo or group arrival attempts should continue until last orders.
