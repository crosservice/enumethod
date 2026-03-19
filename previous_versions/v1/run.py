#!/usr/bin/env python3
"""
Single-command launcher for the enumethod web app.

    python3 run.py

Automatically creates a virtualenv, installs dependencies, and starts the server.
"""

import os
import subprocess
import sys

WEB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "web")
VENV_DIR = os.path.join(WEB_DIR, "venv")
REQUIREMENTS = os.path.join(WEB_DIR, "requirements.txt")

if sys.platform == "win32":
    VENV_PYTHON = os.path.join(VENV_DIR, "Scripts", "python.exe")
else:
    VENV_PYTHON = os.path.join(VENV_DIR, "bin", "python")


def pip_install(*args):
    """Run pip via the venv python — works even when no standalone pip binary exists."""
    subprocess.check_call([VENV_PYTHON, "-m", "pip"] + list(args))


def main():
    # If we're already running inside the venv, start the app
    if os.environ.get("ENUMETHOD_BOOTSTRAPPED"):
        sys.path.insert(0, WEB_DIR)
        os.chdir(WEB_DIR)
        from app import app
        app.run(debug=True, host="0.0.0.0", port=5000, threaded=True)
        return

    # Bootstrap: create venv if missing
    if not os.path.isfile(VENV_PYTHON):
        print("[+] Creating virtual environment...")
        subprocess.check_call([sys.executable, "-m", "venv", VENV_DIR])

    # Install/update dependencies
    print("[+] Installing dependencies...")
    pip_install("install", "--quiet", "--upgrade", "pip")
    pip_install("install", "--quiet", "-r", REQUIREMENTS)

    # Re-exec under the venv python
    print("[+] Starting enumethod on http://0.0.0.0:5000")
    os.environ["ENUMETHOD_BOOTSTRAPPED"] = "1"
    os.execv(VENV_PYTHON, [VENV_PYTHON, os.path.abspath(__file__)])


if __name__ == "__main__":
    main()
