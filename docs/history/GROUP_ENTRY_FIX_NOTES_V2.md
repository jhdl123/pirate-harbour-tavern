# Group Entry Fix V2

This patch addresses the remaining parked group members that continued to occupy `GameManager.active_customers` after the original solo customers had left.

Changes:

- A registered group starts immediately instead of waiting for the next world-minute signal.
- Group entry has a real-time watchdog independent of paused/frozen tavern time.
- Individual members parked outside or crossing the door are removed after a bounded timeout.
- A group is rejected and cleaned up when its full membership would exceed the tavern population cap.
- Finished/failed groups clear their watchdog tracking record.

The customer AI report from the failing run recorded eight solo visits completed and zero active visits, while characters remained visible outside. This indicated group members were outside the solo-reporting lifecycle while still occupying live population slots.
