#!/usr/bin/env python3
"""Подключает карту сервера (слот SERVER.md) в обе среды. Идемпотентно.

Зовут setup.sh и update.sh. Только ДОБАВЛЯЕТ: ничего не убирает и не
переписывает. Перед правкой чужого конфига кладёт бэкап рядом.

  1. ~/projects/team-work/SERVER.md  — нет файла: заготовка из harness/;
                                        есть: не трогаем ни байта.
  2. ~/.config/opencode/opencode.json — в instructions[] добавить карту.
  3. ~/.claude/CLAUDE.md              — дописать импорт @...SERVER.md.
                                        Нет Claude Code / нет файла — пропуск.

Путь карты — решение Р6 EPIC-026 vosmenog: ~/projects/team-work/SERVER.md.
"""
import datetime
import json
import os
import shutil
import sys

HOME = os.path.expanduser("~")
MAP_REL = "projects/team-work/SERVER.md"
MAP = os.path.join(HOME, MAP_REL)
MAP_REF = "~/" + MAP_REL
OC_JSON = os.path.join(HOME, ".config/opencode/opencode.json")
CC_MD = os.path.join(HOME, ".claude/CLAUDE.md")
TEMPLATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "server.template.md")


def ok(msg):
    print("\033[1;32m  ✓ %s\033[0m" % msg)


def same(msg):
    print("    · %s" % msg)


def warn(msg):
    print("\033[1;33m  ! %s\033[0m" % msg)


def backup(path):
    dst = "%s.bak-%s" % (path, datetime.datetime.now().strftime("%Y-%m-%d-%H%M%S"))
    shutil.copy2(path, dst)
    return dst


def slot_file():
    if os.path.exists(MAP):
        same("карта сервера уже есть — не трогаю: " + MAP_REF)
        return
    if not os.path.exists(TEMPLATE):
        warn("нет заготовки harness/server.template.md — карту не создаю")
        return
    os.makedirs(os.path.dirname(MAP), exist_ok=True)
    shutil.copy2(TEMPLATE, MAP)
    ok("создана заготовка карты сервера: %s (заполни под свою машину)" % MAP_REF)


def opencode():
    if not os.path.exists(OC_JSON):
        warn("нет opencode.json — подключение в opencode пропущено (его делает setup.sh)")
        return
    with open(OC_JSON, encoding="utf-8") as f:
        conf = json.load(f)
    ins = conf.setdefault("instructions", [])
    if any(str(x).endswith(MAP_REL) for x in ins):
        same("opencode: карта уже в instructions")
        return
    bak = backup(OC_JSON)
    ins.append(MAP_REF)
    with open(OC_JSON, "w", encoding="utf-8") as f:
        json.dump(conf, f, indent=2, ensure_ascii=False)
    ok("opencode: карта добавлена в instructions (бэкап: %s)" % os.path.basename(bak))


def claude_code():
    if not os.path.exists(CC_MD):
        same("Claude Code: нет ~/.claude/CLAUDE.md — пропуск")
        return
    with open(CC_MD, encoding="utf-8") as f:
        text = f.read()
    for line in text.splitlines():
        if line.strip().startswith("@") and line.strip().endswith(MAP_REL):
            same("Claude Code: импорт карты уже на месте")
            return
    bak = backup(CC_MD)
    sep = "" if text.endswith("\n") or not text else "\n"
    with open(CC_MD, "a", encoding="utf-8") as f:
        f.write("%s\n@%s\n" % (sep, MAP_REF))
    ok("Claude Code: импорт карты дописан в CLAUDE.md (бэкап: %s)" % os.path.basename(bak))


def main():
    if os.path.exists(os.path.join(HOME, ".config/vosmenog/harness-off")):
        same("харнесс выключен (evm off): карту сервера и подключения не добавляю; evm on включит")
        return 0
    slot_file()
    opencode()
    claude_code()
    return 0


if __name__ == "__main__":
    sys.exit(main())
