import json
import os
import queue
import re
import time
from functools import wraps

from flask import (
    Flask,
    Response,
    flash,
    jsonify,
    redirect,
    render_template,
    request,
    send_file,
    session,
    stream_with_context,
    url_for,
)

import config
import database
import runner

app = Flask(__name__)
app.secret_key = config.SECRET_KEY

os.makedirs(config.RUNS_DIR, exist_ok=True)
database.init_db()


# ── Auth ─────────────────────────────────────────────────────────────────────

def login_required(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        if not session.get("logged_in"):
            return redirect(url_for("login"))
        return f(*args, **kwargs)
    return wrapper


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        user = request.form.get("username", "")
        pw = request.form.get("password", "")
        if database.check_password(user, pw):
            session["logged_in"] = True
            session["username"] = user
            return redirect(url_for("dashboard"))
        flash("Invalid credentials")
    return render_template("login.html")


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


# ── Settings (password change) ──────────────────────────────────────────────

@app.route("/settings")
@login_required
def settings_page():
    return render_template("settings.html")


@app.route("/api/change-password", methods=["POST"])
@login_required
def api_change_password():
    data = request.get_json(force=True)
    current_pw = data.get("current_password", "")
    new_pw = data.get("new_password", "")
    confirm_pw = data.get("confirm_password", "")

    username = session.get("username", config.ADMIN_USER)

    if not database.check_password(username, current_pw):
        return jsonify({"error": "Current password is incorrect"}), 403

    if len(new_pw) < 8:
        return jsonify({"error": "New password must be at least 8 characters"}), 400

    if new_pw != confirm_pw:
        return jsonify({"error": "New passwords do not match"}), 400

    database.change_password(username, new_pw)
    return jsonify({"ok": True})


# ── Dashboard ────────────────────────────────────────────────────────────────

@app.route("/")
@login_required
def dashboard():
    return render_template("dashboard.html", steps=config.STEP_NAMES)


# ── API: Start a run ────────────────────────────────────────────────────────

IP_RE = re.compile(
    r"^(\d{1,3}\.){3}\d{1,3}$"
    r"|^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$"
    r"|^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$"
)


@app.route("/api/runs", methods=["POST"])
@login_required
def api_create_run():
    data = request.get_json(force=True)
    target_ip = data.get("target_ip", "").strip()

    if not target_ip or not IP_RE.match(target_ip):
        return jsonify({"error": "Invalid target IP or hostname"}), 400

    if runner.has_active_run():
        return jsonify({"error": "A scan is already running. Wait for it to finish."}), 409

    timestamp = time.strftime("%Y%m%d_%H%M%S")
    safe_target = re.sub(r"[^a-zA-Z0-9._-]", "_", target_ip)
    output_dir = os.path.join(config.RUNS_DIR, f"enum_{safe_target}_{timestamp}")

    args_dict = {
        "domain": data.get("domain", "").strip(),
        "steps": data.get("steps", "").strip(),
        "timing": data.get("timing", ""),
        "skip_udp": data.get("skip_udp", False),
        "skip_bruteforce": data.get("skip_bruteforce", False),
        "dry_run": data.get("dry_run", False),
        "wordlist": data.get("wordlist", "").strip(),
    }

    run_id = database.create_run(
        target_ip=target_ip,
        domain=args_dict["domain"],
        arguments=json.dumps(args_dict),
        output_dir=output_dir,
    )

    runner.start_enumeration(run_id, target_ip, args_dict)
    return jsonify({"run_id": run_id}), 201


# ── API: List runs ──────────────────────────────────────────────────────────

@app.route("/api/runs", methods=["GET"])
@login_required
def api_list_runs():
    return jsonify(database.get_all_runs())


@app.route("/api/runs/<int:run_id>", methods=["GET"])
@login_required
def api_get_run(run_id):
    run = database.get_run(run_id)
    if not run:
        return jsonify({"error": "Not found"}), 404
    return jsonify(run)


# ── API: SSE stream ─────────────────────────────────────────────────────────

@app.route("/api/runs/<int:run_id>/stream")
@login_required
def api_stream(run_id):
    run = database.get_run(run_id)
    if not run:
        return jsonify({"error": "Not found"}), 404

    def generate():
        # Send buffered output first
        lines, step = runner.get_buffered_output(run_id)
        catchup = json.dumps({"lines": lines, "step": step})
        yield f"event: catchup\ndata: {catchup}\n\n"

        if run["status"] in ("completed", "failed"):
            yield f"event: status\ndata: {json.dumps({'status': run['status'], 'step': step})}\n\n"
            return

        # Subscribe to live output
        q = runner.subscribe(run_id)
        try:
            while True:
                try:
                    event_type, data, step = q.get(timeout=15)
                except queue.Empty:
                    yield ": heartbeat\n\n"
                    continue

                if event_type == "output":
                    payload = json.dumps({"line": data, "step": step})
                    yield f"event: output\ndata: {payload}\n\n"
                elif event_type == "status":
                    payload = json.dumps({"status": data, "step": step})
                    yield f"event: status\ndata: {payload}\n\n"
                    return
        except GeneratorExit:
            pass

    return Response(
        stream_with_context(generate()),
        mimetype="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )


# ── Past Runs page ──────────────────────────────────────────────────────────

@app.route("/runs")
@login_required
def runs_page():
    return render_template("runs.html")


# ── Report viewing ──────────────────────────────────────────────────────────

@app.route("/report/<int:run_id>")
@login_required
def view_report(run_id):
    return render_template("report.html", run_id=run_id)


@app.route("/api/runs/<int:run_id>/report")
@login_required
def api_report(run_id):
    run = database.get_run(run_id)
    if not run:
        return jsonify({"error": "Not found"}), 404

    report_path = os.path.join(run["output_dir"], "report", "report.html")
    if not os.path.isfile(report_path):
        return jsonify({"error": "Report not yet generated"}), 404

    return send_file(report_path, mimetype="text/html")


# ── Main ─────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=5000, threaded=True)
