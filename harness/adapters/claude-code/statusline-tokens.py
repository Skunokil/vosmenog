#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Панель Минотавра для statusLine Claude Code.

Выводит:  <уровень доверия> · ctx NN% · сессия N.NM · нед NN.NM

Источники:
  доверие — ~/.config/opencode/memory/user-profile.md → trust_level (единый
            источник истины для всех персон; правится командой /trust)
  токены  — ~/.claude/projects/**/*.jsonl (транскрипты): usage у assistant-строк.
            Сессия — свой транскрипт (transcript_path из stdin-JSON).
            Неделя — скользящие 168 часов по всем проектам, через кеш
            ~/.claude/cache/weekly-tokens.json (TTL 300 с), иначе перерисовка
            панели упиралась бы в 187 МБ логов.

Дедупликация обязательна: одна реплика ассистента пишется в jsonl несколько раз
(стриминговые снапшоты) с одним message.id — считаем каждый id один раз.
"""
import json
import os
import re
import sys
import time
from pathlib import Path

HOME = Path.home()
PROFILE = HOME / ".config/opencode/memory/user-profile.md"
PROJECTS = HOME / ".claude/projects"
CACHE = HOME / ".claude/cache/weekly-tokens.json"
CACHE_TTL = 300           # с — как часто пересчитывать недельный свод
WEEK = 7 * 24 * 3600
CTX_LIMIT_FALLBACK = 200_000   # запасное окно, если харнесс не отдал своё

RED, YELLOW, GREEN, GREY, RESET = "\033[31m", "\033[33m", "\033[32m", "\033[90m", "\033[0m"


def trust_level():
    """Уровень доверия = плотность пояснений (решение владельца 2026-09-07).

    Полей в профиле два (trust_level и detail_level) — их читают плагин
    Восьменога, скиллы и шаблоны курса. /trust держит их синхронно; если оси
    всё же разошлись, панель врать не должна — возвращаем метку "!".
    """
    try:
        src = PROFILE.read_text(encoding="utf-8")
    except OSError:
        return "обучающий", False
    def axis(name, default):
        m = re.search(r"^\s*%s:\s*(\S+)" % name, src, re.M)
        return m.group(1) if m else default
    trust = axis("trust_level", "обучающий")
    detail = axis("detail_level", trust)      # деградация: нет detail -> trust
    return trust, detail != trust


def heat(pct):
    """Цвет по заполненности: спокойно / пора оглядеться / жарко."""
    return RED if pct >= 80 else YELLOW if pct >= 60 else GREY


def reset_in(ts):
    """Сколько осталось до сброса окна лимита: 2д, 7ч, 40м."""
    left = ts - time.time()
    if left <= 0:
        return "сброс"
    if left >= 86400:
        return f"{int(left // 86400)}д"
    if left >= 3600:
        return f"{int(left // 3600)}ч"
    return f"{int(left // 60)}м"


def human(n):
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.0f}k"
    return str(n)


def usage_sum(u):
    """Свежие токены запроса: без cache_read.

    cache_read — перечитывание уже оплаченного кеша, он даёт ~98% валового
    объёма и меряет длину разговоров, а не работу. В расход не берём:
    иначе панель всегда показывает сотни миллионов и ни о чём не говорит.
    """
    return (u.get("input_tokens", 0)
            + u.get("cache_creation_input_tokens", 0)
            + u.get("output_tokens", 0))


def scan(path, since=None):
    """(сумма токенов, последний usage) по транскрипту, с дедупом по message.id."""
    total, seen, last = 0, set(), None
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if '"usage"' not in line:
                    continue
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                msg = rec.get("message")
                if not isinstance(msg, dict):
                    continue
                u = msg.get("usage")
                if not isinstance(u, dict):
                    continue
                if since is not None:
                    ts = rec.get("timestamp", "")
                    try:
                        t = time.mktime(time.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S"))
                        t -= time.timezone            # timestamp в UTC
                    except (ValueError, TypeError):
                        t = None
                    if t is not None and t < since:
                        continue
                mid = msg.get("id") or rec.get("uuid")
                if mid in seen:
                    continue
                seen.add(mid)
                total += usage_sum(u)
                last = u
    except OSError:
        pass
    return total, last


def weekly():
    """Свод за скользящие 7 дней. Кеш, чтобы не читать 187 МБ на каждую перерисовку."""
    now = time.time()
    try:
        c = json.loads(CACHE.read_text())
        if now - c.get("ts", 0) < CACHE_TTL:
            return c.get("total", 0)
    except (OSError, ValueError):
        pass

    since = now - WEEK
    total = 0
    for f in PROJECTS.rglob("*.jsonl"):
        try:
            if f.stat().st_mtime < since:      # файл целиком старше окна
                continue
        except OSError:
            continue
        total += scan(f, since=since)[0]

    try:
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        CACHE.write_text(json.dumps({"ts": now, "total": total}))
    except OSError:
        pass
    return total


def main():
    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError):
        payload = {}


    # Транскрипт берём только тот, что назвал харнесс. Запасного пути «самый
    # свежий jsonl» здесь был баг (2026-09-09): в первую секунду новой сессии
    # своего файла на диске ещё нет, и панель показывала расход ПРЕДЫДУЩЕЙ
    # смены как текущий — 542k на пустом старте. Прочерк не врёт, чужая
    # цифра врёт правдоподобно.
    transcript = payload.get("transcript_path")
    if transcript and os.path.exists(transcript):
        session_total, last = scan(transcript)
    else:
        session_total, last = None, None

    # Загрузка окна контекста. Харнесс считает её сам и отдаёт готовой — берём
    # его цифру: размер окна зависит от модели (у Opus 5 это 1M, не 200k),
    # зашивать константу нельзя. Свой расчёт — только запасной путь.
    cw = payload.get("context_window") or {}
    pct = cw.get("used_percentage")
    if pct is None:
        limit = cw.get("context_window_size") or CTX_LIMIT_FALLBACK
        ctx = sum(last.get(k, 0) for k in ("input_tokens",
                                           "cache_creation_input_tokens",
                                           "cache_read_input_tokens")) if last else 0
        pct = min(int(ctx * 100 / limit), 999) if ctx else 0
    pct = int(pct)

    # Лимиты плана — тоже от харнесса (те же цифры, что показывает /usage).
    rl = payload.get("rate_limits") or {}

    def window(key):
        w = rl.get(key) or {}
        p = w.get("used_percentage")
        return (int(p), w.get("resets_at")) if p is not None else (None, None)

    h5, _ = window("five_hour")
    d7, d7_reset = window("seven_day")

    level, desync = trust_level()
    lvl_color = {"продвинутый": RED, "средний": YELLOW}.get(level, GREEN)
    if desync:
        level += "!"                          # оси разошлись — панель предупреждает

    session_str = human(session_total) if session_total is not None else "—"
    parts = [f"{lvl_color}{level}{RESET}",
             f"{heat(pct)}сессия {pct}%{RESET} {GREY}({session_str}){RESET}"]
    if h5 is not None:
        parts.append(f"{heat(h5)}5ч {h5}%{RESET}")
    if d7 is not None:
        tail = f" {GREY}↻{reset_in(d7_reset)}{RESET}" if d7_reset else ""
        parts.append(f"{heat(d7)}нед {d7}%{RESET} {GREY}({human(weekly())}){RESET}{tail}")
    else:
        parts.append(f"нед {human(weekly())}")

    print(f" {GREY}·{RESET} ".join(parts))


if __name__ == "__main__":
    main()
