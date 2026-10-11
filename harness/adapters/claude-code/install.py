#!/usr/bin/env python3
"""Адаптер Claude Code харнесса (EPIC-026 Ф4, решение Р11).

Кладёт в ~/.claude общие хуки и панель и подключает их в settings.json.
Только ДОБАВЛЯЕТ и идемпотентен:
  - файл отсутствует -> копируется; совпадает -> не трогаем; отличается ->
    НЕ перезаписываем, говорим вслух (там может лежать правка владельца);
  - settings.json: добавляется SessionStart-хук и statusLine, если их нет;
    перед записью бэкап рядом. Чужие хуки и права не трогаются.
Нет ~/.claude (Claude Code не стоит) - тихий пропуск.

Сюда НЕ входят: release-gate.sh и psi-mark.sh (привязаны к продукту ds) и
~/.claude/agents/*.md (голос и права владельца).
"""
import datetime
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CC = os.path.join(os.path.expanduser("~"), ".claude")
FILES = [  # (источник, приёмник, исполняемый)
    ("hooks/session-start.sh", "hooks/session-start.sh", True),
    ("hooks/orchestrator.sh", "hooks/orchestrator.sh", True),
    ("statusline.sh", "statusline.sh", True),
    ("statusline-tokens.py", "statusline-tokens.py", False),
]


def ok(m):
    print("\033[1;32m  ✓ %s\033[0m" % m)


def same(m):
    print("    · %s" % m)


def warn(m):
    print("\033[1;33m  ! %s\033[0m" % m)


def same_bytes(a, b):
    with open(a, "rb") as x, open(b, "rb") as y:
        return x.read() == y.read()


def files():
    for src, dst, exe in FILES:
        s, d = os.path.join(HERE, src), os.path.join(CC, dst)
        os.makedirs(os.path.dirname(d), exist_ok=True)
        if not os.path.exists(d):
            shutil.copy2(s, d)
            if exe:
                os.chmod(d, 0o755)
            ok("Claude Code: ~/.claude/%s положен" % dst)
        elif same_bytes(s, d):
            same("Claude Code: ~/.claude/%s уже на месте" % dst)
        else:
            warn("Claude Code: ~/.claude/%s отличается от дистрибутива - НЕ трогаю" % dst)
            print("        diff %s %s" % (d, s))


def has_cmd(entries, needle):
    for e in entries or []:
        for h in (e.get("hooks") or []):
            if needle in str(h.get("command", "")):
                return True
    return False


def settings():
    path = os.path.join(CC, "settings.json")
    with open(os.path.join(HERE, "settings-fragment.json"), encoding="utf-8") as f:
        frag = json.load(f)
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            conf = json.load(f)
        existed = True
    else:
        conf, existed = {}, False
    changed = []
    hooks = conf.setdefault("hooks", {})
    ss = hooks.setdefault("SessionStart", [])
    if not has_cmd(ss, "session-start.sh"):
        ss.extend(frag["hooks"]["SessionStart"])
        changed.append("SessionStart (порог смены)")
    if "statusLine" not in conf:
        conf["statusLine"] = frag["statusLine"]
        changed.append("statusLine (панель)")
    if not changed:
        same("Claude Code: settings.json уже подключён")
        return
    bak = ""
    if existed:
        bak = "%s.bak-%s" % (path, datetime.datetime.now().strftime("%Y-%m-%d-%H%M%S"))
        shutil.copy2(path, bak)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(conf, f, indent=2, ensure_ascii=False)
        f.write("\n")
    ok("Claude Code: settings.json - добавлено: %s%s" % (", ".join(changed), " (бэкап: %s)" % os.path.basename(bak) if bak else ""))


def main():
    if not os.path.isdir(CC):
        same("Claude Code не найден (~/.claude нет) - адаптер пропущен")
        return 0
    files()
    settings()
    return 0


if __name__ == "__main__":
    sys.exit(main())
