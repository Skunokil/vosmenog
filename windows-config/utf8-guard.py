#!/usr/bin/env python3
"""Ставит в python-скрипты метода страховку от cp1252 на Windows.

Зачем: скрипты печатают «✓» и русский текст. Нативный python на Windows берёт
кодировку консоли (cp1252/cp866/cp1251), и такой print падает с
UnicodeEncodeError — установка обрывается на середине, а «порог смены» молчит.

Что делает: после блока импортов каждого файла вставляет перевод stdout/stderr
в utf-8 (errors=replace). Идемпотентно: повторный запуск ничего не меняет.

  python3 windows-config/utf8-guard.py [каталог]
"""
import io
import os
import re
import sys

MARK = "# --- windows: utf-8 stdout"

SNIPPET = '''
# --- windows: utf-8 stdout ---
# На Windows кодировка консоли — cp1252/cp866, и печать «✓» или русского текста
# падает с UnicodeEncodeError. Переводим вывод в utf-8 (с заменой непечатаемого).
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
'''

IMPORT_RE = re.compile(r"^(?:import|from)\s+\S+.*$", re.MULTILINE)


def patch(path):
    with io.open(path, encoding="utf-8") as f:
        src = f.read()
    if MARK in src:
        return "skip"
    if "import sys" not in src:
        return "no sys"
    imports = list(IMPORT_RE.finditer(src))
    if not imports:
        return "no imports"
    last = imports[-1]
    end = src.find("\n", last.end())
    if end == -1:
        return "no eol"
    out = src[:end + 1] + SNIPPET + src[end + 1:]
    with io.open(path, "w", encoding="utf-8", newline="") as f:
        f.write(out)
    return "patched"


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__)) + "/.."
    targets = []
    for d, _, fs in os.walk(root):
        if ".git" in d.split(os.sep):
            continue
        for f in fs:
            p = os.path.join(d, f)
            if f.endswith(".py"):
                targets.append(p)
                continue
            # скрипты без расширения, но с python-shebang (evm, evm-threshold)
            try:
                with io.open(p, "rb") as fh:
                    head = fh.read(2)
            except OSError:
                continue
            if head == b"#!":
                try:
                    with io.open(p, encoding="utf-8") as fh:
                        first = fh.readline()
                except (OSError, UnicodeDecodeError):
                    continue
                if "python" in first:
                    targets.append(p)
    counts = {}
    for p in sorted(targets):
        r = patch(p)
        counts[r] = counts.get(r, 0) + 1
        if r == "patched":
            print("patched: %s" % os.path.relpath(p, root))
    print("итого: %s" % ", ".join("%s=%d" % kv for kv in sorted(counts.items())))


if __name__ == "__main__":
    main()
