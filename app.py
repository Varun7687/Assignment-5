"""Assignment 4 inventory routes adapted for Assignment 5 Secrets Manager/TLS.
Not a byte-for-byte copy: formatting repaired from indexed source; see SOURCE-NOTES.md.
"""
import hashlib
import json
import os
from datetime import datetime
from functools import lru_cache

import boto3
import pymysql
from flask import Flask, flash, redirect, render_template, request, url_for


@lru_cache(maxsize=1)
def credentials():
    client = boto3.client("secretsmanager", region_name=os.environ["AWS_DEFAULT_REGION"])
    return json.loads(client.get_secret_value(SecretId=os.environ["DB_SECRET_ARN"])["SecretString"])


app = Flask(__name__)
# Stable across ASG instances; no public hardcoded Flask signing key.
# Secret retrieval at startup is retried through systemd if IAM is not ready.
app.config["SECRET_KEY"] = os.environ.get("APP_SECRET_KEY") or hashlib.sha256(
    ("assignment-5-session:" + credentials()["password"]).encode()
).digest()


def db_config():
    secret = credentials()
    return {
        "host": secret["host"], "port": int(secret.get("port", 3306)),
        "user": secret["username"], "password": secret["password"],
        "database": secret.get("database", "inventory"),
        "connect_timeout": 5, "read_timeout": 10, "write_timeout": 10,
        "cursorclass": pymysql.cursors.DictCursor, "autocommit": True,
        "ssl_ca": os.environ.get("DB_SSL_CA", "/opt/bluefin/global-bundle.pem"),
        "ssl_verify_cert": True,
        # Private DNS CNAME differs from the RDS certificate hostname.
        "ssl_verify_identity": False,
    }


def get_connection():
    return pymysql.connect(**db_config())


@app.get("/health")
def health():
    try:
        with get_connection() as connection, connection.cursor() as cursor:
            cursor.execute("SELECT id FROM items LIMIT 1")
            cursor.fetchone()
        return {"status": "ok"}, 200
    except Exception:
        return {"status": "unavailable"}, 503


@app.get("/")
def index():
    try:
        with get_connection() as connection, connection.cursor() as cursor:
            cursor.execute("""SELECT id, item_name, sku, quantity,
                warehouse_location, last_updated FROM items ORDER BY id LIMIT 200""")
            items = cursor.fetchall()
        return render_template("index.html", items=items)
    except Exception:
        return "Inventory is not ready. Check database bootstrap and service logs.\n", 503


@app.post("/items")
def add_item():
    item_name = request.form.get("item_name", "").strip()
    sku = request.form.get("sku", "").strip()
    warehouse_location = request.form.get("warehouse_location", "").strip()
    errors = []
    if not item_name or len(item_name) > 160:
        errors.append("Item name is required (maximum 160 characters).")
    if not sku or len(sku) > 64:
        errors.append("SKU is required (maximum 64 characters).")
    if not warehouse_location or len(warehouse_location) > 120:
        errors.append("Warehouse location is required (maximum 120 characters).")
    try:
        quantity = int(request.form.get("quantity", ""))
        if not 0 <= quantity <= 2147483647:
            raise ValueError
    except ValueError:
        errors.append("Quantity must be a non-negative 32-bit whole number.")
        quantity = 0
    if errors:
        for error in errors:
            flash(error, "error")
        return redirect(url_for("index"))
    try:
        with get_connection() as connection, connection.cursor() as cursor:
            cursor.execute("""INSERT INTO items
                (item_name, sku, quantity, warehouse_location) VALUES (%s, %s, %s, %s)""",
                (item_name, sku, quantity, warehouse_location))
        flash(f"Added {item_name} ({sku}).", "success")
    except pymysql.err.IntegrityError:
        flash("That SKU already exists. Use a unique SKU.", "error")
    except Exception:
        app.logger.error("Inventory insert failed")
        flash("The item could not be added. Check the application log.", "error")
    return redirect(url_for("index"))


@app.template_filter("display_time")
def display_time(value):
    return value.strftime("%Y-%m-%d %H:%M:%S") if isinstance(value, datetime) else value


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
