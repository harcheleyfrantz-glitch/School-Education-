# Status, verification and blockers

Version 0.1.0. This page states plainly what has been checked and how, and what has not.

## Verified

| What | How |
| --- | --- |
| Engine: compiler, decompiler, script analyzer, main.scm parser, compatibility evaluator, ELF inspector, safe ZIP reader, mod planner and installer, projects, workspace backup, editor logic | 92 JUnit tests, all passing (`./gradlew :engine:test`). They include byte-exact round trips of 300 random byte inputs and 200 random instruction streams, fuzzed main.scm headers, malformed ELF and ZIP files, and installs with injected failures that must roll back |
| Built-in opcode table (427 commands) | Compared with the Sanny Builder Library `sa_mobile` 0.517 by a maintainer test (`RODWAVE_SBL_JSON=… ./gradlew :engine:test`) during development; the test is skipped when the variable is not set |
| Sample scripts and project templates | Compile with no errors or warnings using the built-in table, and their decompiled listings recompile to identical bytes (`SamplesTest`) |
| Shared UI (every screen) | Compiles without warnings against Compose Multiplatform 1.7.3, which tracks the same Compose 1.7 / Material 3 1.3 APIs as the app's Compose BOM 2024.12.01 (`./gradlew :desktop:compileKotlin`) |
| Android layer (activity, SAF storage, game detection, platform services) | Type-checked against the Android 15 framework (Robolectric `android-all` 15) with stubs for the four `androidx.activity` APIs it uses. A bytecode scan found no Java library calls newer than Android 8.0 (API 26), the minimum supported version |
| Debug APK | Built by the GitHub Actions workflow (`.github/workflows/android.yml`), which also runs the engine tests; the APK is attached to each run as the `rodwave-debug-apk` artifact |
| Launcher icon | The vector drawables parse, and an SVG rendering of the same paths was reviewed (adaptive, round and themed masks) |

## Not verified

- **Release builds and lint.** The debug APK builds on GitHub Actions (see below); the minified
  release build (R8) and Android lint have not been run yet.
- **Nothing has run on a phone, tablet or emulator.** That includes layouts on real screens, touch and
  keyboard handling in the editor, the system pickers, persisted folder permissions and game detection.
- **The desktop preview window and screenshot renderer have never run**, for the same reason as the APK.
- **No script has been run in the game.** Rodwave validates bytecode; it cannot execute scripts. This
  includes the samples and templates.
- **Behaviour of specific loader builds**: which folder a CLEO build reads scripts from, and whether it
  loads `.fxt` files.

## Blockers

1. **Device testing** has not happened yet. Suggested first checks: create a project,
   compile a template, pick an `AMLMods` folder, scan it, install a compiled script through the Mod
   Manager and restore it.

## Known limitations

- `main.scm` is listed read-only; compiling it is not supported.
- The built-in opcode table has 427 commands. All ~2,700 SA Mobile commands need the Sanny Builder Library,
  which you download or import yourself (it is not bundled because its repository states no licence).
- On Android 11 and newer, `Android/data` cannot be opened through the system picker, so files that must
  live there have to be copied with a file manager that has access. Rodwave says so instead of
  attempting workarounds.
- Memory addresses for `0DD8`/`0DD9` are version- and ABI-specific; Rodwave flags their use but cannot
  check them.
- Syntax highlighting and live diagnostics process the whole file on each edit; very large files may
  feel slow.
- There is no native (JNI) code; nothing in Rodwave needs it.
