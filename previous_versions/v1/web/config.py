import os
import secrets

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(BASE_DIR)

SECRET_KEY = secrets.token_hex(32)
ADMIN_USER = "admin"
DEFAULT_PASS = "TestifyThusly99@"

SCRIPT_PATH = os.path.join(REPO_DIR, "enumerate.sh")
DB_PATH = os.path.join(BASE_DIR, "enumethod.db")
RUNS_DIR = os.path.join(REPO_DIR, "runs")

STEP_NAMES = {
    1: "Passive Intelligence Gathering",
    2: "Port Scanning",
    3: "Web Service Enumeration",
    4: "SMB / NetBIOS",
    5: "SNMP Enumeration",
    6: "Mail Services",
    7: "Database Services",
    8: "Authentication Testing",
    9: "Vulnerability Scanning",
    10: "Traffic & Protocol Analysis",
    11: "Consolidation & Reporting",
}
