# PlatformIO hook: ask the SerialMonitor app to let go of the serial port
# while an upload runs, then take it back afterwards.
#
# platformio.ini:
#   extra_scripts = post:path/to/pio_smp_hook.py
#
# Does nothing (silently) when the app is not running.
import socket
import time

Import("env")  # noqa: F821  (provided by PlatformIO)

SMP_HOST = "127.0.0.1"
SMP_PORT = 47800
RELEASE_SECONDS = 120  # safety net: the app takes the port back after this long


def _send(command):
    try:
        with socket.create_connection((SMP_HOST, SMP_PORT), timeout=0.5) as sock:
            sock.sendall((command + "\n").encode("ascii"))
            sock.settimeout(2.0)
            return sock.recv(128).decode("ascii", "replace").strip()
    except OSError:
        return None


def _before_upload(source, target, env):
    reply = _send("release %d" % RELEASE_SECONDS)
    if reply:
        print("SerialMonitor: " + reply)
        time.sleep(0.3)  # give the OS a moment to free the port


def _after_upload(source, target, env):
    reply = _send("resume")
    if reply:
        print("SerialMonitor: " + reply)


env.AddPreAction("upload", _before_upload)  # noqa: F821
env.AddPostAction("upload", _after_upload)  # noqa: F821
