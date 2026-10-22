#!/usr/bin/env python3
"""提交前密钥扫描：拦截疑似真实凭据，避免误传到开源仓库。

用法：
    python scripts/scan_secrets.py              # 扫描 git 暂存区
    python scripts/scan_secrets.py path1 path2  # 扫描指定文件

命中的行若包含占位符关键词（change-me、xxxxxxxx、example 等）会被跳过，
因此 .env.example 这类模板文件不会误报。
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

PLACEHOLDER_MARKERS = (
    "change-me",
    "xxxxxxxx",
    "your-",
    "example",
    "placeholder",
    "sk-xxxx",
    "test-",
    "dummy",
)

PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("OpenAI/DeepSeek 风格 API Key", re.compile(r"sk-[A-Za-z0-9]{16,}")),
    ("AWS Access Key", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("私钥文件内容", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    (
        "疑似真实凭据赋值",
        re.compile(r"(SECRET_KEY|API_KEY|PASSWORD|TOKEN|PASSWD)\s*[=:]\s*['\"]?([^\s'\"#]{12,})"),
    ),
]

SKIP_SUFFIXES = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".pdf",
    ".zip", ".gz", ".woff", ".woff2", ".ttf", ".lock", ".snap",
}


def staged_files() -> list[str]:
    """返回 git 暂存区中新增/修改/重命名的文件。"""
    result = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"],
        capture_output=True,
        text=True,
        check=False,
    )
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def scan(paths: list[str]) -> int:
    findings: list[str] = []
    for raw in paths:
        path = Path(raw)
        if not path.is_file() or path.suffix.lower() in SKIP_SUFFIXES:
            continue
        try:
            content = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for lineno, line in enumerate(content.splitlines(), start=1):
            lowered = line.lower()
            if any(marker in lowered for marker in PLACEHOLDER_MARKERS):
                continue
            for label, pattern in PATTERNS:
                if pattern.search(line):
                    findings.append(f"{raw}:{lineno}: {label}")
                    break

    if findings:
        print("检测到疑似真实凭据，已阻止提交：", file=sys.stderr)
        for item in findings:
            print(f"  - {item}", file=sys.stderr)
        print("\n请改用占位符，或写入已被 .gitignore 排除的 .env。", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(scan(sys.argv[1:] or staged_files()))
