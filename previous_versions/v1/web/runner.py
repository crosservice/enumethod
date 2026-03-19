import datetime
import json
import os
import re
import signal
import subprocess
import threading
import queue

import config
import database

# Global state for active runs
active_runs = {}
_lock = threading.Lock()

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
STEP_RE = re.compile(r"Step\s+(\d+)/11:")
# Matches lines like "[*] Resolving subdomains: 500/27000" or "[*] WHOIS lookup on domain"
SUBSTEP_RE = re.compile(r"\[\*\]\s+(.*)")
DONE_RE = re.compile(r"\[\+\]\s+(.*)")
WARN_RE = re.compile(r"\[!\]\s+(.*)")
SKIP_RE = re.compile(r"\[SKIP\]\s+(.*)")
# Matches progress counters like "500/27000" anywhere in a line
PROGRESS_RE = re.compile(r"(\d+)/(\d+)")


def start_enumeration(run_id, target_ip, args_dict):
    """Launch enumerate.sh as a subprocess and track its output."""
    output_dir = database.get_run(run_id)["output_dir"]
    os.makedirs(output_dir, exist_ok=True)

    cmd = ["sudo", config.SCRIPT_PATH, target_ip, "-o", output_dir]

    if args_dict.get("domain"):
        cmd += ["-d", args_dict["domain"]]
    if args_dict.get("steps"):
        cmd += ["-s", args_dict["steps"]]
    if args_dict.get("timing"):
        cmd += ["-t", str(args_dict["timing"])]
    if args_dict.get("skip_udp"):
        cmd += ["--skip-udp"]
    if args_dict.get("skip_bruteforce"):
        cmd += ["--skip-bruteforce"]
    if args_dict.get("dry_run"):
        cmd += ["--dry-run"]
    if args_dict.get("wordlist"):
        cmd += ["-w", args_dict["wordlist"]]

    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=1,
        universal_newlines=True,
        cwd=config.REPO_DIR,
        preexec_fn=os.setsid,
    )

    database.update_run(run_id, pid=proc.pid)

    run_state = {
        "process": proc,
        "output_lines": [],
        "subscribers": [],
        "current_step": 0,
        "detail": "",
        "progress": None,  # (current, total) or None
    }

    with _lock:
        active_runs[run_id] = run_state

    thread = threading.Thread(target=_read_output, args=(run_id,), daemon=True)
    thread.start()


def _read_output(run_id):
    """Read subprocess output line by line, detect steps, notify subscribers."""
    with _lock:
        state = active_runs.get(run_id)
    if not state:
        return

    proc = state["process"]

    for line in proc.stdout:
        clean = ANSI_RE.sub("", line.rstrip("\n"))

        # Detect step transitions
        step_match = STEP_RE.search(clean)
        if step_match:
            step_num = int(step_match.group(1))
            state["current_step"] = step_num
            state["detail"] = ""
            state["progress"] = None
            database.update_run(run_id, current_step=step_num)

        # Parse sub-step detail
        substep_match = SUBSTEP_RE.search(clean)
        if substep_match:
            state["detail"] = substep_match.group(1)
            # Check for progress counter in the detail
            prog_match = PROGRESS_RE.search(state["detail"])
            if prog_match:
                state["progress"] = (int(prog_match.group(1)), int(prog_match.group(2)))
            else:
                state["progress"] = None

        done_match = DONE_RE.search(clean)
        if done_match:
            state["detail"] = done_match.group(1)
            state["progress"] = None

        state["output_lines"].append(clean)

        # Build event payload
        payload = {
            "step": state["current_step"],
            "detail": state["detail"],
            "progress": state["progress"],
        }

        # Notify all SSE subscribers
        dead = []
        for i, q in enumerate(state["subscribers"]):
            try:
                q.put_nowait(("output", clean, payload))
            except queue.Full:
                dead.append(i)
        for i in reversed(dead):
            state["subscribers"].pop(i)

    proc.wait()
    exit_code = proc.returncode

    # Signal-killed processes (SIGTERM=15, SIGKILL=9) have negative return codes
    if exit_code < 0 or state.get("cancelled"):
        status = "cancelled"
    elif exit_code == 0:
        status = "completed"
    else:
        status = "failed"

    now = datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
    database.update_run(run_id, status=status, finished_at=now)

    # Notify subscribers of completion
    payload = {"step": state["current_step"], "detail": "", "progress": None}
    for q in state["subscribers"]:
        try:
            q.put_nowait(("status", status, payload))
        except queue.Full:
            pass


def cancel_run(run_id):
    """Cancel a running enumeration by killing the process group."""
    with _lock:
        state = active_runs.get(run_id)
    if not state:
        return False

    proc = state["process"]
    if proc.poll() is not None:
        return False  # Already finished

    state["cancelled"] = True
    try:
        # Kill the entire process group (sudo + enumerate.sh + child tools)
        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        # Fallback: try killing just the process
        try:
            proc.terminate()
        except (ProcessLookupError, PermissionError):
            pass

    return True


def subscribe(run_id):
    """Return a queue that receives output events for this run."""
    q = queue.Queue(maxsize=1000)
    with _lock:
        state = active_runs.get(run_id)
    if state:
        state["subscribers"].append(q)
    return q


def get_buffered_output(run_id):
    """Return all output lines buffered so far, plus current detail/progress."""
    with _lock:
        state = active_runs.get(run_id)
    if state:
        return (
            list(state["output_lines"]),
            state["current_step"],
            state["detail"],
            state["progress"],
        )
    return [], 0, "", None


def is_running(run_id):
    with _lock:
        state = active_runs.get(run_id)
    if state and state["process"].poll() is None:
        return True
    return False


def has_active_run():
    """Check if any run is currently active."""
    with _lock:
        for rid, state in active_runs.items():
            if state["process"].poll() is None:
                return True
    return False
