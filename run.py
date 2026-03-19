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
    VENV_PIP = os.path.join(VENV_DIR, "Scripts", "pip.exe")
else:
    VENV_PYTHON = os.path.join(VENV_DIR, "bin", "python")
    VENV_PIP = os.path.join(VENV_DIR, "bin", "pip")


def main():
    # If we're already running inside the venv, start the app
    if sys.executable == VENV_PYTHON or os.environ.get("ENUMETHOD_BOOTSTRAPPED"):
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
    subprocess.check_call(
        [VENV_PIP, "install", "--quiet", "--upgrade", "pip"],
        stdout=subprocess.DEVNULL,
    )
    subprocess.check_call(
        [VENV_PIP, "install", "--quiet", "-r", REQUIREMENTS],
    )

    # Re-exec under the venv python
    print("[+] Starting enumethod on http://0.0.0.0:5000")
    os.environ["ENUMETHOD_BOOTSTRAPPED"] = "1"
    os.execv(VENV_PYTHON, [VENV_PYTHON, __file__])


if __name__ == "__main__":
    main()
