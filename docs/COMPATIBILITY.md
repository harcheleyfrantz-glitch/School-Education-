# Compatibility notes

What Rodwave targets, what it can detect, and how it decides the state shown in the Compatibility
Center. The same knowledge is built into the app (`engine/.../compat/ComponentProfiles.kt`); each
profile there lists the sources its facts come from.

## Target game

- **GTA: San Andreas for Android**, package `com.rockstargames.gtasa`. Known versions, as enumerated by
  CLEO Android's `GameVerInternal`: 1.00, 1.01, 1.02, 1.03, 1.05, 1.05 GER, 1.06, 1.07, 1.08 and
  "2.00 or higher".
- **Opcode table: SA Mobile.** Every Android version shares it, so one compiler profile covers them all.
  It differs from the PC game from opcode 0A4E upwards; for example 0A8C–0A90 are mobile commands
  (LOAD_ALL_STREAMING_MODELS, IS_HID_RELEASED, UNLOCK_ACHIEVEMENT, RELEASE_WEAPON_LOCK, IS_HID_PRESSED)
  where PC CLEO has WRITE_MEMORY, READ_MEMORY, INT_ADD, INT_SUB and INT_MUL.
- **Not supported:** *San Andreas – Definitive Edition* (Unreal Engine, its own script table), and
  replacing or recompiling `main.scm` (Rodwave only lists it, read-only).

## Script loaders and mod loaders are different things

| Component | What it is | What Rodwave checks |
| --- | --- | --- |
| **CLEO Android** | Script loader by Alexander Blade. Runs headerless bytecode scripts: `.csa` start automatically, `.csi` from the CLEO menu. Adds opcodes 0DD0–0DF3 (memory, touch, menu) and touch support for 00E1 | CLEO scripts found in scanned folders (by content, not name); libraries named like CLEO in the game APK |
| **AndroidModLoader (AML)** | Native mod loader (MIT, by RusJJ) injected into the game APK. Loads `.so` mods that export `__GetModInfo`; ARM only (armeabi-v7a, arm64-v8a) | `libAML.so` inside the installed APK; `configs/ModLoaderCore.ini`, which AML writes on every launch |
| **CLEO library for AML** | An AML mod (GUID `net.rusjj.cleolib`) that adds CLEO script support to an AML setup | An AML mod library referencing that GUID; its config file in `configs/`, which proves it has loaded |
| **Native AML mods** | `.so` libraries loaded by AML | ELF header, ABI, AML exports (`__GetModInfo`, `__GetDepsList`, `__INeedASpecificGame`), callbacks, linked libraries; GUID-like strings as dependency hints |
| **`.fxt` text files** | `KEY text` tables used with the normal print commands | Format validation; loading depends on the CLEO build |
| **PC CLEO scripts (`.cs`)** | Scripts for Windows CLEO | Commands whose ids mean something else on mobile; the inspector lists what needs porting |

AML facts (AML 1.4.1 source): mods are loaded from `Android/data/<package>/mods/` and from what AML calls
its internal folder, `AMLMods/<package>/` on shared storage, which is loaded first by default
(`InternalModsFirst=true`). Only files ending in `.so` are loaded. Mods must match the ABI the game
process runs with; Rodwave reads that ABI from the game's native library folder, since an APK can ship
both ABIs while Android runs it as one.

## The six states

| State | Meaning |
| --- | --- |
| **Compatible** | Evidence beyond file names, e.g. AML's own config written at launch, or an inspected library whose ABI matches the running game and whose config shows it has loaded |
| **Partially compatible** | Works in principle, but something is missing or unverifiable, e.g. a mod needs AML and AML was not detected |
| **Installed but unverified** | Files are present (possibly checked by content) but nothing proves they run, e.g. a CLEO library that has not written its config yet |
| **Not detected** | A scanned location or the installed APK shows no sign of the component |
| **Incompatible** | A concrete conflict: wrong ABI, not an ELF library, missing `__GetModInfo`, PC-only commands, x86 game with AML |
| **Unknown** | Nothing to go on yet (no folder scanned, game not visible) |

Every state lists its evidence with a confidence (high, medium, low) and, where it applies, the file
path. A file name alone can at most produce "Installed but unverified". Reports can be exported as
Markdown from the Compatibility Center.

## What Android lets Rodwave see

Rodwave uses only the Storage Access Framework: it reads and writes folders you pick, keeps that
permission until you forget the folder, and requests no storage permission, no "all files" access and
no root.

| Location | Android 10 and older | Android 11 and newer |
| --- | --- | --- |
| `Android/data/com.rockstargames.gtasa` (game data, saves, AML `mods/` and `configs/`) | Can be picked | **Cannot be picked**: the system picker blocks it, and choosing another folder does not change that |
| `Android/obb/com.rockstargames.gtasa` | Can be picked | Cannot be picked (Rodwave never needs it) |
| `AMLMods/com.rockstargames.gtasa` (AML's internal mods folder) | Can be picked | Can be picked |
| `Download/…` and other shared folders | Can be picked | Can be picked |

The installed game's version, ABIs and the native libraries inside its APK are read through the package
manager (declared with `<queries>`), so they are available on every Android version.

When a destination is out of reach, install into `AMLMods/…` where that works for your setup, or export
the files and copy them with a file manager that has access.

## What Rodwave cannot know

- Which folder a given CLEO loader build reads scripts from. Rodwave finds it from scripts already on
  your device, or you choose it.
- Whether a script or mod works in the game. Rodwave validates bytecode and inspects binaries
  statically; it never runs them.
- Memory addresses used with `0DD8`/`0DD9`/`0DD2`/`0DDE`: they belong to one game version and ABI.
- Dependency lists of AML mods, which AML only reads at run time (`__GetDepsList`). GUID-like strings
  found in a library are reported as hints.
- Whether a particular CLEO build loads `.fxt` files.
