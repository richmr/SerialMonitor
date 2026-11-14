// Minimal SMP example: a few updating rows, graphable values and two commands.
#include <Arduino.h>
#include <smp.h>

#ifndef LED_BUILTIN
#define LED_BUILTIN 2
#endif

static uint32_t periodMs = 200;

static void onLed(const char* args) {
  bool on = strcmp(args, "on") == 0;
  digitalWrite(LED_BUILTIN, on ? HIGH : LOW);
  smp::log("led", "state=%s", on ? "on" : "off");
}

static void onRate(const char* args) {
  long ms = atol(args);
  if (ms < 10 || ms > 10000) {
    smp::error("rate", "period must be 10..10000 ms, got \"%s\"", args);
    return;
  }
  periodMs = (uint32_t)ms;
  smp::log("rate", "period=%lums", (unsigned long)periodMs);
}

void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
  Serial.begin(115200);
  smp::begin(Serial, "smp-basic", "0.1.0");
  smp::command("led", "<on|off>", "Switch the on-board LED", onLed);
  smp::command("rate", "<ms>", "Set the report period", onRate);
}

void loop() {
  static uint32_t last = 0;
  static uint32_t count = 0;
  smp::poll();

  uint32_t now = millis();
  if (now - last < periodMs) return;
  last = now;
  count++;

  float t = now / 1000.0f;
  smp::log("wave", "sin=%.3f cos=%.3f", sinf(t), cosf(t));
  smp::log("sys", "heap=%u uptime=%lus", (unsigned)ESP.getFreeHeap(), (unsigned long)(now / 1000));
  if (count % 25 == 0) smp::warn("demo", "every 25th report n=%lu", (unsigned long)count);
  Serial.println("heartbeat");  // untagged lines still work: identical ones just count up
}
