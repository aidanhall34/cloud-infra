#!/usr/bin/env python3
"""
Executes a rendered cloud-init YAML on the current host.

Must be run as root (sudo python3 scripts/run-cloud-init.py ...).

Execution order mirrors cloud-init's own module order:
  1. apt-get update  (if package_update: true)
  2. apt-get upgrade (if package_upgrade: true, skipped with --skip-upgrade)
  3. apt-get install packages
  4. write_files
  5. runcmd

Usage:
  sudo python3 scripts/run-cloud-init.py <rendered.yaml> [--skip-upgrade]
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path

import yaml


def run(cmd, *, shell=False, check=True, env=None):
    """Run a command, printing it first. Exit on failure when check=True."""
    display = cmd if isinstance(cmd, str) else " ".join(str(c) for c in cmd)
    print(f"\n==> {display}", flush=True)
    merged_env = {**os.environ, **(env or {})}
    result = subprocess.run(cmd, shell=shell, env=merged_env)
    if check and result.returncode != 0:
        print(f"ERROR: command exited {result.returncode}", file=sys.stderr)
        sys.exit(result.returncode)
    return result.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", help="Path to rendered cloud-init YAML file")
    parser.add_argument(
        "--skip-upgrade",
        action="store_true",
        help="Skip apt-get upgrade (saves time in CI)",
    )
    args = parser.parse_args()

    if os.geteuid() != 0:
        print("ERROR: must be run as root (use sudo)", file=sys.stderr)
        sys.exit(1)

    with open(args.config) as fh:
        config = yaml.safe_load(fh)

    noninteractive_env = {"DEBIAN_FRONTEND": "noninteractive"}

    # ── 1. Package update ─────────────────────────────────────────────────────
    if config.get("package_update"):
        run(["apt-get", "update", "-q"], env=noninteractive_env)

    # ── 2. Package upgrade ────────────────────────────────────────────────────
    if not args.skip_upgrade and config.get("package_upgrade"):
        run(
            ["apt-get", "upgrade", "-y", "-q", "-o", "Dpkg::Options::=--force-confold"],
            env=noninteractive_env,
        )

    # ── 3. Install packages ───────────────────────────────────────────────────
    packages = config.get("packages", [])
    if packages:
        print(f"\n==> Installing {len(packages)} packages: {' '.join(packages)}")
        run(
            ["apt-get", "install", "-y", "-q", "-o", "Dpkg::Options::=--force-confold"]
            + packages,
            env=noninteractive_env,
        )

    # ── 4. Write files ────────────────────────────────────────────────────────
    for entry in config.get("write_files", []):
        dest = Path(entry["path"])
        content = entry.get("content", "")
        permissions = entry.get("permissions", "0644")

        print(f"\n==> write_files: {dest}")
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content)
        dest.chmod(int(permissions, 8))

    # ── 5. Run commands ───────────────────────────────────────────────────────
    for cmd in config.get("runcmd", []):
        if isinstance(cmd, list):
            run(cmd)
        else:
            run(cmd, shell=True)


if __name__ == "__main__":
    main()
