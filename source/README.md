# Backup Plan — game sources

This repository is the Godot 4.7 **web export** of *Backup Plan* (`index.html`,
`index.js`, `index.wasm`, `index.pck`). The gameplay scripts live inside
`index.pck`; this folder holds the readable copies of those scripts so that
changes to the build can be reviewed as a normal diff.

- `scripts/` — the six game scripts exactly as embedded in `index.pck`
  (`res://scripts/*.gd`). The pck now carries them as plain-text GDScript
  instead of compiled binary tokens, so the files here are byte-for-byte
  what the game runs.
- `tests/` — the headless test scenes shipped in the pck
  (`res://tests/*.gd`), unchanged. Run `res://tests/test_runner.tscn` for the
  12 unit-style checks and `res://tests/bot_playthrough.tscn` for a scripted
  bot that plays the whole level.

## How the game works

- `game.gd` builds the level procedurally: a 78 m corridor with rubble,
  pillars and torches, three wave-trigger zones (3 / 4 / 5 enemies) and an
  exit gate that only completes the level once every wave has been cleared.
- `player.gd` is a `CharacterBody3D` FPS controller (WASD + mouse, or the
  touch joystick / look-drag on phones).
- `weapon.gd` is a hitscan rifle with a 30-round magazine, tracers, impact
  sparks and a muzzle flash.
- `enemy.gd` chases the player, melees inside 1.3 m, flashes on hit and fades
  out on death.
- `hud.gd` draws health, ammo, the objective line, the story card, the
  death / win screens and the touch controls.
- `sfx.gd` synthesises every sound effect (gunshot, hit, growl, reload,
  hurt) into `AudioStreamWAV` streams at startup, since the project ships no
  audio assets, and plays them from small 2D / 3D player pools.

Enemies navigate on a `NavigationMesh` that `game.gd` bakes at startup from
the level's static colliders (the `nav_source` group), with a straight-line
fallback while the map is not ready.

## Porting the fixes back into the Godot project

Copy `scripts/*.gd` over the matching files in the editor project and
re-export. The scenes (`player.tscn`, `enemy.tscn`, `hud.tscn`, `main.tscn`)
and `project.godot` were not changed.
