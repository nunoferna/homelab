#!/usr/bin/env python3
"""Validate the lightweight app.yaml contract used by the Argo CD ApplicationSets."""

from __future__ import annotations

from pathlib import Path
import sys


ROOT = Path("gitops")
APP_FILES = sorted(ROOT.glob("apps/*/app.yaml")) + sorted(ROOT.glob("platform/*/app.yaml"))

COMMON_REQUIRED = {"appName", "namespace", "project", "syncWave"}
OCI_REQUIRED = {"repoURL", "targetRevision", "chartPath", "serverSideApply"}
HELM_REQUIRED = {"repoURL", "targetRevision", "chart"}
ALLOWED_PROJECTS = {"apps", "platform"}


def parse_scalar(value: str) -> object:
    value = value.strip()
    if value in {"true", "false"}:
        return value == "true"
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1]
    if value.startswith("'") and value.endswith("'"):
        return value[1:-1]
    return value


def load_yaml(path: Path) -> dict:
    data: dict[str, object] = {}
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if raw_line[:1].isspace():
            raise ValueError(f"line {line_number}: app.yaml must stay a flat key/value mapping")
        if ":" not in line:
            raise ValueError(f"line {line_number}: expected key: value")
        key, value = line.split(":", 1)
        key = key.strip()
        if not key:
            raise ValueError(f"line {line_number}: key is empty")
        data[key] = parse_scalar(value)
    return data


def validate_app(path: Path) -> list[str]:
    errors: list[str] = []

    try:
        data = load_yaml(path)
    except Exception as exc:  # noqa: BLE001 - this is a CLI validator.
        return [f"{path}: {exc}"]

    missing = sorted(COMMON_REQUIRED - data.keys())
    if missing:
        errors.append(f"{path}: missing required keys: {', '.join(missing)}")

    expected_project = "apps" if path.parts[1] == "apps" else "platform"
    project = data.get("project")
    if project not in ALLOWED_PROJECTS:
        errors.append(f"{path}: project must be one of: {', '.join(sorted(ALLOWED_PROJECTS))}")
    elif project != expected_project:
        errors.append(f"{path}: project must be {expected_project!r} for this folder")

    if "repoURL" in data and "chart" not in data:
        missing = sorted(OCI_REQUIRED - data.keys())
        if missing:
            errors.append(f"{path}: OCI-style apps must set: {', '.join(missing)}")

    if "chart" in data:
        missing = sorted(HELM_REQUIRED - data.keys())
        if missing:
            errors.append(f"{path}: Helm repo apps must set: {', '.join(missing)}")

    if data.get("noBase") is True and (path.parent / "base").exists():
        errors.append(f"{path}: noBase is true but a base/ directory exists")

    if data.get("noBase") is not True and not (path.parent / "base").exists():
        errors.append(f"{path}: missing base/ directory; set noBase: true if intentional")

    return errors


def main() -> int:
    errors = [error for path in APP_FILES for error in validate_app(path)]
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
