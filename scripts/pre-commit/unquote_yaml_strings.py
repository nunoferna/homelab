from __future__ import annotations

import io
import re
import sys
from pathlib import Path
from typing import Any

from ruamel.yaml import YAML
from ruamel.yaml.comments import CommentedMap, CommentedSeq
from ruamel.yaml.scalarstring import DoubleQuotedScalarString, PlainScalarString, SingleQuotedScalarString


YAML_LIKE_NON_STRINGS = {
    "false",
    "null",
    "off",
    "on",
    "true",
    "~",
}


def can_be_plain_string(value: str) -> bool:
    if not value or value != value.strip():
        return False
    if "\n" in value or "\r" in value or "\t" in value:
        return False
    if value.lower() in YAML_LIKE_NON_STRINGS:
        return False
    if ": " in value or " #" in value:
        return False

    yaml = YAML(typ="safe")
    try:
        parsed = yaml.load(f"value: {value}\n")["value"]
    except Exception:
        return False
    return isinstance(parsed, str) and parsed == value


def unquote(value: Any) -> Any:
    if isinstance(value, CommentedMap):
        for key in list(value):
            value[key] = unquote(value[key])
        return value

    if isinstance(value, CommentedSeq):
        for index, item in enumerate(value):
            value[index] = unquote(item)
        return value

    if isinstance(value, (DoubleQuotedScalarString, SingleQuotedScalarString)):
        text = str(value)
        if can_be_plain_string(text):
            return PlainScalarString(text)

    return value


def normalize_top_level_sequence(text: str, documents: list[Any]) -> str:
    if not documents or not isinstance(documents[0], CommentedSeq):
        return text
    return re.sub(r"(?m)^  ", "", text)


def prepare_top_level_sequence(text: str) -> str:
    if not text.startswith("- "):
        return text
    for line in text.splitlines()[1:]:
        if not line.strip():
            continue
        if re.match(r"^ {4,}\S", line):
            return re.sub(r"(?m)^  ", "", text)
        return text
    return re.sub(r"(?m)^  ", "", text)


def format_file(path: Path) -> bool:
    original = path.read_text(encoding="utf-8")
    parse_input = prepare_top_level_sequence(original)

    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.indent(mapping=2, sequence=4, offset=2)
    yaml.width = 4096
    yaml.top_level_colon_align = False

    documents = list(yaml.load_all(parse_input))
    documents = [unquote(document) for document in documents]

    output = io.StringIO()
    yaml.dump_all(documents, output)
    formatted = normalize_top_level_sequence(output.getvalue(), documents)
    formatted = re.sub(r"(?<! ) #", "  #", formatted)

    if formatted != original:
        path.write_text(formatted, encoding="utf-8")
        return True
    return False


def main() -> int:
    changed = False
    for filename in sys.argv[1:]:
        path = Path(filename)
        if path.exists():
            changed = format_file(path) or changed
    return 1 if changed else 0


if __name__ == "__main__":
    raise SystemExit(main())
