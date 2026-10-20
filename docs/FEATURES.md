# Feature matrix

Legend:

- **Tested**: implemented and covered by automated tests in `engine/` (run with `./gradlew :engine:test`).
- **Built**: implemented in the app and compiles (shared UI against Compose, Android code against the
  Android 15 framework), but not yet run on a device.
- **Partial**: works with the limitation noted.
- **No**: not supported, with the reason.

## Game directory manager

| Feature | State | Notes |
| --- | --- | --- |
| Choose, change, forget folders with the system picker | Built | Persistable SAF permissions; a permission is released only when no other purpose uses the folder |
| Separate purposes: game data, CLEO scripts, AML mods, export | Built | |
| Picker starts near the right place | Built | `AMLMods/<package>` for AML mods, `Download` for exports, `Android/data/<package>` on Android 10 and older |
| Explain Android 11+ restrictions | Built | Game Directory screen and docs; never implies that picking a folder unlocks `Android/data` |
| Detect installed game, version and ABI | Built | Package manager with `<queries>`; libraries read from base and split APKs; running ABI from the native library folder |
| Scan folders read-only, classify location with confidence | Tested | `GameDirectoryScanner` with entry, depth and size limits |
| Validate before installing | Tested | Install planner: blockers, ABI checks, missing loaders |
| Backup, restore, conflict detection, logs | Tested | See Mod Manager |
| Export to a user-chosen folder | Built | Export folder or system "save as" |
| Root access | No | Never requested, by design |

## Compatibility Center

| Feature | State | Notes |
| --- | --- | --- |
| Six states with evidence and confidence | Tested | `CompatibilityEvaluator`; file names never yield "Compatible" |
| Profiles: game, CLEO Android, CLEO library for AML, AML, native mods, `.fxt`, PC scripts, main.scm, limit adjuster, Definitive Edition | Tested | Requirements, install steps, limitations and sources per profile |
| Native mod inspection (ELF, ABI, AML exports, GUID hints) | Tested | Static parsing only; nothing is loaded |
| Searchable, filterable cards | Built | |
| Exportable Markdown report | Tested / Built | Renderer tested; export, share and copy in the app |
| Downloading or installing loaders | No | By design: Rodwave links to official pages after confirmation and never installs loaders |

## Editor

| Feature | State | Notes |
| --- | --- | --- |
| Syntax highlighting, line numbers, current line, bracket matching | Tested / Built | Highlighter and bracket matcher tested; drawing built |
| Auto-indent, dedent of `end`/`else`/`until`, formatter | Tested / Built | |
| Find and replace (case, whole word, regex with groups) | Tested / Built | |
| Undo and redo with typing coalescing | Tested / Built | |
| Tabs, unsaved markers, close confirmation | Built | |
| Diagnostics with line and column, live while typing | Tested / Built | Compiled in the background about 0.7 s after typing stops |
| Autocomplete (commands, keywords, labels, variables, constants, enums, models) | Tested / Built | |
| Command help (Sanny-style status bar, current parameter) | Tested / Built | |
| Outline, go to line, snippets, compare with saved | Tested / Built | Outline and diff tested |
| Font size, theme, toggles for autocomplete, indent, symbol bar, live diagnostics | Built | |
| Autosave and crash recovery | Built | Recovery snapshots of unsaved documents; restore prompt at start |
| Import and export of sources | Built | |
| Very large files | Partial | Highlighting and diagnostics re-run on the whole file per edit, so files with tens of thousands of lines may feel slow |

## Compiler and decompiler

| Feature | State | Notes |
| --- | --- | --- |
| `.csa`/`.csi` compilation, Sanny-compatible syntax | Tested | See [SCRIPT_LANGUAGE.md](SCRIPT_LANGUAGE.md) |
| Output validation before success is reported | Tested | Every instruction decoded and compared; coverage and jump targets checked |
| Diagnostics with codes, lines, columns and hints | Tested | |
| PC CLEO detection and porting hints | Tested | |
| Decompiler with labels, jumps, strings, variables, arrays | Tested | Control-flow guided; unreachable bytes kept as `hex` |
| Byte-exact round trip | Tested | Includes 300 random byte inputs and 200 random instruction streams |
| main.scm header parsing and read-only listing | Tested | |
| main.scm compilation | No | Out of scope for 0.1 |
| Batch compile and validate-only runs | Built | |
| Opcode library: built-in core set | Tested | Checked against Sanny Builder Library sa_mobile 0.517 |
| Opcode library: import or download of the full library | Tested / Built | Importer tested; download only on request, HTTPS only |

## Mod manager

| Feature | State | Notes |
| --- | --- | --- |
| Import single files and ZIP archives | Tested | ZIP entries with `..`, absolute paths or duplicates are rejected; size limits |
| Categorize, inspect findings, instructions from archives | Tested / Built | |
| Dry-run plan before any change | Tested | Create, replace, skip identical, delete, restore |
| Confirmation for replacing files Rodwave does not own | Tested | |
| Backups of replaced files, verified writes, rollback on failure | Tested | Includes failure injection |
| Uninstall and restore of earlier operations | Tested | Backups are hash-checked before restoring |
| Missing loader and ABI checks | Tested | Uses the ABI the game actually runs with |
| Export a mod (file or ZIP) | Built | |

## Utilities

| Feature | State | Notes |
| --- | --- | --- |
| Opcode browser with enums | Built | |
| Script inspector (verdict, findings, hex, opcode histogram) | Tested / Built | |
| Binary metadata viewer (ELF, ZIP, script, text by content) | Tested / Built | |
| Diff of documents or files | Tested / Built | |
| Templates and snippets | Tested | Every template compiles and round-trips |
| Validation and dependency analysis per project | Built | Uses the compiler and the analyzer |
| Workspace backup and restore with dry run | Tested / Built | |
| Documentation library (offline) | Built | |
| Operation console with export | Built | |

## Platform and UI

| Feature | State | Notes |
| --- | --- | --- |
| Phone and tablet layouts (bottom bar, drawer, navigation rail ≥ 600 dp) | Built | |
| Three dark themes | Built | Sunset, Midnight, AMOLED |
| Launcher icon drawn as vectors (adaptive, round, themed) | Built | Same geometry as the in-app logo |
| Edge-to-edge, predictive back, splash screen | Built | |
| Works offline, no analytics | Built | |
| Native code (JNI) | No | Nothing needs it; all parsing is Kotlin with bounds checks |
