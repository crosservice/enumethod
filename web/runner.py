import json
import os
import re
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
    )

    database.update_run(run_id, pid=proc.pid)

    run_state = {
        "process": proc,
        "output_lines": [],
        "subscribers": [],
        "current_step": 0,
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
        match = STEP_RE.search(clean)
        if match:
            step_num = int(match.group(1))
            state["current_step"] = step_num
            database.update_run(run_id, current_step=step_num)

        state["output_lines"].append(clean)

        # Notify all SSE subscribers
        dead = []
        for i, q in enumerate(state["subscribers"]):
            try:
                q.put_nowait(("output", clean, state["current_step"]))
            except queue.Full:
                dead.append(i)
        for i in reversed(dead):
            state["subscribers"].pop(i)

    proc.wait()
    exit_code = proc.returncode
    status = "completed" if exit_code == 0 else "failed"

    import datetime
    now = datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
    database.update_run(run_id, status=status, finished_at=now)

    # Notify subscribers of completion
    for q in state["subscribers"]:
        try:
            q.put_nowait(("status", status, state["current_step"]))
        except queue.Full:
            pass


def subscribe(run_id):
    """Return a queue that receives output events for this run."""
    q = queue.Queue(maxsize=1000)
    with _lock:
        state = active_runs.get(run_id)
    if state:
        state["subscribers"].append(q)
    return q


def get_buffered_output(run_id):
    """Return all output lines buffered so far."""
    with _lock:
        state = active_runs.get(run_id)
    if state:
        return list(state["output_lines"]), state["current_step"]
    return [], 0


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
