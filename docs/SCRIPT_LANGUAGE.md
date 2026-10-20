# Rodwave script language

Rodwave compiles a Sanny Builder–compatible source language to CLEO bytecode for *GTA: San Andreas* on
Android. This page lists what the compiler accepts. Everything shown here is covered by the engine tests
or was compiled while writing this page.

## File layout

```
{$CLEO .csa}                 // output type: .csa (auto-start) or .csi (CLEO menu); .cs is PC CLEO
0000: nop                    // a CLEO script must not start with a label (see C093)
03A4: script_name 'MYMOD'    // up to 7 characters

while true
    wait 250
    // ...
end
```

- One statement per line. Comments: `// to the end of the line`, `/* block */` and `{ block }` (a brace
  followed by `$` is a directive instead).
- Directives: `{$CLEO .csa}`, `{$CLEO .csi}`, `{$CLEO .cs}` set the output type; `{$INCLUDE file}` or
  `{$I file}` inserts another file of the same project (nesting up to 16 levels, cycles are reported).
  `{$VERSION}`, `{$USE}`, `{$O}`, `{$OPCODE}`, `{$NOSOURCE}` and `{$EXTERNAL}` are accepted and ignored
  with an information message. Without `{$CLEO}`, the project's default type is used.
- CLEO scripts are headerless: jump targets are stored as negative offsets from the start of the script,
  so a label at offset 0 cannot be encoded. Start every script with an instruction such as `0000: nop`.

## Commands

```
0001: wait 0 ms              // opcode form: the number selects the command
wait 250                     // keyword form: the name comes from the opcode library
8256: not is_player_playing $PLAYER_CHAR   // bit 15 set = negated condition
not 0256: is_player_playing $PLAYER_CHAR   // same, written with 'not'
01F5: get_player_char $PLAYER_CHAR store_to 0@
```

After an opcode, words that are not values (`ms`, `store_to`, `to`, `amount` …) are descriptive and
ignored. Parameter counts, input/output direction and value kinds are checked against the opcode library.
Keyword aliases: `jump`/`goto`, `jf`/`else_jump`, `gosub`, `return`, `terminate_this_script`/`end_thread`,
`start_new_script`/`create_thread`.

## Values

| Kind | Examples |
| --- | --- |
| Integers | `5`, `-1`, `0x1F` (32-bit) |
| Floats | `1.0`, `-0.5` |
| Global variables | `$12` (slot 12 = byte offset 48), `&48` (raw byte offset), `$PLAYER_CHAR` (= `$2`), `$PLAYER_ACTOR` (= `$3`) |
| Local variables | `0@` … `31@`; timers `TIMERA` (`32@`) and `TIMERB` (`33@`) |
| String variables | `0@s` (8-byte), `0@v` (16-byte), `s$12`, `v$12` |
| Arrays | `$100(0@,10i)`, `1@(2@,4f)`, `s$20(0@,3s)`: base, index variable, size and element type (`i`, `f`, `s`, `v`) |
| Text | `'TEXT'` = short string (up to 7 characters in 8 bytes, or 15 in 16 bytes, chosen by the parameter); `"Text"` = variable-length string (up to 255 characters, Latin-1) |
| Labels | `:NAME` defines, `@NAME` references |
| Models | `#CHEETAH`, `#INFERNUS` — San Andreas vehicle and weapon model names |
| Enums | `TouchPoints.RightTop`, `Platform.Android`, `GameVerInternal.VER_GTASA_2_00_OR_HIGHER`, and every enum of an imported library |
| Booleans | `true`, `false` |

## Assignments and operators

```
0@ = 5          0@ += 1        0@ -= 1        0@ *= 2        0@ /= 2
0@++            0@--
1@ +=@ 1.0      1@ -=@ 1.0     // timed: scaled by the frame time
0@ =# 1@        1@ =# 0@       // integer <-> float conversion
$10 = 0@        2@ = TIMERA
```

The opcode is chosen from the operator and the operand kinds (global or local, integer or float,
constant or variable). If neither side shows whether a value is an integer or a float, declare it:

```
int counter = 0
float speed
var 3@: Float end
```

Named variables declared with `int` or `float` get free local slots automatically. Expressions with
more than one operator are not supported; split them into separate statements.

## Conditions

```
if
    0@ == 1
then
    wait 0
end

if and                         // or: if or — up to 8 conditions
    0@ > 5
    0256: is_player_playing $PLAYER_CHAR
then
    wait 0
else
    0@ = 0
end

if 0@ > 10 then                // single condition on one line
    break
end
```

Comparisons: `==`, `<>` (or `!=`), `>`, `>=`, `<`, `<=`; text can only be compared with `==`/`<>`.
The classic form ending the conditions with `jf @label` instead of `then` also works.

## Loops

```
while true                     // also: while <condition>
    wait 0
end

repeat
    wait 0
    1@ += 1
until 1@ > 3

for 2@ = 1 to 10 step 2        // also: downto
    wait 0
    if 2@ == 5 then
        continue
    end
end
```

`break` and `continue` work in every loop. The compiler warns (L005) about a loop that never waits,
which would freeze the game.

## Constants, data and subroutines

```
const DELAY = 500, CAR = #CHEETAH

hex
  01 02 03 04
end

gosub @HELPER
004E: terminate_this_script

:HELPER
wait DELAY
return
```

## PC CLEO and mobile differences

The SA Mobile opcode table differs from the PC game from opcode 0A4E upwards. Rodwave rejects PC-only
CLEO commands with an explanation: for example, `0A93: end_custom_thread` → use `004E:
terminate_this_script`; `is_key_pressed` → use touch points (`0DE0: get_touch_point_state`); PC
`write_memory`/`read_memory` → CLEO Android's `0DD9`/`0DD8`, whose parameters differ. Memory addresses
are specific to one game version and ABI; guard such code with `0DD6: get_game_version`.

## Diagnostics

Errors stop compilation; warnings and information messages do not. Every message has a code, a line and
a column, and most have a hint.

| Codes | Stage |
| --- | --- |
| P001–P035 | Parsing: unexpected text, malformed numbers, arrays, operators, one statement per line |
| C001–C004 | `{$INCLUDE}`: not available, too deep, circular, not found |
| C010–C014 | Directives and output type |
| C020–C024 | Constants and declared variables |
| C030–C037 | Unknown models, globals, names; variable and array ranges |
| C040–C045 | `break`/`continue` outside loops, duplicate labels, condition counts |
| C050–C055 | Unknown, ambiguous or PC-only commands; conditions vs. plain commands |
| C060–C074 | Parameter counts, input/output kinds, literals vs. variables, text rules |
| C080–C091 | Assignments, operators, integer/float typing, text operations |
| C092–C093 | Undefined labels; a jump target at offset 0 |
| C100 | Empty script |
| V001–V004 | Output validation (the compiled bytes are decoded again and compared; any mismatch is a compiler bug and nothing is written) |
| L001–L007 | Lint warnings: invalid `00D6` counts, running past the end, loops without `wait`, unsupported commands, local slots beyond 33@ |

## Decompiler output

The decompiler prints opcode-form listings that the compiler accepts. After decompiling, Rodwave
recompiles the listing and compares it with the input byte for byte; the inspector shows whether the
round trip is identical. Bytes that are not reachable as code are kept as `hex … end` blocks so nothing
is lost. main.scm files get a read-only listing; Rodwave does not compile main.scm.
