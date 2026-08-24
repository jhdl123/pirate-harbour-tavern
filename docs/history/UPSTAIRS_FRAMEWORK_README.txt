UPSTAIRS FRAMEWORK DROP-IN
==========================

Implemented structure
---------------------
Main scene:
- FloorTransitions/StairsUp
- UpstairsFloor (kept loaded at x +1400 so downstairs simulation continues)
- Markers/DownstairsArrival
- FloorController

Upstairs scene:
- Environment/Room
  - TileMapLayerWalls
  - TileMapLayerWalls_Top
  - TileMapLayerFloor
- Environment/Furniture
  - stairs artwork
- Environment/Rails
  - rail sprites
- Environment/Collision/RailCollisions
  - vertical and horizontal rail collisions
- Transitions/StairsDown
- Markers/UpstairsArrival

How the transition works
------------------------
1. Stand close to the stairs.
2. Use the normal interaction key.
3. FloorController moves the persistent Player to the matching arrival marker.
4. Both floors remain loaded, so customers, staff, managers, inventory and time are not recreated.

Important editor checks
-----------------------
The transition and arrival points were placed to match the current upstairs stair artwork:
- stair centre: approximately (1057, 343)
- arrival point: approximately (1057, 404)

The downstairs stair appears to be painted into the TileMap rather than stored as a named Sprite2D,
so confirm FloorTransitions/StairsUp visually overlays the bottom/top interaction section of your stair art.
Move the StairsUp node only if your painted downstairs stair is at a slightly different position.
Keep DownstairsArrival outside the StairsUp interaction rectangle.

Rail collision shapes
---------------------
Upstairs rail collisions are under:
Environment/Collision/RailCollisions

They are separate CollisionShape2D nodes so you can resize them visually without altering the rail sprites.
- VerticalRailCollision blocks the north-south rail.
- HorizontalRailCollision blocks the east-west rail.

Current scope
-------------
- Player-only floor travel.
- No NPC upstairs routing yet.
- No fade transition yet.
- Upstairs has its tile collision but no separate baked NPC navigation region yet.
