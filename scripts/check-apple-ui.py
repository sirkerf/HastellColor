#!/usr/bin/env python3
"""Run iPad UI checks from a cold Simulator session, without erasing its data."""

import argparse
from datetime import datetime
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
REPORTS = Path.home() / "Library/Logs/DiagnosticReports"


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True).stdout


def device_info(udid):
    devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "-j"))
    for group in devices["devices"].values():
        for device in group:
            if device["udid"] == udid:
                if ".iPad-" not in device["deviceTypeIdentifier"]:
                    raise ValueError("Choose an iPad Simulator, not another device family.")
                return device
    raise ValueError("The requested Simulator is not available: " + udid)


def springboard_status(udid):
    result = subprocess.run(
        ["xcrun", "simctl", "spawn", udid, "launchctl", "list", "com.apple.SpringBoard"],
        text=True, capture_output=True, timeout=15)
    if result.returncode:
        # Xcode owns boot/shutdown. A stopped device has no SpringBoard to query.
        if device_info(udid)["state"] != "Booted":
            return None
        raise RuntimeError(result.stderr.strip() or "Cannot inspect SpringBoard")
    return parse_service_status(result.stdout)


def parse_service_status(text):
    pid = re.search(r'"PID"\s*=\s*(\d+);', text)
    status = re.search(r'"LastExitStatus"\s*=\s*(-?\d+);', text)
    if not pid:
        raise ValueError("SpringBoard is not running")
    return {"pid": int(pid[1]), "lastExitStatus": int(status[1]) if status else 0}


def abnormal_exit(status):
    # Xcode can deliberately replace SpringBoard with SIGKILL during setup.
    # SIGSEGV (11), observed in the incident, must fail even if XCTest passed.
    return status is not None and status["lastExitStatus"] not in (0, 9)


def relevant_crash(text, udid, started):
    _, _, body = text.partition("\n")
    data = json.loads(body)
    if data.get("coalitionName") != "com.apple.CoreSimulator.SimDevice." + udid:
        return None
    captured = datetime.strptime(data["captureTime"], "%Y-%m-%d %H:%M:%S.%f %z")
    if captured < started:
        return None
    return {"process": data.get("procName"), "time": data["captureTime"],
            "exception": data.get("exception", {})}


def checks_passed(health):
    return (health.get("xcodeExitStatus") == 0 and health.get("testsStarted", False)
            and not health["errors"] and not health["crashes"])


def check(args):
    device = device_info(args.device)
    results = Path(args.results).resolve() if args.results else ROOT / "apple/.build/ui" / datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    results.mkdir(parents=True, exist_ok=False)
    print(f"UI checks: {device['name']} ({args.device})\nResults: {results}", flush=True)
    # Do not erase user drawings or reset global Simulator/Xcode preferences.
    # A cold launch clears the stale rotation/automation session after a crash.
    if device["state"] != "Shutdown":
        run("xcrun", "simctl", "shutdown", args.device)
    if device_info(args.device)["state"] != "Shutdown":
        raise RuntimeError("Simulator did not shut down")

    started = datetime.now().astimezone()
    known_reports = set(REPORTS.glob("*.ips"))
    health = {"device": args.device, "started": started.isoformat(), "states": [],
              "crashes": {}, "errors": [], "testsStarted": False}
    command = ["xcodebuild", "-project", str(ROOT / "apple/HastellColor.xcodeproj"),
               "-scheme", "HastellColor", "-destination", "platform=iOS Simulator,id=" + args.device,
               "-parallel-testing-enabled", "NO", "-collect-test-diagnostics", "never",
               "-derivedDataPath", args.derived_data, "-resultBundlePath", str(results / "Test.xcresult"),
               "CODE_SIGNING_ALLOWED=NO"]
    command += ["-only-testing:" + item for item in args.only_testing]
    command.append("test")

    def inspect():
        try:
            if health["testsStarted"]:
                status = springboard_status(args.device)
                if not health["states"] or status != health["states"][-1]["status"]:
                    health["states"].append({"time": datetime.now().astimezone().isoformat(), "status": status})
                if abnormal_exit(status):
                    message = "SpringBoard exited abnormally: " + str(status)
                    if message not in health["errors"]:
                        health["errors"].append(message)
        except (RuntimeError, ValueError, subprocess.SubprocessError) as error:
            # Do not silently treat a failed health check as a healthy device.
            health["errors"].append(str(error))
        for path in set(REPORTS.glob("*.ips")) - known_reports:
            try:
                crash = relevant_crash(path.read_text(), args.device, started)
            except (OSError, ValueError, KeyError):
                # Reports may still be being written; inspect again next time.
                continue
            if crash:
                health["crashes"][str(path)] = crash

    try:
        with (results / "xcodebuild.log").open("w") as log, (results / "xcodebuild.log").open() as progress:
            process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
            pending = ""

            def read_progress():
                nonlocal pending
                pending += progress.read()
                lines = pending.split("\n")
                pending = lines.pop()
                for line in lines:
                    if line.startswith("Test Case "):
                        health["testsStarted"] = True
                        print(line, flush=True)

            try:
                while process.poll() is None:
                    read_progress()
                    inspect()
                    time.sleep(2)
                read_progress()
                health["xcodeExitStatus"] = process.returncode
                # The automation-disconnect crash can arrive just after XCTest
                # reports success. Check the service as well as delayed reports.
                for _ in range(5):
                    inspect()
                    time.sleep(2)
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=20)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
    finally:
        # Close only this explicitly selected test device. Preserve its data.
        try:
            if device_info(args.device)["state"] != "Shutdown":
                run("xcrun", "simctl", "shutdown", args.device)
        finally:
            (results / "health.json").write_text(json.dumps(health, ensure_ascii=False, indent=2) + "\n")
    passed = checks_passed(health)
    print("PASS: UI tests and Simulator health" if passed else "FAIL: inspect xcodebuild.log and health.json", flush=True)
    return 0 if passed else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("device", help="UDID of an iPad test Simulator; it will be restarted and left shut down")
    parser.add_argument("--derived-data", default=str(Path(tempfile.gettempdir()) / "HastellColor-ui-build"))
    parser.add_argument("--results", help="New directory for logs, health report and xcresult")
    parser.add_argument("--only-testing", action="append", default=[], help="Optional XCTest selector (repeatable)")
    args = parser.parse_args()
    try:
        return check(args)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print("UI checks failed: " + str(error), file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())
