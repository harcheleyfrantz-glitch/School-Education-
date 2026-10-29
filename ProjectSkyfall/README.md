# Project Skyfall 1.0

An aviation life simulator made in Godot 4.4.1. Everything — aircraft, airports, people, terrain, sound and the news — is generated procedurally, so the game ships with no imported art.

## Playing

**Windows / Linux builds:** unzip `ProjectSkyfall-1.0.0-windows-x64.zip` or `ProjectSkyfall-1.0.0-linux-x64.zip` and run `ProjectSkyfall.exe` / `ProjectSkyfall.x86_64`. You need a Vulkan-capable GPU.

**From source:** open this folder in Godot 4.4.1 and press F5.

## What's in it

- **Career:** create a pilot, then fly scheduled trips for an airline. You earn hours, ranks, money and reputation, and your logbook keeps every flight. If your pilot dies, they're gone for good, and the world remembers it.
- **Free flight** from the world map: any of the seven aircraft, from any airport, at any time of day, in any weather.
- **Activities:** discovery flights, landing challenges (crosswind, fog, gusts, night) and multi-leg bush trips, all scored.
- **Passenger mode:** book a seat and ride along in the cabin, then rate the flight.
- **The aircraft:**
  - seven types: trainer, turboprop, regional jet, narrowbody, widebody, business jet and freighter;
  - detailed exteriors with airline liveries and special schemes, including a firefighting supertanker;
  - interactive flight decks and walk-in cabins.
- **Full flights:**
  - gate to gate: preflight, boarding, pushback, taxi, takeoff, cruise, approach and landing;
  - ATC with radio replies you choose;
  - AI traffic, failures and emergencies.
- **Accidents:** every person aboard gets an individual outcome, and an investigation follows.
- **News:**
  - every story is a watchable in-engine TV news video: studio anchors, reconstructions with flight data, helicopter footage, phone video from witnesses, press conferences and memorials;
  - after an accident, the investigation report itself is a video;
  - hundreds of comments per story, with replies, likes and sorting;
  - a social feed, a video library, and replays of your own landings.

## Controls (keyboard)

| Action | Keys |
|---|---|
| Pitch / roll | W S A D or arrow keys |
| Rudder | Q / E |
| Throttle | Shift / Ctrl (F1 idle, F4 full) |
| Flaps | F down, V up |
| Gear / brakes / parking brake | G / B / P |
| Spoilers / reverse | X / R |
| Autopilot / autothrottle | Z / T |
| Cameras | 1 cockpit, 2 external, 3 chase, 4 tower, 5 flyby, 6 cabin, 7 wing, 8 free, C next |
| ATC / checklist / map / HUD | Tab / K / M / H |
| Walk around, interact | arrow keys and Space, Shift runs |
| Sim rate | = / - |
| Pause | Esc |

Gamepads and touch controls (on phones and tablets) are supported too.

## Building

`export_presets.cfg` contains presets for Windows Desktop, Linux and Android. With the Godot 4.4.1 export templates installed:

```
godot --headless --path . --export-release "Windows Desktop" ../build/windows/ProjectSkyfall.exe
godot --headless --path . --export-release "Linux" ../build/linux/ProjectSkyfall.x86_64
```

Android also needs Godot's Android SDK and keystore settings (Editor Settings → Export → Android). Phones automatically use the Mobile renderer and lower quality presets.

## Tests

`tests/` holds headless checks and visual render tests:

- `compile_all` loads every script and shader;
- `review_smoke` opens every menu screen and runs eight back-to-back flights;
- `session_test` flies a complete trip;
- the `*_shot` scenes render screenshots.

They are excluded from exports.
