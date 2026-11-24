# Antsy Airlines - Level and World Design Starter

Prepared as an isolated graybox deliverable for Pranav's Level & World Design role.
This kit adds NEW files; it does not replace the team's title screen, lobby, player or scripts.

## Files to copy

Copy `scenes/levels/` and `docs/level_design/` into the ROOT of your local
`AntsyAirlinesGodot` repository (next to `project.godot`). Do not copy the ZIP as a folder
inside the project. Use GitHub Desktop to create `feature/pranav-level-graybox` from
`main` BEFORE copying, and do not edit your teammates' files.

## How to preview in Godot

1. Open the repo's `project.godot` in the installed Godot editor.
2. Open `res://scenes/levels/level_walkthrough_preview.tscn`.
3. Press **F6** (Run Current Scene), not F5 (Run Project).
4. The preview uses the team's existing Player scene in OFFLINE mode; it does not need a server.
5. Test **W/A/S/D**, **mouse movement**, **Space** for jump, **V** for camera mode, and **Esc** to release mouse.
6. Walk from the cargo staging zone at the apron to the OPEN rear entrance of the plane.
7. Check that walls, cabin seats and counters block movement, and the aisle stays clear.

This is a graybox. Cargo boxes are STATIC placeholder objects and CANNOT be picked up.
The blue staging pad and green interior loading pad are Area3D markers only; they do NOT
count deliveries yet. The multiplayer lobby is unchanged by this package.

## Scene interfaces for other teammates

- `airport_environment.tscn`: apron, basic terminal, cargo props, four spawn markers.
- `airplane_graybox.tscn`: walkable interior, cockpit, four rows of seats, galley,
  electrical panel, open rear entrance, and cargo loading Area3D.
- `level_walkthrough_preview.tscn`: visual local test, not a production game phase.
- `AirportEnvironment/Zones/CargoPickupStagingZone` is in group `cargo_pickup_zone`.
- `AirplaneGraybox/Zones/RearCargoLoadingZone` is in group `cargo_loading_zone`.
- `PlayerSpawnMarkers/PlayerSpawn_01` to `_04` are Marker3D placeholders.
- `InteractionMarkers` and `PassengerSeatMarkers` are placement anchors only.

## Important integration boundaries

- Do not replace `res://scenes/lobby.tscn` with this preview scene.
- The existing team's player-spawner code DOES NOT yet use these spawn markers.
  Coordinate with the network programmer before wiring them in.
- The current scene uses 1 unit = ~1 meter, a 5-meter-wide plane, a 1.8-meter aisle.
  Final dimensions should be adjusted to the Blender plane model when it arrives.
- The existing player scene may change: if offline preview fails after later merges,
  test using the team's current player scene and ask for a compatible preview fix.
- The team should agree on cargo Area3D names and group before writing cargo logic.

## GitHub contribution

1. In GitHub Desktop, review Changes: only `scenes/levels/` and `docs/level_design/`
   should appear (plus Godot-generated `.uid` files if Godot creates any).
2. Commit: `feat(level): add airport and airplane graybox with QA preview`.
3. Push the new branch and create a pull request against `main`.
4. Ask a teammate to review; do not overwrite or force-push into `main`.

## Evidence of work

Capture screenshots of the Godot editor showing node hierarchy, walkable aisle,
spawn markers and cargo zones. Record actual test outcomes in `TEST_CHECKLIST.md`.
