# Basic Group Loop Fix

This pass intentionally focuses only on completing a reliable visible group visit.

## Changes

- A shared keg now loses at most one portion per group/world-minute tick.
- The next drinker rotates through valid members rather than every ready member drinking simultaneously.
- Standing members wait 2-5 world minutes before their first keg drink.
- The post-keg social period now measures time since the group entered `SOCIALISING`, rather than the full visit duration.
- The default post-keg social period is 10 world minutes.
- Group departures start one member at a time with a default 0.6 real-second delay.
- Existing payment, stock, visual placeholder, arrival recovery and cleanup systems were otherwise left unchanged.

## Expected loop

Spawn -> enter -> form up -> order -> keg appears -> staggered drinking -> 10-minute linger -> staggered departure -> cleanup.
