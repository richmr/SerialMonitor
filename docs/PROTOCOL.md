# SMP v1 — Serial Monitor Protocol

A small, human-readable line protocol for ESP32 (or any) firmware. It is plain
text, so output still reads fine in `pio device monitor` or any terminal. The
monitor uses it to decide which lines are "the same kind of message" (one row
per kind, updated in place), which values can be graphed, and which commands
the device accepts.

Nothing here is required. Untagged output still works (see "Lines without a
tag"). The protocol just makes grouping exact instead of guessed.

## 1. Framing

- One message per line, terminated by `\n`. A trailing `\r` is ignored.
- UTF-8 text. ANSI colour codes are stripped by the monitor.
- Keep lines under 4 KB.
- Default link: 115200 baud, 8 data bits, no parity, 1 stop bit, no flow control.

## 2. Device → monitor

```
[tag] free text and/or key=value pairs
[tag:L] same, with a level
```

| Part  | Rule |
|-------|------|
| `tag` | 1–32 chars, starts with a letter, then letters, digits, `_ . - /`. The tag **is the message type**: the monitor keeps one row per tag and overwrites it on every arrival. |
| `:L`  | Optional level: `E` error, `W` warning, `I` info, `D` debug, `V` verbose. |
| body  | Anything. Numbers in the body can be graphed. |

### Values

Any number in the body is graphable. A number gets a name when it is written
as `name=value` or `name: value`; otherwise it is named by position (`#1`,
`#2`, …). A unit may be attached directly to the number.

```
[imu] ax=0.02 ay=-0.98 az=0.11
[env] temp=23.5C hum=41%
[loop:D] dt=1042us heap=182344
[motor:W] stall detected pos=1200
```

Prefer `name=value` so a series keeps its name even if you reorder the line.
Strings with spaces are quoted: `state="homing x"`.

### Choosing tags

Use one tag per thing you want to watch as a single, updating row:
`[imu]`, `[wifi]`, `[motor/x]`, `[motor/y]`. Two different messages that
should not overwrite each other need different tags.

## 3. Monitor → device

```
command arg1 arg2\n
```

One command per line; the first word is the command name, the rest is passed
to the handler unparsed. The monitor's line ending is selectable (LF default).

`?` is reserved: the device answers with its `[!hello]` line and one `[!cmd]`
line per command.

## 4. Meta lines (tags starting with `!`)

Sent by the device to describe itself. `!` tags are reserved for the protocol.

| Line | Meaning |
|------|---------|
| `[!hello] smp=1 name="BenchTest" fw="0.3.1"` | Sent once at boot and in reply to `?`. The monitor treats it as "device (re)started": rows not seen since are dimmed, and the device's command list is reset. |
| `[!cmd] name=move args="<steps> [speed]" desc="Move the stepper"` | Declares one command. Fills the command picker / autocomplete. Optional `example="move 200 50"` is what gets inserted when picked. |
| `[!err] cmd=foo msg="unknown command"` | A command failed. Shown as an error row. |
| `[!ok] cmd=move` | Optional acknowledgement. |

## 5. Protocol description file (optional)

For firmware that does not announce its commands, the same information can be
loaded from a JSON file (menu → "Load protocol file…"):

```json
{
  "smp": 1,
  "name": "BenchTest",
  "commands": [
    { "name": "move", "args": "<steps> [speed]", "desc": "Move the stepper", "example": "move 200 50" },
    { "name": "stop", "desc": "Stop immediately" }
  ]
}
```

Commands announced by the device and commands from the file are merged.

## 6. Lines without a tag

The monitor also understands, without any firmware changes:

| Format | Example | Grouped by |
|--------|---------|------------|
| ESP-IDF log | `I (1234) wifi: connected ip=10.0.0.5` | component tag + message shape |
| arduino-esp32 log | `[  1234][W][main.cpp:42] loop(): slow frame` | `file:line` |
| anything else | `Temp: 23.5 C` | message shape |

"Message shape" is the line with every number replaced by a placeholder, so
`Temp: 23.5 C` and `Temp: 23.7 C` land on the same row. ROM boot output
(`rst:0x1 (POWERON_RESET)…`, `ESP-ROM:…`) is recognised as a restart.

## 7. Firmware library

`esp32/SerialMonitorProtocol/src/smp.h` is a header-only helper:

```cpp
#include <smp.h>

void onLed(const char* args) { digitalWrite(LED_BUILTIN, strcmp(args, "on") == 0); }

void setup() {
  Serial.begin(115200);
  smp::begin(Serial, "BenchTest", "0.3.1");
  smp::command("led", "<on|off>", "Switch the LED", onLed);
}

void loop() {
  smp::poll();                                   // handle incoming commands
  smp::log("env", "temp=%.1fC hum=%d%%", t, h);  // [env] temp=23.5C hum=41%
  smp::warn("motor", "stall pos=%ld", pos);      // [motor:W] stall pos=1200
}
```
