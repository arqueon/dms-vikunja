#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "scripts" / "vikunja_api.py"


class MockVikunjaHandler(BaseHTTPRequestHandler):
    server_version_text = "v2.3.0"
    calls: list[tuple[str, str, dict]] = []

    def log_message(self, *_args):
        return

    def _json(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _empty(self, status=204):
        self.send_response(status)
        self.end_headers()

    def _body(self):
        length = int(self.headers.get("Content-Length", "0"))
        return json.loads(self.rfile.read(length) or b"{}")

    def _list(self, items):
        path = urlparse(self.path)
        query = parse_qs(path.query)
        if path.path.startswith("/api/v2/"):
            return {"items": items, "total": len(items), "page": 1,
                    "per_page": 1000, "total_pages": 1}
        return items

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/api/v1/info":
            self._json(200, {"version": self.server_version_text})
        elif path.endswith("/user"):
            self._json(200, {"id": 1, "username": "tester"})
        elif path.endswith("/projects"):
            self._json(200, self._list([
                {"id": 1, "title": "Parent", "parent_project_id": 0},
                {"id": 2, "title": "Child", "parent_project_id": 1},
            ]))
        elif path.endswith("/labels"):
            self._json(200, self._list([{"id": 9, "title": "urgent"}]))
        elif path.endswith("/tasks"):
            self._json(200, self._list([
                {"id": 4, "project_id": 2, "title": "Task", "done": False,
                 "labels": [{"id": 9, "title": "urgent"}]}
            ]))
        else:
            self._json(404, {"message": "not found"})

    def do_POST(self):
        path = urlparse(self.path).path
        self._write_request(201 if path.endswith(("/tasks", "/attachments")) else 200)

    def do_PUT(self):
        self._write_request(201 if self.path.endswith("/tasks") else 200)

    def do_PATCH(self):
        self._write_request(200)

    def do_DELETE(self):
        self.calls.append(("DELETE", urlparse(self.path).path, {}))
        if self.path.startswith("/api/v2/"):
            self._empty()
        else:
            self._json(200, {"message": "deleted"})

    def _write_request(self, status):
        path = urlparse(self.path).path
        if self.headers.get("Content-Type", "").startswith("multipart/form-data"):
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length)
            self.calls.append((self.command, path, {"raw": raw}))
            self._json(status, {
                "success": [{
                    "id": 5,
                    "task_id": 4,
                    "file": {"name": "notes.txt", "mime": "text/plain", "size": 5},
                }],
                "errors": [],
            })
            return
        body = self._body()
        self.calls.append((self.command, path, body))
        if path.endswith("/labels/bulk"):
            self._json(200, body)
        else:
            payload = {"id": 44, "project_id": 2, "title": body.get("title", "Task")}
            payload.update(body)
            self._json(status, payload)


class BridgeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.httpd = ThreadingHTTPServer(("127.0.0.1", 0), MockVikunjaHandler)
        cls.thread = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.thread.start()
        cls.base_url = f"http://127.0.0.1:{cls.httpd.server_address[1]}"

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()

    def setUp(self):
        MockVikunjaHandler.calls = []
        MockVikunjaHandler.server_version_text = "v2.3.0"

    def run_bridge(self, *args):
        env = dict(os.environ, DMS_VIKUNJA_TEST_TOKEN="tk_test")
        result = subprocess.run(
            [sys.executable, str(BRIDGE), "--base-url", self.base_url, *args],
            text=True, capture_output=True, env=env, timeout=10,
        )
        payload = json.loads(result.stdout)
        self.assertEqual(result.returncode, 0, payload)
        return payload

    def test_v1_sync_uses_flat_lists(self):
        payload = self.run_bridge("sync")
        self.assertEqual(payload["api_version"], "v1")
        self.assertEqual(payload["projects"][1]["title"], "Child")
        self.assertEqual(payload["tasks"][0]["labels"][0]["id"], 9)

    def test_v2_sync_uses_envelopes(self):
        MockVikunjaHandler.server_version_text = "v2.4.0"
        payload = self.run_bridge("sync", "--include-done")
        self.assertEqual(payload["api_version"], "v2")
        self.assertEqual(len(payload["tasks"]), 1)

    def test_create_and_replace_labels_v1(self):
        payload = self.run_bridge("create-task", "2", "New task", "", "3", "9")
        self.assertEqual(payload["task"]["title"], "New task")
        methods = [(method, path) for method, path, _ in MockVikunjaHandler.calls]
        self.assertIn(("PUT", "/api/v1/projects/2/tasks"), methods)
        self.assertIn(("POST", "/api/v1/tasks/44/labels/bulk"), methods)

    def test_v2_save_uses_patch(self):
        MockVikunjaHandler.server_version_text = "v2.4.0"
        self.run_bridge(
            "save-task", "4", '{"done":true,"percent_done":1}', "9"
        )
        methods = [(method, path) for method, path, _ in MockVikunjaHandler.calls]
        self.assertIn(("PATCH", "/api/v2/tasks/4"), methods)
        self.assertIn(("PUT", "/api/v2/tasks/4/labels/bulk"), methods)
        task_patch = next(
            body for method, path, body in MockVikunjaHandler.calls
            if method == "PATCH" and path == "/api/v2/tasks/4"
        )
        self.assertEqual(task_patch["percent_done"], 1)

    def test_rejects_unknown_update_fields(self):
        env = dict(os.environ, DMS_VIKUNJA_TEST_TOKEN="tk_test")
        result = subprocess.run(
            [sys.executable, str(BRIDGE), "--base-url", self.base_url,
             "save-task", "4", '{"id":99}'],
            text=True, capture_output=True, env=env, timeout=10,
        )
        payload = json.loads(result.stdout)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unsupported task fields", payload["error"])

    def test_v2_uploads_multiple_part_attachment(self):
        MockVikunjaHandler.server_version_text = "v2.4.0"
        with tempfile.TemporaryDirectory() as directory:
            selected = Path(directory) / "notes.txt"
            selected.write_text("hello", encoding="utf-8")
            payload = self.run_bridge(
                "upload-attachments", "4", json.dumps([selected.as_uri()])
            )
        self.assertEqual(payload["uploaded"][0]["file"]["name"], "notes.txt")
        upload = next(
            body for method, path, body in MockVikunjaHandler.calls
            if method == "POST" and path == "/api/v2/tasks/4/attachments"
        )
        self.assertIn(b'name="files"', upload["raw"])
        self.assertIn(b'filename="notes.txt"', upload["raw"])


if __name__ == "__main__":
    unittest.main()
