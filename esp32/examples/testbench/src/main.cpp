// SerialMonitor test bench.
//
// Output that exercises each part of the monitor:
//   graphs       [sine] y=…          sine wave, adjustable period
//                [ramp] saw=… tri=…  sawtooth and triangle ramps
//   colours      [lvl/debug:D] [lvl/info:I] [lvl/warn:W] [lvl/error:E]
//   aggregation  two kinds of info line in each format the monitor groups:
//                SMP tags, ESP-IDF style, arduino-esp32 style and untagged
//   commands     announced with [!cmd]; errors come back as [!err]
//   restarts     `reboot` (rows from before the restart are dimmed)
//
// Type `help` (or `?`) in the command box for the list.
#include <Arduino.h>
#include <math.h>
#include <smp.h>

static const char* kName = "smp-testbench";
static const char* kVersion = "0.1.0";

struct Wave {
  const char* name;
  bool on;
  uint32_t periodMs;
  double phase;  // 0..1, advanced by dt/period so period changes don't jump
};

static Wave sine = {"sine", true, 2000, 0};
static Wave ramp = {"ramp", true, 4000, 0};

static uint32_t sampleMs = 50;   // wave samples: 20 per second
static bool logsOn = true;       // level demo lines
static bool infoOn = true;       // aggregation demo lines
static uint32_t lastSample = 0;
static uint32_t lastSlow = 0;
static uint32_t slowCount = 0;

// ---- helpers ----------------------------------------------------------------

// Splits "word rest" in place: returns the first word, *rest points past it.
static char* nextWord(char* s, char** rest) {
  while (*s == ' ') ++s;
  char* end = s;
  while (*end && *end != ' ') ++end;
  if (*end) *end++ = '\0';
  while (*end == ' ') ++end;
  *rest = end;
  return s;
}

static int parseOnOff(const char* s) {
  if (strcmp(s, "on") == 0 || strcmp(s, "1") == 0) return 1;
  if (strcmp(s, "off") == 0 || strcmp(s, "0") == 0) return 0;
  return -1;
}

static Wave* findWave(const char* name) {
  if (strcmp(name, sine.name) == 0) return &sine;
  if (strcmp(name, ramp.name) == 0) return &ramp;
  return nullptr;
}

static void cmdError(const char* cmd, const char* msg) {
  Serial.printf("[!err] cmd=%s msg=\"%s\"\n", cmd, msg);
}

static void cmdOk(const char* cmd) { Serial.printf("[!ok] cmd=%s\n", cmd); }

static void printStatus() {
  smp::log("status", "sine=%s sine_period=%lums ramp=%s ramp_period=%lums rate=%lums logs=%s info=%s",
           sine.on ? "on" : "off", (unsigned long)sine.periodMs, ramp.on ? "on" : "off",
           (unsigned long)ramp.periodMs, (unsigned long)sampleMs, logsOn ? "on" : "off",
           infoOn ? "on" : "off");
}

// ---- commands ---------------------------------------------------------------

// sine <on|off>   /   ramp <on|off>
static void setWave(Wave& w, const char* args) {
  int v = parseOnOff(args);
  if (v < 0) {
    cmdError(w.name, "expected on or off");
    return;
  }
  w.on = v;
  cmdOk(w.name);
  printStatus();
}
static void onSine(const char* args) { setWave(sine, args); }
static void onRamp(const char* args) { setWave(ramp, args); }

// waves <on|off>
static void onWaves(const char* args) {
  int v = parseOnOff(args);
  if (v < 0) {
    cmdError("waves", "expected on or off");
    return;
  }
  sine.on = ramp.on = v;
  cmdOk("waves");
  printStatus();
}

// period <sine|ramp> <ms>
static void onPeriod(const char* args) {
  char buf[SMP_LINE_MAX];
  strncpy(buf, args, sizeof(buf) - 1);
  buf[sizeof(buf) - 1] = '\0';
  char* rest;
  char* name = nextWord(buf, &rest);
  Wave* w = findWave(name);
  if (!w) {
    cmdError("period", "usage: period <sine|ramp> <ms>");
    return;
  }
  long ms = atol(rest);
  if (ms < 100 || ms > 600000) {
    cmdError("period", "ms must be 100..600000");
    return;
  }
  w->periodMs = (uint32_t)ms;
  cmdOk("period");
  printStatus();
}

// rate <ms>
static void onRate(const char* args) {
  long ms = atol(args);
  if (ms < 10 || ms > 10000) {
    cmdError("rate", "ms must be 10..10000");
    return;
  }
  sampleMs = (uint32_t)ms;
  cmdOk("rate");
  printStatus();
}

// logs <on|off>
static void onLogs(const char* args) {
  int v = parseOnOff(args);
  if (v < 0) {
    cmdError("logs", "expected on or off");
    return;
  }
  logsOn = v;
  cmdOk("logs");
  printStatus();
}

// info <on|off>
static void onInfo(const char* args) {
  int v = parseOnOff(args);
  if (v < 0) {
    cmdError("info", "expected on or off");
    return;
  }
  infoOn = v;
  cmdOk("info");
  printStatus();
}

// burst <n>: n lines as fast as possible, to watch a row's count jump
static void onBurst(const char* args) {
  long n = atol(args);
  if (n < 1 || n > 1000) {
    cmdError("burst", "n must be 1..1000");
    return;
  }
  for (long i = 1; i <= n; ++i) smp::log("burst", "i=%ld of=%ld", i, n);
  cmdOk("burst");
}

// fail: an on-demand error row
static void onFail(const char*) { cmdError("fail", "this command always fails (on purpose)"); }

static void onStatus(const char*) { printStatus(); }

static void onHelp(const char*) { smp::describe(); }

static void onReboot(const char*) {
  smp::warn("sys", "rebooting in 200 ms");
  Serial.flush();
  delay(200);
  ESP.restart();
}

// ---- output -----------------------------------------------------------------

static void advance(Wave& w, uint32_t dtMs) {
  w.phase += (double)dtMs / (double)w.periodMs;
  w.phase -= floor(w.phase);
}

static void emitWaves(uint32_t dtMs) {
  advance(sine, dtMs);
  advance(ramp, dtMs);
  if (sine.on) smp::log("sine", "y=%.4f", sin(2.0 * M_PI * sine.phase));
  if (ramp.on) {
    double saw = ramp.phase;                                         // 0 -> 1, drop
    double tri = ramp.phase < 0.5 ? 2 * ramp.phase : 2 - 2 * ramp.phase;  // 0 -> 1 -> 0
    smp::log("ramp", "saw=%.4f tri=%.4f", saw, tri);
  }
}

// Once a second. Every line kind below gets its own row in the monitor.
static void emitSlow(uint32_t now) {
  slowCount++;
  uint32_t up = now / 1000;

  if (logsOn) {
    // Same message in every level, so the rows differ only in colour.
    smp::debug("lvl/debug", "debug line n=%lu", (unsigned long)slowCount);
    smp::info("lvl/info", "info line n=%lu", (unsigned long)slowCount);
    if (slowCount % 3 == 0) smp::warn("lvl/warn", "warning line n=%lu", (unsigned long)slowCount);
    if (slowCount % 5 == 0) smp::error("lvl/error", "error line n=%lu", (unsigned long)slowCount);
    Serial.printf("[lvl/verbose:V] verbose line n=%lu\n", (unsigned long)slowCount);
  }

  if (infoOn) {
    // Two kinds of info message per format. Each kind keeps one row whose
    // count goes up; the two kinds never overwrite each other.

    // 1. SMP tags: grouped by tag.
    float temp = 22.0f + 1.5f * sinf(now / 9000.0f);
    smp::info("env", "temp=%.2fC hum=%d%%", temp, 40 + (int)(slowCount % 7));
    smp::info("net", "rssi=%ddBm ch=6 ip=192.168.1.42", -55 - (int)(slowCount % 11));

    // 2. ESP-IDF style: grouped by component + message shape (numbers ignored).
    Serial.printf("I (%lu) wifi: connected rssi=%d\n", (unsigned long)now, -60 + (int)(slowCount % 5));
    Serial.printf("I (%lu) heap: free=%u min=%u\n", (unsigned long)now, (unsigned)ESP.getFreeHeap(),
                  (unsigned)ESP.getMinFreeHeap());

    // 3. arduino-esp32 style: grouped by file:line, so these are two rows.
    Serial.printf("[%6lu][I][sensor.cpp:41] read(): sample=%lu\n", (unsigned long)now,
                  (unsigned long)(slowCount * 7 % 100));
    Serial.printf("[%6lu][I][motor.cpp:88] step(): pos=%lu\n", (unsigned long)now,
                  (unsigned long)(slowCount * 25));

    // 4. Untagged: grouped by shape, so these are two rows as well.
    Serial.printf("Uptime: %lu s\n", (unsigned long)up);
    Serial.printf("Loop count %lu, last dt %lu ms\n", (unsigned long)slowCount, (unsigned long)sampleMs);

    // Identical untagged lines just count up.
    Serial.println("heartbeat");
  }
}

// ---- main -------------------------------------------------------------------

void setup() {
  Serial.begin(115200);
  uint32_t t0 = millis();
  while (!Serial && millis() - t0 < 2000) delay(10);  // native USB: wait for the host briefly

  smp::begin(Serial, kName, kVersion);
  smp::command("help", "", "List commands (same as ?)", onHelp);
  smp::command("status", "", "Print current settings", onStatus);
  smp::command("sine", "<on|off>", "Enable/disable the sine wave", onSine);
  smp::command("ramp", "<on|off>", "Enable/disable the ramp waves", onRamp);
  smp::command("waves", "<on|off>", "Enable/disable all waves", onWaves);
  smp::command("period", "<sine|ramp> <ms>", "Set a wave's period", onPeriod);
  smp::command("rate", "<ms>", "Set the wave sample interval", onRate);
  smp::command("logs", "<on|off>", "Enable/disable the level demo lines", onLogs);
  smp::command("info", "<on|off>", "Enable/disable the aggregation demo lines", onInfo);
  smp::command("burst", "<n>", "Send n lines at once", onBurst);
  smp::command("fail", "", "Reply with an error", onFail);
  smp::command("reboot", "", "Restart the device", onReboot);

  smp::info("sys", "boot reset_reason=%d cpu=%luMHz", (int)esp_reset_reason(),
            (unsigned long)getCpuFrequencyMhz());
  printStatus();
  lastSample = lastSlow = millis();
}

void loop() {
  smp::poll();
  uint32_t now = millis();

  uint32_t dt = now - lastSample;
  if (dt >= sampleMs) {
    lastSample = now;
    emitWaves(dt);
  }
  if (now - lastSlow >= 1000) {
    lastSlow += 1000;
    emitSlow(now);
  }
}
