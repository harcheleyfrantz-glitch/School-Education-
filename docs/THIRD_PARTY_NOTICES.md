# Third-party notices

Rodwave is MIT-licensed (see [LICENSE](../LICENSE)). It ships no game files and no third-party data
files. This page lists the software it builds on and the projects whose public information it relies on.

## Libraries included in the app

| Library | Licence | Used for |
| --- | --- | --- |
| Kotlin standard library | Apache License 2.0 | Language runtime |
| kotlinx.coroutines | Apache License 2.0 | Background work |
| kotlinx.serialization (JSON) | Apache License 2.0 | Settings, projects, mod records, library import |
| AndroidX Core, Activity, Lifecycle | Apache License 2.0 | Android integration |
| Jetpack Compose (UI, Foundation, Material 3, Material Icons Extended) | Apache License 2.0 | User interface and icons |

The `:desktop` development harness additionally uses JetBrains Compose Multiplatform (Apache License
2.0). Tests use JUnit 5 (Eclipse Public License 2.0) and kotlin-test (Apache License 2.0); neither is
part of the app.

## Projects referenced but not included

- **Sanny Builder Library** (github.com/sannybuilder/library): opcode names, parameters and enums of
  the `sa_mobile` game. Its repository states no licence, so Rodwave does not bundle it. Rodwave's
  small built-in opcode table was written for Rodwave and checked against `sa_mobile` version 0.517.
  Users can download or import the library themselves; the app asks first and shows the source address.
- **AndroidModLoader (AML)** by RusJJ (MIT, github.com/RusJJ/AndroidModLoader): Rodwave's descriptions
  of mod folders, configs, exported symbols and ABIs follow AML 1.4.1's source and documentation. No AML
  code is included.
- **CLEO Android** by Alexander Blade: Rodwave targets the script format and the extension commands it
  documents (0DD0–0DF3). No CLEO code is included.
- **GTA: San Andreas** is a trademark of Take-Two Interactive Software. Rodwave contains no Rockstar
  Games scripts, models, text or other assets; model names such as `#CHEETAH` are identifiers used by
  the game's scripting language.

Rodwave is not affiliated with or endorsed by any of these projects or companies.
