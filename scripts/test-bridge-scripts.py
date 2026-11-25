"""Repeatable black-box checks for check-bridge.ps1 using a local HTTP stub."""
from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread


ROOT = Path(__file__).resolve().parents[1]
CHECK_SCRIPT = ROOT / "scripts" / "check-bridge.ps1"
SETUP_SCRIPT = ROOT / "scripts" / "setup-windows.ps1"
TOOLS_SCRIPT = ROOT / "scripts" / "install-opencode-tools.ps1"
STARTUP_SCRIPT = ROOT / "scripts" / "install-bridge-startup.ps1"
T3_SETUP_DOC = ROOT / "docs" / "t3-code-setup.md"
API_KEY = "test-key-do-not-print"
REQUIRED_MODELS = ["gemini-4-neon", "gemini-4-hydrogen"]


class StubHandler(BaseHTTPRequestHandler):
    models_status = 200
    model_ids = REQUIRED_MODELS
    received_keys: list[str | None] = []

    def log_message(self, _format: str, *_args: object) -> None:
        pass

    def do_GET(self) -> None:
        key = self.headers.get("Authorization")
        type(self).received_keys.append(key)
        if self.path == "/health":
            status, payload = 200, {"status": "ok"}
        elif self.path == "/v1/models":
            status = type(self).models_status
            payload = {"error": "unauthorized"} if status != 200 else {
                "data": [{"id": item} for item in type(self).model_ids]
            }
        else:
            status, payload = 404, {"error": "not found"}
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class CheckBridgeScriptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.powershell = shutil.which("powershell.exe") or shutil.which("powershell") or shutil.which("pwsh")
        if not cls.powershell:
            raise unittest.SkipTest("PowerShell is required to run these checks")

    def run_check(self, port: int) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [self.powershell, "-NoProfile", "-File", str(CHECK_SCRIPT), "-Port", str(port), "-ApiKey", API_KEY],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )

    def serve(self, status: int = 200, models: list[str] | None = None):
        StubHandler.models_status = status
        StubHandler.model_ids = models if models is not None else REQUIRED_MODELS
        StubHandler.received_keys = []
        server = ThreadingHTTPServer(("127.0.0.1", 0), StubHandler)
        thread = Thread(target=server.serve_forever, daemon=True)
        thread.start()
        return server, thread

    def assert_key_not_leaked(self, result: subprocess.CompletedProcess[str]) -> None:
        self.assertNotIn(API_KEY, result.stdout + result.stderr)

    def test_unreachable_bridge_fails(self) -> None:
        probe = ThreadingHTTPServer(("127.0.0.1", 0), StubHandler)
        port = probe.server_address[1]
        probe.server_close()
        result = self.run_check(port)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Bridge reachable:", result.stdout)
        self.assertIn("NO", result.stdout)
        self.assert_key_not_leaked(result)

    def test_models_unauthorized_fails(self) -> None:
        server, thread = self.serve(status=401)
        try:
            result = self.run_check(server.server_address[1])
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Authenticated models:", result.stdout)
        self.assertIn("NO", result.stdout)
        self.assertEqual(StubHandler.received_keys, [f"Bearer {API_KEY}", f"Bearer {API_KEY}"])
        self.assert_key_not_leaked(result)

    def test_missing_required_model_fails(self) -> None:
        server, thread = self.serve(models=["gemini-4-neon"])
        try:
            result = self.run_check(server.server_address[1])
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("gemini-4-hydrogen", result.stdout + result.stderr)
        self.assert_key_not_leaked(result)

    def test_required_models_succeed(self) -> None:
        server, thread = self.serve()
        try:
            result = self.run_check(server.server_address[1])
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("OK: gemini-4-neon and gemini-4-hydrogen are advertised.", result.stdout)
        self.assert_key_not_leaked(result)


class SetupBridgeScriptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.powershell = shutil.which("powershell.exe") or shutil.which("powershell") or shutil.which("pwsh")
        if not cls.powershell:
            raise unittest.SkipTest("PowerShell is required to run these checks")

    def serve(self, account_status: int = 200, reply_marker: bool = True):
        class Handler(BaseHTTPRequestHandler):
            requests: list[tuple[str, str | None, object]] = []

            def log_message(self, _format: str, *_args: object) -> None:
                pass

            def send_json(self, status: int, payload: object) -> None:
                body = json.dumps(payload).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self) -> None:
                type(self).requests.append((self.path, self.headers.get("Authorization"), None))
                if self.path == "/v1/accounts" and account_status == 200:
                    self.send_json(200, {
                        "default_authuser": "0",
                        "accounts": [
                            {"authuser": "0", "picker_models": ["gemini-4-neon"], "eligible": True},
                            {"authuser": "1", "picker_models": ["gemini-4-neon", "gemini-4-hydrogen"], "eligible": True},
                        ],
                    })
                else:
                    self.send_json(account_status if self.path == "/v1/accounts" else 404, {"detail": "unavailable"})

            def do_POST(self) -> None:
                size = int(self.headers.get("Content-Length", "0"))
                body = json.loads(self.rfile.read(size) or b"{}")
                type(self).requests.append((self.path, self.headers.get("Authorization"), body))
                messages = body.get("messages", [])
                prompt = str(messages[-1].get("content", "")) if messages else ""
                marker = prompt.rsplit(" ", 1)[-1] if reply_marker else "wrong-marker"
                self.send_json(200, {"choices": [{"message": {"content": marker}}]})

            def do_PUT(self) -> None:
                size = int(self.headers.get("Content-Length", "0"))
                body = json.loads(self.rfile.read(size) or b"{}")
                type(self).requests.append((self.path, self.headers.get("Authorization"), body))
                self.send_json(200, {"default_authuser": body.get("authuser")})

        Handler.requests = []
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = Thread(target=server.serve_forever, daemon=True)
        thread.start()
        return server, thread, Handler

    def run_setup(self, port: int, root: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                self.powershell, "-NoProfile", "-File", str(SETUP_SCRIPT),
                "-NonInteractive", "-SkipDependencyInstall", "-SkipChromeHandoff",
                "-AccountAuthuser", "1",
                "-ProjectRoot", str(root), "-ApiBase", f"http://127.0.0.1:{port}", "-ApiKey", API_KEY,
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )

    def test_guided_setup_selects_account_and_verifies_first_reply(self) -> None:
        server, thread, handler = self.serve()
        try:
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / ".env.example").write_text("GEMINI_API_KEY=placeholder\n", encoding="utf-8")
                result = self.run_setup(server.server_address[1], root)
                env = (root / ".env").read_text(encoding="utf-8")
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("First live Gemini reply verified through Chrome.", result.stdout)
        self.assertIn("GEMINI_BACKEND=chrome", env)
        self.assertTrue(any(path == "/v1/accounts" and key == f"Bearer {API_KEY}" for path, key, _ in handler.requests))
        self.assertTrue(any(path == "/v1/accounts/default" and body == {"authuser": "1"} for path, _, body in handler.requests))
        self.assertTrue(any(path == "/v1/chat/completions" and key == f"Bearer {API_KEY}" for path, key, _ in handler.requests))
        self.assertNotIn(API_KEY, result.stdout + result.stderr)

    def test_guided_setup_rejects_missing_account_api(self) -> None:
        server, thread, _handler = self.serve(account_status=404)
        try:
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / ".env.example").write_text("GEMINI_API_KEY=placeholder\n", encoding="utf-8")
                result = self.run_setup(server.server_address[1], root)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("/v1/accounts", result.stdout + result.stderr)
        self.assertNotIn(API_KEY, result.stdout + result.stderr)


class RegularT3MigrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.powershell = shutil.which("powershell.exe") or shutil.which("powershell") or shutil.which("pwsh")
        if not cls.powershell:
            raise unittest.SkipTest("PowerShell is required to run these checks")

    def test_scripts_and_docs_avoid_deprecated_fork_paths(self) -> None:
        setup_text = SETUP_SCRIPT.read_text(encoding="utf-8")
        self.assertIn("gemini-bridge\\runtime\\opencode", setup_text)
        self.assertNotIn("T3 Code (Gemini)", setup_text)
        startup_text = STARTUP_SCRIPT.read_text(encoding="utf-8")
        self.assertIn("$TaskName = 'Gemini Bridge'", startup_text)
        self.assertIn("Unregister-ScheduledTask", startup_text)
        tools_text = TOOLS_SCRIPT.read_text(encoding="utf-8")
        self.assertIn(".t3\\gemini-bridge\\config", tools_text)
        self.assertNotIn(".t3-gemini", tools_text)
        t3_doc_text = T3_SETUP_DOC.read_text(encoding="utf-8")
        self.assertIn("%LOCALAPPDATA%\\gemini-bridge\\runtime\\opencode", t3_doc_text)
        self.assertIn("deprecated", t3_doc_text.lower())

    def test_install_opencode_tools_writes_to_custom_root(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                [self.powershell, "-NoProfile", "-File", str(TOOLS_SCRIPT), "-ConfigRoot", directory],
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=15,
                check=False,
            )
            installed = Path(directory) / "opencode" / "tools" / "gemini_app.ts"
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(installed.is_file())
            content = installed.read_text(encoding="utf-8")
            self.assertIn("OPENCODE_CONFIG", content)
            self.assertIn("expandEnvPlaceholders", content)


if __name__ == "__main__":
    unittest.main(verbosity=2)
