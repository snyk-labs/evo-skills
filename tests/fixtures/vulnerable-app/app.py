# Intentionally vulnerable test fixture for the snyk-evo-code-scan skill. Do not deploy.
import os
import sqlite3
import subprocess

from flask import Flask, request, send_file

app = Flask(__name__)
DB_PATH = os.environ.get("DB_PATH", "users.db")


@app.route("/user")
def get_user():
    username = request.args.get("name", "")
    conn = sqlite3.connect(DB_PATH)
    query = "SELECT id, email FROM users WHERE name = '" + username + "'"
    rows = conn.execute(query).fetchall()
    return {"users": rows}


@app.route("/ping")
def ping():
    host = request.args.get("host", "127.0.0.1")
    output = subprocess.check_output("ping -c 1 " + host, shell=True)
    return output


@app.route("/download")
def download():
    filename = request.args.get("file", "")
    return send_file(os.path.join("/srv/files", filename))


if __name__ == "__main__":
    app.run(host="0.0.0.0", debug=True)
