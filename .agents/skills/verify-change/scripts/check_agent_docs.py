#!/usr/bin/env python3
"""Check this repository's agent documents without installing dependencies.

This checks our name/description-only metadata convention, required sections,
Skill index, and local file links. It is not a general YAML or Agent Skills
specification validator and does not test an agent runtime's discovery behavior.
"""

import argparse
import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit


SECTIONS = (
    "## 사용 시점",
    "## 팀 규칙",
    "## 절차",
    "## 주의사항과 예외",
    "## 결과 검증",
)
LINK = re.compile(r"\[[^\]\n]+\]\(([^)\n]+)\)")


def check(root: Path) -> list[str]:
    errors = []
    index_path = root / "AGENTS.md"
    guide_path = root / "docs/agent-rules.md"
    skills_root = root / ".agents/skills"
    skill_dirs = sorted(path for path in skills_root.iterdir() if path.is_dir()) if skills_root.is_dir() else []
    if not skill_dirs:
        errors.append(".agents/skills: no Skill directories found")

    paths = [index_path, guide_path] + [path / "SKILL.md" for path in skill_dirs]
    documents = {}
    for path in paths:
        label = path.relative_to(root)
        try:
            documents[path] = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as error:
            errors.append(f"{label}: cannot read UTF-8 document ({error})")

    index = documents.get(index_path, "")
    names = set()
    for directory in skill_dirs:
        path = directory / "SKILL.md"
        if path not in documents:
            continue
        label = path.relative_to(root)
        text = documents[path]
        lines = text.splitlines()
        if not lines or lines[0] != "---" or "---" not in lines[1:]:
            errors.append(f"{label}: missing frontmatter delimiters")
            continue
        end = lines.index("---", 1)
        metadata = {}
        for line in lines[1:end]:
            # Repository convention: exactly two plain, single-line scalars.
            key, separator, value = line.partition(": ")
            if not separator or key not in ("name", "description") or key in metadata:
                errors.append(f"{label}: invalid or duplicate metadata field")
                continue
            metadata[key] = value
        name = metadata.get("name", "")
        if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", name) or len(name) > 64:
            errors.append(f"{label}: invalid name")
        if name != directory.name or name in names:
            errors.append(f"{label}: name must match directory and be unique")
        names.add(name)
        description = metadata.get("description", "")
        if not description.strip() or len(description) > 1024:
            errors.append(f"{label}: description must contain 1–1024 characters")
        # Reject YAML constructs outside the intentionally small convention.
        if description.startswith(("|", ">", "'", '"', "[", "{", "#", "&", "*", "!")) or ": " in description or " #" in description:
            errors.append(f"{label}: description must be a plain single-line scalar")
        body = "\n".join(lines[end + 1:])
        for section in SECTIONS:
            if section not in body.splitlines():
                errors.append(f"{label}: missing section {section}")
        if f".agents/skills/{directory.name}/SKILL.md" not in index:
            errors.append(f"{label}: not linked from AGENTS.md")

    for path, text in documents.items():
        for target in LINK.findall(text):
            parsed = urlsplit(target)
            if parsed.scheme or parsed.netloc or not parsed.path:
                continue
            destination = (path.parent / unquote(parsed.path)).resolve()
            if not destination.is_relative_to(root) or not destination.is_file():
                errors.append(f"{path.relative_to(root)}: broken local file link {target}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[4])
    args = parser.parse_args()
    root = args.root.resolve()
    errors = check(root)
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        print(f"Agent document checks FAILED ({len(errors)} errors)", file=sys.stderr)
        return 1
    print("Agent document checks PASSED (metadata, required sections, index, local file links)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
