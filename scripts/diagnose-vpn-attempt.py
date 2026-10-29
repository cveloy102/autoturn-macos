#!/usr/bin/env python3
"""Bounded local diagnostic. Never log raw UAPI/config or VPN keys.

Run with sudo while the installed app is at Home/Off, then enable VPN in its UI.
After 60 seconds, the signed installed app releases AutoTurn's network settings.
The report is private and owned by the invoking user. Saved profiles are untouched.
"""
import datetime
import json
import os
from pathlib import Path
import pwd
import re
import socket
import subprocess
import threading
import time

APP = "/Applications/AutoTurn.app/Contents/MacOS/AutoTurn"
if os.geteuid() != 0 or not os.environ.get("SUDO_UID"):
    raise SystemExit("Run this script using sudo from your normal user account.")
UID = int(os.environ["SUDO_UID"])
if UID == 0:
    raise SystemExit("A normal invoking user is required.")
ACCOUNT = pwd.getpwuid(UID)
REPORT = Path(ACCOUNT.pw_dir) / "Desktop" / ("AutoTurn-VPN-attempt-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S") + ".txt")
os.umask(0o077)
fd = os.open(REPORT, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
os.fchown(fd, UID, ACCOUNT.pw_gid)
report = os.fdopen(fd, "w", buffering=1)


def record(label, value):
    report.write(label + " " + json.dumps(value, ensure_ascii=False) + "\n")


def run(args, timeout=4, as_user=False):
    options = dict(capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)
    if as_user:
        options.update(user=UID, group=ACCOUNT.pw_gid, extra_groups=[])
    try:
        process = subprocess.run(args, **options)
        return {"exit": process.returncode, "out": process.stdout[:24000], "error": process.stderr[:2000]}
    except subprocess.TimeoutExpired:
        return {"error": "timeout"}
    except OSError as error:
        return {"error": type(error).__name__}


def counters():
    result = []
    for path in Path("/var/run/autoturn/uapi").glob("utun*.sock"):
        if not re.fullmatch(r"utun[0-9]+\.sock", path.name):
            continue
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
                client.settimeout(2)
                client.connect(str(path))
                client.sendall(b"get=1\n\n")
                raw = b""
                while len(raw) < 65536:
                    block = client.recv(4096)
                    if not block:
                        break
                    raw += block
                    if raw.endswith(b"\n\n"):
                        break
            # UAPI contains secrets. Only these numeric values may leave this
            # function. Never include raw in exceptions, logging or report data.
            safe = {"interface": path.stem, "rx_bytes": 0, "tx_bytes": 0, "handshake_times": []}
            for line in raw.decode("utf-8", errors="replace").splitlines():
                key, separator, value = line.partition("=")
                if not separator or not value.isdigit():
                    continue
                if key in ("rx_bytes", "tx_bytes"):
                    safe[key] += int(value)
                elif key == "last_handshake_time_sec":
                    safe["handshake_times"].append(int(value))
                elif key == "errno":
                    safe["errno"] = int(value)
            del raw
            result.append(safe)
        except (OSError, ValueError):
            result.append({"interface": path.stem, "error": "UAPI unavailable"})
    return result


def curl(interface=None, resolve=None):
    args = ["/usr/bin/curl", "-4", "--noproxy", "*", "--silent", "--show-error",
            "--connect-timeout", "2", "--max-time", "4", "--output", "/dev/null",
            "--write-out", "http=%{http_code} remote=%{remote_ip} dns=%{time_namelookup}"]
    if interface:
        args += ["--interface", interface]
    if resolve:
        args += ["--resolve", "www.cloudflare.com:443:" + resolve]
    return run(args + ["https://www.cloudflare.com/cdn-cgi/trace"], timeout=5, as_user=True)


initial = run([APP, "--network-status"], as_user=True)
record("INITIAL", initial)
if not any(marker in initial.get("out", "") for marker in ("phase=home guard=false", "phase=off guard=false", "phase=setup guard=false")):
    report.close()
    raise SystemExit("Start at Home or Off with protection released. No network settings were changed.")
try:
    real_ip = socket.getaddrinfo("www.cloudflare.com", 443, socket.AF_INET, socket.SOCK_STREAM)[0][4][0]
except OSError:
    real_ip = None
record("SYSTEM", run(["/usr/bin/sw_vers"]))
record("DNS_BEFORE", run(["/usr/sbin/scutil", "--dns"]))
print("READY: enable VPN in AutoTurn now. Automatic recovery starts within about 60 seconds.", flush=True)
print("Private report:", REPORT, flush=True)
started = time.monotonic()
recovery_result = {}
recovery_lock = threading.Lock()


def recover():
    with recovery_lock:
        if not recovery_result:
            recovery_result.update(run([APP, "--recover-network-check"], timeout=15, as_user=True))
        return dict(recovery_result)


watchdog = threading.Timer(60, recover)
watchdog.start()
try:
    while time.monotonic() - started < 45:
        record("TIME", {"elapsed": round(time.monotonic() - started), "utc": datetime.datetime.now(datetime.timezone.utc).isoformat()})
        record("STATUS", run([APP, "--network-status"], as_user=True))
        record("ROUTE", run(["/sbin/route", "-n", "get", "1.1.1.1"]))
        values = counters()
        record("TUNNEL_COUNTERS", values)
        record("APPLICATION_HTTPS", curl())
        for value in values:
            if "error" not in value and real_ip:
                record("BOUND_VPN_HTTPS", {"interface": value["interface"], "result": curl(value["interface"], real_ip)})
        time.sleep(2)
except KeyboardInterrupt:
    record("INTERRUPTED", True)
finally:
    record("DNS_DURING", run(["/usr/sbin/scutil", "--dns"]))
    record("PF_AUTOTURN", run(["/sbin/pfctl", "-a", "com.apple/autoturn", "-sr"]))
    recovery = recover()
    watchdog.cancel()
    watchdog.join()
    record("RECOVERY", recovery)
    record("FINAL", run([APP, "--network-status"], as_user=True))
    report.close()
    print("Capture finished. Recovery:", "confirmed" if recovery.get("exit") == 0 else "not confirmed; choose Auto/Home or Off in AutoTurn", flush=True)
    print("Report:", REPORT, flush=True)
    print("Choose Auto again in the app after the test. The recovery command changes service memory only.", flush=True)
