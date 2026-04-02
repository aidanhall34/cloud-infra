#!/usr/bin/env python3
"""
End-to-end OAuth2 authentication flow test against a live Grafana instance.

What it does:
  1. Opens a requests.Session (acts as a browser with a cookie jar)
  2. Hits Grafana's /login/github endpoint — Grafana sets the OAuth state cookie
     and redirects to the configured auth_url (mock server in CI)
  3. Mock server auto-approves and redirects back to Grafana's callback
  4. Grafana exchanges the code, calls the mock /api/user endpoint, creates the
     session cookie, and redirects to the home page
  5. Script calls an authenticated Grafana API endpoint to verify the session

Usage:
  python3 test/mock-oauth/test-oauth-flow.py [--grafana-url URL] [--expected-user USER]

Exit codes:
  0  Authentication succeeded
  1  Authentication failed (with reason printed to stderr)
"""

import argparse
import sys
import time
import urllib3

import requests

# Suppress InsecureRequestWarning if running against http
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


def wait_for_grafana(base_url: str, timeout: int = 60) -> None:
    """Block until Grafana's health endpoint returns 200."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            r = requests.get(f"{base_url}/api/health", timeout=3)
            if r.status_code == 200:
                print(f"  Grafana health: {r.json()}", flush=True)
                return
        except requests.exceptions.ConnectionError:
            pass
        time.sleep(2)
    print(f"ERROR: Grafana did not become healthy within {timeout}s", file=sys.stderr)
    sys.exit(1)


def test_oauth_flow(grafana_url: str, expected_user: str) -> None:
    session = requests.Session()
    # Follow all redirects automatically; cookies are preserved across redirects.
    session.max_redirects = 10

    print(f"\n==> Step 1: Trigger OAuth login at {grafana_url}/login/github")
    resp = session.get(f"{grafana_url}/login/github", allow_redirects=True, timeout=15)

    print(f"  Final URL after redirects: {resp.url}")
    print(f"  HTTP status: {resp.status_code}")
    print(f"  Cookies set: {list(session.cookies.keys())}")

    # After the redirect chain completes we should be at Grafana's home (/) or /dashboard
    if resp.status_code not in (200, 302):
        print(f"ERROR: unexpected status {resp.status_code} after OAuth redirect chain", file=sys.stderr)
        sys.exit(1)

    print("\n==> Step 2: Verify session is authenticated (GET /api/org)")
    org_resp = session.get(f"{grafana_url}/api/org", timeout=10)
    if org_resp.status_code != 200:
        print(
            f"ERROR: GET /api/org returned {org_resp.status_code} — not authenticated.\n"
            f"  Response: {org_resp.text}",
            file=sys.stderr,
        )
        sys.exit(1)
    print(f"  /api/org → {org_resp.json()}")

    print("\n==> Step 3: Verify authenticated user matches expected")
    user_resp = session.get(f"{grafana_url}/api/user", timeout=10)
    if user_resp.status_code != 200:
        print(
            f"ERROR: GET /api/user returned {user_resp.status_code}\n"
            f"  Response: {user_resp.text}",
            file=sys.stderr,
        )
        sys.exit(1)
    user_data = user_resp.json()
    login = user_data.get("login") or user_data.get("name") or ""
    print(f"  Logged in as: {login!r} (expected: {expected_user!r})")

    if expected_user and login != expected_user:
        print(
            f"ERROR: logged in as {login!r}, expected {expected_user!r}",
            file=sys.stderr,
        )
        sys.exit(1)

    print("\n  OAuth flow PASSED — Grafana authentication with mock OAuth server works.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--grafana-url",    default="http://localhost:3000",
                        help="Base URL of Grafana (default: http://localhost:3000)")
    parser.add_argument("--expected-user",  default="testuser",
                        help="Expected Grafana login username (default: testuser)")
    parser.add_argument("--wait-timeout",   type=int, default=60,
                        help="Seconds to wait for Grafana to become healthy (default: 60)")
    args = parser.parse_args()

    print(f"Grafana URL:    {args.grafana_url}")
    print(f"Expected user:  {args.expected_user}")

    wait_for_grafana(args.grafana_url, args.wait_timeout)
    test_oauth_flow(args.grafana_url, args.expected_user)


if __name__ == "__main__":
    main()
