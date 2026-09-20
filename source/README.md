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
  (`res://tests/*.gd`, shipped as plain text). Run
  `res://tests/test_runner.tscn` for the 13 unit-style checks and
  `res://tests/bot_playthrough.tscn` for a scripted bot that plays the whole
  level.

## How the game works

- `game.gd` builds the level procedurally from the `AREAS` table: five named
  areas with their own width, rubble, torches, story caption, objective and
  encounter. The Breach (reach the road), Ash Road (clear it), The Cistern
  (a wide chamber: find the gate key, which springs an ambush), The Narrows
  (a tight passage: clear it, with a second group spawning behind you) and
  The Gate (hold it, then reach the exit). Doors between areas lift when the
  area's objective is done. It also tracks run stats (time, kills,
  headshots, shots, hits, damage taken) for the score screens.
- `player.gd` is a `CharacterBody3D` FPS controller (WASD + mouse, or the
  touch joystick / look-drag on phones) with touch aim assist while FIRE is
  held.
- `weapon.gd` is a hitscan rifle with a 30-round magazine and a finite
  reserve (60 to start, topped up by glowing ammo packs and 40% drops from
  kills), pooled tracers and impact sparks, a muzzle flash, and headshots
  for double damage.
- `enemy.gd` has two variants: the grunt and the faster, fragile, red-tinted
  runner. Both path on the navmesh, wind up before striking (eyes flare,
  head swells) and only land the hit if the player is still in reach.
- `hud.gd` draws health, ammo, objective, area titles and story captions,
  the title screen, the pause menu (ESC or the touch PAUSE button, with
  sensitivity sliders saved to `user://settings.cfg`), the death / win
  screens with run stats and best time, and the touch controls.
- `sfx.gd` synthesises every sound effect into `AudioStreamWAV` streams at
  startup, since the project ships no audio assets.

Touch look deltas are computed from touch positions, never from
`InputEventScreenDrag.relative`: Godot's web platform (4.7) fills `relative`
from the wrong finger when two touches are down.

The tests drive the level through `Game`'s small API (`get_area_count`,
`area_entry_position`, `key_position`, `gate_position`, `bot_next_goal`,
`progress_text`) and set `Game.skip_title = true` before instantiating the
main scene.

## Porting the fixes back into the Godot project

Copy `scripts/*.gd` over the matching files in the editor project and
re-export. The scenes (`player.tscn`, `enemy.tscn`, `hud.tscn`, `main.tscn`)
and `project.godot` were not changed.
