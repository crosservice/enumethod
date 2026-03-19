import sqlite3

import bcrypt

import config


def get_db():
    conn = sqlite3.connect(config.DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


def init_db():
    conn = get_db()
    conn.execute("""
        CREATE TABLE IF NOT EXISTS runs (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            target_ip   TEXT NOT NULL,
            domain      TEXT DEFAULT '',
            arguments   TEXT DEFAULT '',
            status      TEXT DEFAULT 'pending',
            current_step INTEGER DEFAULT 0,
            output_dir  TEXT DEFAULT '',
            started_at  TEXT,
            finished_at TEXT,
            pid         INTEGER DEFAULT 0
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            username      TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL
        )
    """)
    conn.commit()
    # Seed admin user if missing
    row = conn.execute(
        "SELECT id FROM users WHERE username = ?", (config.ADMIN_USER,)
    ).fetchone()
    if not row:
        pw_hash = bcrypt.hashpw(
            config.DEFAULT_PASS.encode(), bcrypt.gensalt()
        ).decode()
        conn.execute(
            "INSERT INTO users (username, password_hash) VALUES (?, ?)",
            (config.ADMIN_USER, pw_hash),
        )
        conn.commit()
    # Mark stale running rows as failed (from prior crash)
    conn.execute("UPDATE runs SET status = 'failed' WHERE status = 'running'")
    conn.commit()
    conn.close()


def check_password(username, password):
    conn = get_db()
    row = conn.execute(
        "SELECT password_hash FROM users WHERE username = ?", (username,)
    ).fetchone()
    conn.close()
    if not row:
        return False
    return bcrypt.checkpw(password.encode(), row["password_hash"].encode())


def change_password(username, new_password):
    pw_hash = bcrypt.hashpw(new_password.encode(), bcrypt.gensalt()).decode()
    conn = get_db()
    conn.execute(
        "UPDATE users SET password_hash = ? WHERE username = ?",
        (pw_hash, username),
    )
    conn.commit()
    conn.close()


def create_run(target_ip, domain, arguments, output_dir):
    conn = get_db()
    cur = conn.execute(
        "INSERT INTO runs (target_ip, domain, arguments, output_dir, status, started_at) "
        "VALUES (?, ?, ?, ?, 'running', datetime('now'))",
        (target_ip, domain, arguments, output_dir),
    )
    run_id = cur.lastrowid
    conn.commit()
    conn.close()
    return run_id


def update_run(run_id, **kwargs):
    conn = get_db()
    sets = ", ".join(f"{k} = ?" for k in kwargs)
    vals = list(kwargs.values()) + [run_id]
    conn.execute(f"UPDATE runs SET {sets} WHERE id = ?", vals)
    conn.commit()
    conn.close()


def get_run(run_id):
    conn = get_db()
    row = conn.execute("SELECT * FROM runs WHERE id = ?", (run_id,)).fetchone()
    conn.close()
    return dict(row) if row else None


def get_all_runs():
    conn = get_db()
    rows = conn.execute("SELECT * FROM runs ORDER BY started_at DESC").fetchall()
    conn.close()
    return [dict(r) for r in rows]
