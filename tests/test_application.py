"""Mocked application contract tests; no real Flask, AWS, or MySQL runtime."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import MagicMock, Mock, patch

ROOT = Path(__file__).resolve().parents[1]


class StubFlask:
    def __init__(self, name):
        self.config = {}
        self.logger = Mock()

    def get(self, path):
        return lambda function: function

    post = get
    template_filter = get


class IntegrityError(Exception):
    pass


class ApplicationContracts(unittest.TestCase):
    def setUp(self):
        self.secret = {"host": "db.prod.bluefin.internal", "port": 3306,
                       "username": "bluefinapp", "password": "offline-test-only",
                       "database": "inventory"}
        self.client = Mock()
        self.client.get_secret_value.return_value = {"SecretString": json.dumps(self.secret)}
        boto = types.ModuleType("boto3")
        boto.client = Mock(return_value=self.client)
        pymysql = types.ModuleType("pymysql")
        pymysql.cursors = types.SimpleNamespace(DictCursor=object)
        pymysql.err = types.SimpleNamespace(IntegrityError=IntegrityError)
        pymysql.connect = Mock()
        self.flask = types.ModuleType("flask")
        self.flask.Flask = StubFlask
        self.flask.flash = Mock()
        self.flask.redirect = lambda url: ("redirect", url)
        self.flask.url_for = lambda endpoint: "/"
        self.flask.render_template = Mock(return_value="rendered-index")
        self.flask.request = types.SimpleNamespace(form={})
        with patch.dict(sys.modules, {"boto3": boto, "pymysql": pymysql, "flask": self.flask}), \
             patch.dict(os.environ, {"AWS_DEFAULT_REGION": "us-east-1",
                                     "DB_SECRET_ARN": "offline-test-secret",
                                     "APP_SECRET_KEY": "offline-session-test-only"}):
            spec = importlib.util.spec_from_file_location("assignment5_app", ROOT / "app.py")
            self.app = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(self.app)
        self.env = patch.dict(os.environ, {"AWS_DEFAULT_REGION": "us-east-1", "DB_SECRET_ARN": "offline-test-secret"})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.conn = MagicMock()
        self.conn.__enter__.return_value = self.conn
        self.cursor = MagicMock()
        self.cursor.__enter__.return_value = self.cursor
        self.conn.cursor.return_value = self.cursor
        self.app.get_connection = Mock(return_value=self.conn)

    def test_secret_cached(self):
        self.assertEqual(self.app.credentials(), self.secret)
        self.app.credentials()
        self.client.get_secret_value.assert_called_once_with(SecretId="offline-test-secret")

    def test_tls_and_credentials_contract(self):
        config = self.app.db_config()
        self.assertEqual(config["user"], "bluefinapp")
        self.assertEqual(config["host"], "db.prod.bluefin.internal")
        self.assertTrue(config["ssl_verify_cert"])
        self.assertFalse(config["ssl_verify_identity"])
        self.assertTrue(config["autocommit"])

    def test_health_ready(self):
        self.assertEqual(self.app.health(), ({"status": "ok"}, 200))
        self.cursor.execute.assert_called_once_with("SELECT id FROM items LIMIT 1")

    def test_health_unavailable(self):
        self.app.get_connection.side_effect = RuntimeError("offline")
        self.assertEqual(self.app.health()[1], 503)

    def test_index_uses_original_template_and_items(self):
        self.cursor.fetchall.return_value = [{"id": 1}]
        self.assertEqual(self.app.index(), "rendered-index")
        self.flask.render_template.assert_called_once_with("index.html", items=[{"id": 1}])
        self.assertIn("FROM items", self.cursor.execute.call_args.args[0])

    def test_index_database_failure(self):
        self.app.get_connection.side_effect = RuntimeError("offline")
        self.assertEqual(self.app.index()[1], 503)

    def valid_form(self):
        self.flask.request.form = {"item_name": "Test item", "sku": "TEST-1", "quantity": "5", "warehouse_location": "Rack 1"}

    def test_insert_is_parameterized(self):
        self.valid_form()
        self.assertEqual(self.app.add_item(), ("redirect", "/"))
        sql, values = self.cursor.execute.call_args.args
        self.assertIn("INSERT INTO items", sql)
        self.assertEqual(sql.count("%s"), 4)
        self.assertEqual(values, ("Test item", "TEST-1", 5, "Rack 1"))

    def test_invalid_quantity_never_connects(self):
        self.valid_form()
        self.flask.request.form["quantity"] = "-1"
        self.app.add_item()
        self.app.get_connection.assert_not_called()
        self.assertEqual(self.flask.flash.call_args.args[1], "error")

    def test_oversized_name_never_connects(self):
        self.valid_form()
        self.flask.request.form["item_name"] = "x" * 161
        self.app.add_item()
        self.app.get_connection.assert_not_called()

    def test_duplicate_sku_message(self):
        self.valid_form()
        self.cursor.execute.side_effect = IntegrityError()
        self.app.add_item()
        self.assertIn("SKU already exists", self.flask.flash.call_args.args[0])

    def test_template_and_schema_contract(self):
        html = (ROOT / "templates/index.html").read_text()
        schema = (ROOT / "SQL/schema.sql").read_text()
        for name in ("item_name", "sku", "quantity", "warehouse_location"):
            self.assertIn(f'name="{name}"', html)
            self.assertIn(name, schema)
        self.assertIn("CREATE TABLE IF NOT EXISTS items", schema)
        self.assertNotIn("Footer navigation", html)

    def test_public_inputs_are_placeholders(self):
        text = (ROOT / "terraform/terraform.tfvars.example").read_text()
        self.assertIn('aws_region          = "us-east-1"', text)
        self.assertIn('expected_account_id = "REPLACE_', text)
        self.assertFalse((ROOT / "terraform/terraform.tfvars").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
