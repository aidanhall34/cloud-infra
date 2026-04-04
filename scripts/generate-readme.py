#!/usr/bin/env python3
"""Generate README.md from README.md.tpl and Makefile target comments.

Usage:
    python3 scripts/generate-readme.py [--check]

Options:
    --check   Exit with code 1 if README.md would change (useful in CI).
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).parent.parent
MAKEFILE = ROOT / "Makefile"
TEMPLATE = ROOT / "README.md.tpl"
OUTPUT = ROOT / "README.md"
PLACEHOLDER = "<!-- MAKE_TARGETS -->"


def parse_makefile(path: Path) -> list[dict]:
    """Return a list of sections parsed from the Makefile.

    Each section is:
        {'name': str, 'targets': [{'name': str, 'desc': str, 'line': int}]}

    Section headers are lines that begin with '## ' (double-hash space).
    Targets are lines matching 'target: ... ## description'.
    Targets with no preceding section header are skipped.
    """
    sections: list[dict] = []
    current_section: dict | None = None
    in_header = True

    for lineno, line in enumerate(path.read_text().splitlines(), start=1):
        # Skip the leading comment block (lines starting with # or blank)
        if in_header:
            if line.startswith("#") or line.strip() == "":
                continue
            in_header = False

        # Section header: ## Section Name
        if re.match(r"^## ", line):
            current_section = {"name": line[3:].strip(), "targets": []}
            sections.append(current_section)
            continue

        # Target with inline description: target-name: [deps] ## description
        m = re.match(r"^([a-zA-Z_-]+):.*## (.+)$", line)
        if m and current_section is not None:
            current_section["targets"].append(
                {"name": m.group(1), "desc": m.group(2).strip(), "line": lineno}
            )

    return sections


def generate_targets_section(sections: list[dict]) -> str:
    lines = ["## Available Make Targets", ""]
    for section in sections:
        targets = section["targets"]
        if not targets:
            continue
        lines.append(f"### {section['name']}")
        lines.append("")
        lines.append("| Target | Description | Source |")
        lines.append("|---|---|---|")
        for t in targets:
            link = f"[Makefile:{t['line']}](Makefile#L{t['line']})"
            lines.append(f"| `make {t['name']}` | {t['desc']} | {link} |")
        lines.append("")
    return "\n".join(lines)


def main() -> None:
    check_only = "--check" in sys.argv

    if not TEMPLATE.exists():
        print(f"error: template not found: {TEMPLATE}", file=sys.stderr)
        sys.exit(1)

    sections = parse_makefile(MAKEFILE)
    targets_md = generate_targets_section(sections)

    template = TEMPLATE.read_text()
    if PLACEHOLDER not in template:
        print(f"error: placeholder '{PLACEHOLDER}' not found in {TEMPLATE}", file=sys.stderr)
        sys.exit(1)

    result = template.replace(PLACEHOLDER, targets_md)

    if check_only:
        current = OUTPUT.read_text() if OUTPUT.exists() else ""
        if current != result:
            print(f"error: {OUTPUT} is out of date — run 'make readme' to regenerate", file=sys.stderr)
            sys.exit(1)
        print(f"{OUTPUT} is up to date")
        return

    OUTPUT.write_text(result)
    print(f"wrote {OUTPUT}")


if __name__ == "__main__":
    main()
