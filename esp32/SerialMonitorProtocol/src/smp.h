// SMP v1 — Serial Monitor Protocol helper for Arduino-style firmware (ESP32).
// Header-only. See docs/PROTOCOL.md in the SerialMonitor repo.
//
//   smp::begin(Serial, "BenchTest", "0.3.1");
//   smp::command("led", "<on|off>", "Switch the LED", onLed);
//   smp::log("env", "temp=%.1fC hum=%d%%", t, h);   // -> [env] temp=23.5C hum=41%
//   smp::poll();                                    // in loop(): runs commands
//
// Not thread-safe: call from one task, or guard calls with your own mutex.
#pragma once

#include <Arduino.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#ifndef SMP_MAX_COMMANDS
#define SMP_MAX_COMMANDS 16
#endif
#ifndef SMP_LINE_MAX
#define SMP_LINE_MAX 192  // longest outgoing body and longest incoming command
#endif

namespace smp {

typedef void (*Handler)(const char* args);

namespace detail {

struct Command {
  const char* name;
  const char* args;
  const char* desc;
  Handler fn;
};

struct State {
  Stream* io = nullptr;
  const char* name = "device";
  const char* fw = "";
  Command commands[SMP_MAX_COMMANDS];
  uint8_t commandCount = 0;
  char rx[SMP_LINE_MAX];
  uint16_t rxLen = 0;
  bool rxOverflow = false;
};

inline State& state() {
  static State s;
  return s;
}

// Prints key="value", replacing characters that would break the quoting.
inline void printQuoted(Stream& io, const char* key, const char* value) {
  io.print(key);
  io.print("=\"");
  for (const char* p = value; *p; ++p) {
    char c = *p;
    if (c == '"') c = '\'';
    if (c == '\n' || c == '\r') c = ' ';
    io.print(c);
  }
  io.print('"');
}

inline void printCommand(Stream& io, const Command& c) {
  io.print("[!cmd] name=");
  io.print(c.name);
  if (c.args && c.args[0]) {
    io.print(' ');
    printQuoted(io, "args", c.args);
  }
  if (c.desc && c.desc[0]) {
    io.print(' ');
    printQuoted(io, "desc", c.desc);
  }
  io.print('\n');
}

inline void vlog(char level, const char* tag, const char* fmt, va_list ap) {
  State& s = state();
  if (!s.io) return;
  char body[SMP_LINE_MAX];
  vsnprintf(body, sizeof(body), fmt, ap);
  s.io->print('[');
  s.io->print(tag);
  if (level) {
    s.io->print(':');
    s.io->print(level);
  }
  s.io->print("] ");
  s.io->print(body);
  s.io->print('\n');
}

}  // namespace detail

// Sends [!hello] followed by one [!cmd] line per registered command.
inline void describe() {
  detail::State& s = detail::state();
  if (!s.io) return;
  s.io->print("[!hello] smp=1 ");
  detail::printQuoted(*s.io, "name", s.name);
  if (s.fw && s.fw[0]) {
    s.io->print(' ');
    detail::printQuoted(*s.io, "fw", s.fw);
  }
  s.io->print('\n');
  for (uint8_t i = 0; i < s.commandCount; ++i) detail::printCommand(*s.io, s.commands[i]);
}

// Call once after Serial.begin(). Strings must outlive the program (literals).
inline void begin(Stream& io, const char* name = "device", const char* fw = "") {
  detail::State& s = detail::state();
  s.io = &io;
  s.name = name;
  s.fw = fw;
  describe();
}

// Registers a command. `args` and `desc` are shown in the monitor's picker.
// Returns false when the table is full (raise SMP_MAX_COMMANDS).
inline bool command(const char* name, const char* args, const char* desc, Handler fn) {
  detail::State& s = detail::state();
  if (s.commandCount >= SMP_MAX_COMMANDS) return false;
  detail::Command& c = s.commands[s.commandCount++];
  c.name = name;
  c.args = args;
  c.desc = desc;
  c.fn = fn;
  if (s.io) detail::printCommand(*s.io, c);  // registered after begin(): announce now
  return true;
}

// [tag] printf-formatted body
inline void log(const char* tag, const char* fmt, ...) __attribute__((format(printf, 2, 3)));
inline void log(const char* tag, const char* fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  detail::vlog(0, tag, fmt, ap);
  va_end(ap);
}

#define SMP_LEVEL_FN(fn, ch)                                                              \
  inline void fn(const char* tag, const char* fmt, ...) __attribute__((format(printf, 2, 3))); \
  inline void fn(const char* tag, const char* fmt, ...) {                                 \
    va_list ap;                                                                           \
    va_start(ap, fmt);                                                                    \
    detail::vlog(ch, tag, fmt, ap);                                                       \
    va_end(ap);                                                                           \
  }
SMP_LEVEL_FN(error, 'E')  // [tag:E] ...
SMP_LEVEL_FN(warn, 'W')   // [tag:W] ...
SMP_LEVEL_FN(info, 'I')   // [tag:I] ...
SMP_LEVEL_FN(debug, 'D')  // [tag:D] ...
#undef SMP_LEVEL_FN

// [tag] key=value — one numeric value, ready to graph.
inline void value(const char* tag, const char* key, double v, uint8_t decimals = 3) {
  detail::State& s = detail::state();
  if (!s.io) return;
  s.io->print('[');
  s.io->print(tag);
  s.io->print("] ");
  s.io->print(key);
  s.io->print('=');
  s.io->print(v, (int)decimals);
  s.io->print('\n');
}

// Call from loop(). Reads pending input and runs complete command lines.
inline void poll() {
  detail::State& s = detail::state();
  if (!s.io) return;
  while (s.io->available() > 0) {
    int ch = s.io->read();
    if (ch < 0) break;
    if (ch != '\n' && ch != '\r') {
      if (s.rxLen < SMP_LINE_MAX - 1) {
        s.rx[s.rxLen++] = (char)ch;
      } else {
        s.rxOverflow = true;
      }
      continue;
    }
    if (s.rxLen == 0 && !s.rxOverflow) continue;  // blank line, or the LF of a CRLF
    s.rx[s.rxLen] = '\0';
    bool overflow = s.rxOverflow;
    s.rxLen = 0;
    s.rxOverflow = false;
    if (overflow) {
      s.io->print("[!err] msg=\"command too long\"\n");
      continue;
    }
    char* name = s.rx;
    while (*name == ' ') ++name;
    char* args = strchr(name, ' ');
    if (args) {
      *args++ = '\0';
      while (*args == ' ') ++args;
    } else {
      args = name + strlen(name);  // empty string
    }
    if (!*name) continue;
    if (strcmp(name, "?") == 0) {
      describe();
      continue;
    }
    bool found = false;
    for (uint8_t i = 0; i < s.commandCount; ++i) {
      if (strcmp(name, s.commands[i].name) == 0) {
        found = true;
        if (s.commands[i].fn) s.commands[i].fn(args);
        break;
      }
    }
    if (!found) {
      s.io->print("[!err] cmd=");
      s.io->print(name);
      s.io->print(" msg=\"unknown command\"\n");
    }
  }
}

}  // namespace smp
