#!/usr/bin/env python3
"""
Renders one or more Terraform template files (.tpl) with the given variable values.

When multiple templates are given they are rendered independently then their
cloud-config YAML dicts are deep-merged (lists concatenated, dicts recursed,
scalars replaced by the later value) and output as a single #cloud-config
document.  This mirrors the merge behaviour of cloud-init MIME multipart so
that run-cloud-init.py can consume the result without modification.

Handles the subset of Terraform template syntax used in this project:
  ${variable_name}                    simple substitution
  ${indent(N, variable)}              indent all lines after the first by N spaces
  ${a != "" ? a : "literal"}          ternary (variable-not-empty check)
  %{ if var != "" ~} ... %{ endif ~}  conditional block
  %{ if var != "" ~} ... %{ else ~} ... %{ endif ~}

Usage:
  python3 scripts/render-template.py <template.tpl> [<template2.tpl> ...] <vars.json>

  vars.json may be a file path or an inline JSON string.
  All templates receive the same variables.
"""

import json
import re
import sys
from pathlib import Path

import yaml


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def indent_tf(n: int, value: str) -> str:
    """Terraform indent(n, s): indent all lines *after the first* by n spaces."""
    lines = value.split("\n")
    return lines[0] + "".join("\n" + " " * n + ln for ln in lines[1:])


def eval_condition(expr: str, variables: dict) -> bool:
    """Evaluate simple Terraform boolean expressions."""
    expr = expr.strip()
    # var != ""
    m = re.fullmatch(r'(\w+)\s*!=\s*""', expr)
    if m:
        return bool(str(variables.get(m.group(1), "")))
    # var == ""
    m = re.fullmatch(r'(\w+)\s*==\s*""', expr)
    if m:
        return not bool(str(variables.get(m.group(1), "")))
    # Unrecognised — treat as True so we don't silently drop content
    print(f"WARNING: unrecognised condition '{expr}', treating as True", file=sys.stderr)
    return True


def substitute_expressions(text: str, variables: dict) -> str:
    """Replace all ${...} expressions in a single line / text block."""

    # ${indent(N, varname)}
    def _indent(m):
        return indent_tf(int(m.group(1)), str(variables.get(m.group(2).strip(), "")))

    text = re.sub(r"\$\{indent\((\d+),\s*(\w+)\)\}", _indent, text)

    # ${varname != "" ? varname : "literal"}
    def _ternary(m):
        test_var, true_var, false_lit = m.group(1), m.group(2), m.group(3)
        return str(variables.get(true_var, "")) if variables.get(test_var, "") else false_lit

    text = re.sub(
        r'\$\{(\w+)\s*!=\s*""\s*\?\s*(\w+)\s*:\s*"([^"]*)"\}',
        _ternary,
        text,
    )

    # ${varname}  — only bare-word identifiers so $( ... ) bash syntax is untouched
    def _var(m):
        name = m.group(1)
        if name in variables:
            return str(variables[name])
        # Leave unknown references as-is (bash variables inside heredocs)
        return m.group(0)

    text = re.sub(r"\$\{([A-Za-z_]\w*)\}", _var, text)

    return text


# ---------------------------------------------------------------------------
# Directive patterns  (%{ ... })
# ---------------------------------------------------------------------------

# Matches:  %{ if <condition> ~}   or   %{~ if <condition> }  (leading/trailing ~)
_RE_IF     = re.compile(r"^\s*%\{[~\s]*if\s+(.+?)\s*[~\s]*\}\s*$")
_RE_ELSE   = re.compile(r"^\s*%\{[~\s]*else[~\s]*\}\s*$")
_RE_ENDIF  = re.compile(r"^\s*%\{[~\s]*endif[~\s]*\}\s*$")


# ---------------------------------------------------------------------------
# Main renderer
# ---------------------------------------------------------------------------

def render(template: str, variables: dict) -> str:
    out_lines = []
    # Stack of dicts: {'emit': bool, 'seen_else': bool}
    stack = []

    for raw_line in template.splitlines(keepends=True):
        stripped = raw_line.strip()

        m = _RE_IF.match(stripped)
        if m:
            cond = eval_condition(m.group(1), variables)
            stack.append({"emit": cond, "seen_else": False})
            continue

        if _RE_ELSE.match(stripped):
            if stack and not stack[-1]["seen_else"]:
                stack[-1]["emit"] = not stack[-1]["emit"]
                stack[-1]["seen_else"] = True
            continue

        if _RE_ENDIF.match(stripped):
            if stack:
                stack.pop()
            continue

        # Emit this line only when every enclosing block says so
        if all(s["emit"] for s in stack):
            out_lines.append(substitute_expressions(raw_line, variables))

    return "".join(out_lines)


# ---------------------------------------------------------------------------
# YAML deep-merge
# ---------------------------------------------------------------------------

def deep_merge(base: dict, overlay: dict) -> None:
    """Merge overlay into base in-place.

    Lists are concatenated (base first, overlay appended).
    Dicts are recursively merged.
    Scalars take the overlay value.
    """
    for k, v in overlay.items():
        if k in base and isinstance(base[k], list) and isinstance(v, list):
            base[k] = base[k] + v
        elif k in base and isinstance(base[k], dict) and isinstance(v, dict):
            deep_merge(base[k], v)
        else:
            base[k] = v


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) < 3:
        print(
            f"Usage: {sys.argv[0]} <template.tpl> [<template2.tpl> ...] <vars.json | json_string>",
            file=sys.stderr,
        )
        sys.exit(1)

    template_paths = sys.argv[1:-1]
    vars_arg = sys.argv[-1]

    # Accept either a JSON file path or an inline JSON string
    try:
        variables = json.loads(vars_arg)
    except (json.JSONDecodeError, ValueError):
        variables = json.loads(Path(vars_arg).read_text())

    rendered_parts = [render(Path(tpl).read_text(), variables) for tpl in template_paths]

    if len(rendered_parts) == 1:
        # Single template: output raw rendered text unchanged.
        sys.stdout.write(rendered_parts[0])
        return

    # Multiple templates: merge YAML dicts and emit a single cloud-config document.
    merged: dict = {}
    for part in rendered_parts:
        doc = yaml.safe_load(part)
        if doc:
            deep_merge(merged, doc)

    sys.stdout.write("#cloud-config\n")
    sys.stdout.write(yaml.dump(merged, default_flow_style=False, allow_unicode=True, sort_keys=False))


if __name__ == "__main__":
    main()
