#!/usr/bin/env python3
"""Помощник tests/evm-auto-test.sh: вставляет в CHANGELOG.md тестовую запись.
Аргументы: yes|no (с пометкой безопасности или без) и ПОЛНЫЙ путь к CHANGELOG.md внутри временного каталога.
Отказывается работать с путём вне /tmp: это защита от случая, когда тест правит настоящий репозиторий."""
import sys

mode, path = sys.argv[1], sys.argv[2]
uniq = sys.argv[3] if len(sys.argv) > 3 else "0"   # уникальный заголовок: сценарии делят один origin
if not (path.startswith("/tmp/") or path.startswith("/var/tmp/")):
    sys.exit(f"отказ: {path} вне /tmp - тестовая запись не пишется в настоящий репозиторий")
s = open(path, encoding="utf-8").read()
i = s.index("## 20")
mark = "<!-- auto: ok -->\n" if mode == "yes" else ""
entry = f"## 2099-{mode}-{uniq} — тестовый релиз\n{mark}\n**1. Пункт.** Описание.\n\n---\n\n"
open(path, "w", encoding="utf-8").write(s[:i] + entry + s[i:])
