#!/usr/bin/env python3
"""
Minimal mock GitHub OAuth2 server for Grafana SSO testing.

Mimics the GitHub OAuth2 endpoints that Grafana's GitHub auth provider calls:
  GET  /login/oauth/authorize           → auto-approves; redirects to callback with code
  POST /login/oauth/access_token        → returns a static bearer token
  GET  /api/user                        → returns mock user info (login, email, name)
  GET  /api/user/orgs                   → returns mock org membership
  GET  /health                          → liveness check

Configuration (environment variables):
  MOCK_OAUTH_PORT       Listening port           (default: 8090)
  MOCK_OAUTH_USER       GitHub login username     (default: testuser)
  MOCK_OAUTH_EMAIL      User email                (default: testuser@example.com)
  MOCK_OAUTH_NAME       Display name              (default: Test User)
  MOCK_OAUTH_ORG        Organisation name         (default: homelab)
  MOCK_OAUTH_ADMIN_USER If set and matches login, role_attribute_path returns Admin

Usage:
  python3 test/mock-oauth/server.py
  MOCK_OAUTH_PORT=8091 python3 test/mock-oauth/server.py
"""

import json
import os
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT    = int(os.environ.get("MOCK_OAUTH_PORT", "8090"))
USER    = os.environ.get("MOCK_OAUTH_USER",  "testuser")
EMAIL   = os.environ.get("MOCK_OAUTH_EMAIL", "testuser@example.com")
NAME    = os.environ.get("MOCK_OAUTH_NAME",  "Test User")
ORG     = os.environ.get("MOCK_OAUTH_ORG",   "homelab")
ADMIN   = os.environ.get("MOCK_OAUTH_ADMIN_USER", USER)

# Static token — any Bearer value we issue is accepted.
_TOKEN = "mock-github-oauth-token-for-ci-testing"

# Fake auth code — the real value doesn't matter; we accept any.
_CODE = "mock-auth-code-123"

MOCK_USER_INFO = {
    "login":      USER,
    "email":      EMAIL,
    "name":       NAME,
    "id":         1,
    "avatar_url": "",
    "html_url":   f"https://github.com/{USER}",
}

MOCK_ORGS = [{"login": ORG, "id": 1}]

MOCK_TEAMS = [{"name": "owners", "slug": "owners", "organization": {"login": ORG}}]


class MockOAuthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)

        # ── Authorization endpoint ──────────────────────────────────────────
        # Immediately redirects back with a code — no user interaction needed.
        if parsed.path == "/login/oauth/authorize":
            redirect_uri = params.get("redirect_uri", [""])[0]
            state        = params.get("state",        [""])[0]
            if not redirect_uri:
                self._error(400, "missing redirect_uri")
                return
            location = f"{redirect_uri}?code={_CODE}&state={urllib.parse.quote(state)}"
            self._redirect(location)

        # ── User info ───────────────────────────────────────────────────────
        elif parsed.path == "/api/user":
            self._json(MOCK_USER_INFO)

        # ── Org membership ──────────────────────────────────────────────────
        elif parsed.path == "/api/user/orgs":
            self._json(MOCK_ORGS)

        # ── Teams ───────────────────────────────────────────────────────────
        elif parsed.path == "/api/user/teams":
            self._json(MOCK_TEAMS)

        # ── Liveness check ──────────────────────────────────────────────────
        elif parsed.path == "/health":
            self._json({"status": "ok", "user": USER, "org": ORG})

        else:
            self._error(404, f"unknown path: {parsed.path}")

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)

        # ── Token exchange ──────────────────────────────────────────────────
        if parsed.path == "/login/oauth/access_token":
            # Read body (not validated — any code is accepted)
            length = int(self.headers.get("Content-Length", 0))
            self.rfile.read(length)

            # Grafana sends Accept: application/json for this endpoint
            self._json({
                "access_token": _TOKEN,
                "token_type":   "bearer",
                "scope":        "user:email,read:org",
            })
        else:
            self._error(404, f"unknown path: {parsed.path}")

    # ── Helpers ──────────────────────────────────────────────────────────────

    def _json(self, data: dict):
        body = json.dumps(data).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _redirect(self, location: str):
        self.send_response(302)
        self.send_header("Location", location)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _error(self, code: int, msg: str):
        body = json.dumps({"error": msg}).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        # Route to stdout with a clear prefix
        print(f"[mock-oauth] {self.address_string()} {fmt % args}", file=sys.stderr, flush=True)


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), MockOAuthHandler)
    print(f"Mock GitHub OAuth server listening on :{PORT}", flush=True)
    print(f"  User:  {USER} <{EMAIL}>", flush=True)
    print(f"  Org:   {ORG}", flush=True)
    print(f"  Token: {_TOKEN}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
