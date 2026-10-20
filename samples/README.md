# Sample scripts

Original CLEO Android scripts written for Rodwave (MIT licence). Open them in Rodwave as a project file
or compile them with the engine.

| File | Type | What it does | Shows |
| --- | --- | --- | --- |
| `car_repair_touch.txt` | `.csa` | While driving, hold the bottom-right corner for one second to repair your vehicle | Nested `if` blocks, touch zones, vehicle handles |
| `wanted_clear_touch.txt` | `.csa` | Hold the top-left corner for half a second to clear your wanted level | `if and` with two conditions |
| `weather_menu.txt` | `.csi` | Sets the clock to noon and forces sunny Los Santos weather | `const`, menu scripts that end themselves |
| `armour_steps.txt` | `.csi` | Adds armour in ten steps of 10 | `for` loop, `gosub` and `return` |

**Verified:** every file here compiles with Rodwave's built-in opcode table without errors or warnings,
and its decompiled listing recompiles to the same bytes (`SamplesTest` in `engine/`).

**Not verified:** none of them has been run in the game; Rodwave cannot execute scripts. Test them
with a backup of your setup.
