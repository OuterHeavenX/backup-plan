# Backup Plan — game sources

This repository is the Godot 4.7 **web export** of *Backup Plan* (`index.html`,
`index.js`, `index.wasm`, `index.pck`). The gameplay scripts live inside
`index.pck`; this folder holds the readable copies of those scripts so that
changes to the build can be reviewed as a normal diff.

- `scripts/` — the six game scripts exactly as embedded in `index.pck`
  (`res://scripts/*.gd`). The pck now carries them as plain-text GDScript
  instead of compiled binary tokens, so the files here are byte-for-byte
  what the game runs.
- `levels/` — the level data files shipped in the pck.
- `tests/` — the headless test scenes shipped in the pck
  (`res://tests/*.gd`, shipped as plain text). Run
  `res://tests/test_runner.tscn` for the 15 unit-style checks and
  `res://tests/bot_playthrough.tscn` for a scripted bot that plays the whole
  level.

## How the game works

- Levels are JSON files in `levels/` (`ash_valley.json`, `the_deep.json`):
  a corridor of named areas, each with its own width, rubble, torches,
  story caption, objective (`reach`, `clear` or `collect`) and encounter,
  plus ammo and health pickups. `game.gd` builds the geometry, doors,
  triggers, navmesh and pickups from that table, runs the progression,
  tracks run stats, and handles checkpoints (death offers a retry from the
  start of the current area with the ammo you had on entry), difficulty
  (enemy HP / damage and drop rates) and level select.
- `player.gd` is a `CharacterBody3D` FPS controller (WASD + mouse, or the
  touch joystick / look-drag on phones) with a dash (Shift, or double-tap
  the joystick / DASH button), touch aim assist while FIRE is held, camera
  recoil and shake, footsteps and haptics.
- `weapon.gd` holds two weapons, a rifle and a shotgun (keys 1 / 2 or the
  SWAP button), each with its own magazine and reserve, pooled tracers,
  impact sparks (`GPUParticles3D`) and headshots for double damage.
- `enemy.gd` has three variants: grunt, runner (fast, fragile, small) and
  brute (slow, huge, its slam shakes the camera). All path on the navmesh,
  bob and lean while moving, wind up before striking (eyes flare, head
  swells, spikes flick out) and stagger on headshots.
- `hud.gd` draws health, ammo, objective, area titles and story captions, a
  damage vignette and low-health pulse, the title screen (level and
  difficulty selectors), the pause menu (ESC, the touch PAUSE button, or
  losing window focus) with sensitivity sliders saved to
  `user://settings.cfg`, the death / win screens with run stats, best times
  per level and difficulty, checkpoint retry and next level, and the touch
  controls, positioned inside the display safe area.
- `sfx.gd` synthesises every sound (weapons, hits, growls, footsteps, a wind
  loop and a music drone) into `AudioStreamWAV` streams at startup, since
  the project ships no audio assets. Replace the entries of `_streams` with
  loaded files to use real audio.

Touch look deltas are computed from touch positions, never from
`InputEventScreenDrag.relative`: Godot's web platform (4.7) fills `relative`
from the wrong finger when two touches are down.

The tests drive the level through `Game`'s small API (`get_area_count`,
`area_entry_position`, `key_position`, `gate_position`, `bot_next_goal`,
`progress_text`) and set `Game.skip_title = true` before instantiating the
main scene. The bot plays every level in `Game.LEVELS` in one run.

## Continuous integration

`.github/workflows/test.yml` runs `tools/run_ci.sh` on every push and pull
request: it builds test variants of the web export whose main scene is the
test runner / the bot (`tools/pck_tools.py`), runs them in headless Chromium
(`tools/web_harness.mjs`, Playwright) and fails unless every test passes and
the bot wins every level.

## Porting the fixes back into the Godot project

Copy `scripts/*.gd`, `tests/*.gd` and `levels/*.json` over the matching
files in the editor project (create a `levels/` folder) and re-export. The
scenes (`player.tscn`, `enemy.tscn`, `hud.tscn`, `main.tscn`) and
`project.godot` were not changed.
