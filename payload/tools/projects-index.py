#!/usr/bin/env python3
"""projects-index — индекс и сторож раскладки проектов (метод ЭВМ, EPIC-025).

Строит ~/projects/INDEX.md по паспортам проектов и ловит беспорядок на диске.
Индекс руками не правится: его истина — паспорта и git, а не память.

Режимы:
  projects-index.py            проверка: сводка + список нарушений (ничего не пишет)
  projects-index.py --summary  одна строка для хука старта смены
  projects-index.py --write    записать ~/projects/INDEX.md (+ вывод проверки)
  --strict                     код возврата 1, если есть нарушения
  --root DIR                   корень проектов (по умолчанию ~/projects)

Паспорт — блок в первых 80 строках AGENTS.md (или CLAUDE.md) проекта:
  <!-- passport
  key: apl
  parent: alfa
  planning: team-work/alfa/apl
  status: active
  -->
Поля: key (обязательно), parent, planning (путь от корня проектов), status
(active | paused | archive), about (одна фраза).

Правила раскладки — ~/agent-os/method/layout.md.
"""
import argparse
import datetime as dt
import os
import re
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
ROOT_ALLOWED = {"team-work", "_archive", "INDEX.md", "CLAUDE.md", "AGENTS.md"}
HOME_ALLOWED = {"projects", "agent-os", "bot_factory", "backups", "deploy"}
HOME_EXTRA = HOME / ".config" / "vosmenog" / "home-allowed"  # доп. имена, по строке
SKIP_DIRS = {".git", ".worktrees", "node_modules", "_archive", "__pycache__"}
PASSPORT_RE = re.compile(r"<!--\s*passport\b(.*?)-->", re.S)


def git(repo, *args):
    r = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def read_passport(d: Path):
    for name in ("AGENTS.md", "CLAUDE.md"):
        f = d / name
        if not f.is_file():
            continue
        try:
            head = "".join(f.open(encoding="utf-8", errors="replace").readlines()[:80])
        except OSError:
            continue
        m = PASSPORT_RE.search(head)
        if not m:
            continue
        p = {}
        for part in re.split(r"\n|·", m.group(1)):
            if ":" in part:
                k, v = part.split(":", 1)
                p[k.strip()] = v.strip()
        p["_file"] = name
        return p
    return None


def is_inside(child: Path, parent: Path):
    try:
        child.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


class Audit:
    def __init__(self, root: Path):
        self.root = root
        self.projects = []      # dict: path, passport, kind(repo|plain), origin, branch, last
        self.worktrees = []     # dict: repo, path, branch, merged, placed
        self.issues = []        # (категория, текст)

    def add(self, cat, text):
        self.issues.append((cat, text))

    def rel(self, p: Path):
        p = Path(p)
        for base, label in ((self.root, "~/projects"), (HOME, "~")):
            try:
                return f"{label}/{p.relative_to(base)}" if p != base else label
            except ValueError:
                pass
        return str(p)

    # ---- обход ----
    def candidates(self):
        """Каталоги-проекты: глубина 1 и вложенные подпроекты на глубине 2."""
        for d in sorted(self.root.iterdir()):
            if d.name.startswith(".") or d.name in SKIP_DIRS:
                continue
            if d.is_symlink():
                continue  # симлинки разбирает links()
            if not d.is_dir():
                if d.name not in ROOT_ALLOWED:
                    self.add("лишнее в корне", f"{self.rel(d)} — файл в корне проектов")
                continue
            if d.name == "team-work":
                yield d, 1
                for sub in sorted(d.iterdir()):
                    if sub.is_dir() and not sub.is_symlink() and (sub / ".git").is_dir():
                        yield sub, 2   # закрытое планирование со своим git
                continue
            yield d, 1
            for sub in sorted(d.iterdir()):
                if sub.name in SKIP_DIRS or sub.name.startswith(".") or sub.is_symlink():
                    continue
                if sub.is_dir() and ((sub / ".git").exists() or read_passport(sub)):
                    yield sub, 2

    def scan(self):
        for d, depth in self.candidates():
            gitp = d / ".git"
            if gitp.is_file():
                # worktree, лежащий как проект: сам по себе нарушение,
                # подробности дадут списки worktree его репозитория
                continue
            pp = read_passport(d)
            is_repo = gitp.is_dir()
            if depth == 1 and not is_repo and not pp and d.name not in ROOT_ALLOWED:
                self.add("без паспорта", f"{self.rel(d)} — не репозиторий и без паспорта (сирота?)")
                continue
            proj = {"path": d, "passport": pp, "repo": is_repo, "depth": depth}
            if is_repo:
                proj["origin"] = git(d, "remote", "get-url", "origin") or "— (нет remote)"
                proj["branch"] = git(d, "rev-parse", "--abbrev-ref", "HEAD") or "?"
                proj["last"] = (git(d, "log", "-1", "--format=%cs") or "—")
                self.worktrees_of(d)
            self.projects.append(proj)
            if not pp:
                self.add("без паспорта", f"{self.rel(d)} — нет блока passport в AGENTS.md/CLAUDE.md")
            if depth == 2 and is_repo and d.parent.name != "team-work" and (d.parent / ".git").is_dir():
                if git(d.parent, "check-ignore", "-q", d.name) is None:
                    self.add("вложенный репо", f"{self.rel(d)} — не исключён в .gitignore родителя")
        self.check_parents()
        self.links()
        self.home()
        self.stray_worktrees()

    def worktrees_of(self, repo: Path):
        out = git(repo, "worktree", "list", "--porcelain")
        if not out:
            return
        trunk = git(repo, "rev-parse", "--abbrev-ref", "HEAD")
        blocks = out.split("\n\n")
        for b in blocks[1:]:  # первый — основной
            info = {}
            for line in b.splitlines():
                k, _, v = line.partition(" ")
                info[k] = v
            path = Path(info.get("worktree", ""))
            branch = info.get("branch", "").replace("refs/heads/", "") or "(detached)"
            placed = is_inside(path, repo / ".worktrees") if path.exists() else False
            merged = None
            if branch != "(detached)" and trunk:
                r = subprocess.run(["git", "-C", str(repo), "merge-base", "--is-ancestor", branch, trunk])
                merged = r.returncode == 0
            wt = {"repo": repo, "path": path, "branch": branch, "merged": merged,
                  "placed": placed, "prunable": "prunable" in info, "trunk": trunk}
            self.worktrees.append(wt)
            where = self.rel(path)
            if wt["prunable"]:
                self.add("worktree мёртв", f"{where} — каталога нет, нужен `git worktree prune` в {self.rel(repo)}")
                continue
            if not placed:
                self.add("worktree не на месте", f"{where} [{branch}] — должен быть в {self.rel(repo)}/.worktrees/")
            if merged:
                self.add("worktree влит", f"{where} [{branch}] — влит в {trunk}, снять: wt done")
            if placed and path.name != branch and branch != "(detached)":
                self.add("worktree: имя ≠ ветка", f"{where} — ветка {branch}")

    def stray_worktrees(self):
        """Каталоги-worktree в корне, чей репозиторий не найден в обходе."""
        known = {w["path"].resolve() for w in self.worktrees if w["path"].exists()}
        for d in sorted(self.root.iterdir()):
            if (d / ".git").is_file() and d.resolve() not in known:
                self.add("worktree не на месте", f"{self.rel(d)} — worktree чужого или потерянного репозитория")

    def check_parents(self):
        by_key = {p["passport"]["key"]: p for p in self.projects if p["passport"] and p["passport"].get("key")}
        for p in self.projects:
            pp = p["passport"]
            if not pp:
                continue
            if not pp.get("key"):
                self.add("паспорт", f"{self.rel(p['path'])} — в паспорте нет key")
            par = pp.get("parent")
            if par:
                if par not in by_key:
                    self.add("паспорт", f"{self.rel(p['path'])} — parent «{par}» не найден среди паспортов")
                elif not is_inside(p["path"], by_key[par]["path"]):
                    self.add("подпроект вне родителя", f"{self.rel(p['path'])} — должен лежать внутри {self.rel(by_key[par]['path'])}")
            plan = pp.get("planning")
            if plan and not (self.root / plan).exists():
                self.add("паспорт", f"{self.rel(p['path'])} — planning {plan} не существует")

    def links(self):
        for d in [self.root, *[x for x in self.root.iterdir() if x.is_dir() and not x.is_symlink()]]:
            for e in d.iterdir():
                if e.is_symlink():
                    tgt = Path(os.path.realpath(e))
                    if not is_inside(tgt, self.root):
                        self.add("ссылка наружу", f"{self.rel(e)} → {tgt}")

    def home(self):
        allowed = set(HOME_ALLOWED)
        if HOME_EXTRA.is_file():
            allowed |= {l.strip() for l in HOME_EXTRA.read_text().splitlines() if l.strip()}
        for e in sorted(HOME.iterdir()):
            n = e.name
            if n.startswith("."):
                if re.search(r"\.(bak|orig|old)\b|\.bak-|\.tmp\.", n):
                    self.add("лишнее в ~", f"~/{n} — снимок/хвост: место ему в ~/backups/")
                continue
            if n not in allowed:
                self.add("лишнее в ~", f"~/{n}")

    # ---- вывод ----
    def summary(self):
        if not self.issues:
            return "Раскладка: чисто."
        cats = {}
        for c, _ in self.issues:
            cats[c] = cats.get(c, 0) + 1
        parts = ", ".join(f"{c} {n}" for c, n in sorted(cats.items(), key=lambda x: -x[1]))
        return f"Раскладка: беспорядок {len(self.issues)} ({parts}) → ~/agent-os/bin/projects-index.py"

    def report(self):
        lines = [self.summary()]
        cur = None
        for c, t in sorted(self.issues, key=lambda x: x[0]):
            if c != cur:
                lines.append(f"\n  [{c}]")
                cur = c
            lines.append(f"    • {t}")
        return "\n".join(lines)

    def index_md(self):
        now = dt.datetime.now().strftime("%Y-%m-%d %H:%M")
        out = [
            "# INDEX — проекты на сервере",
            "",
            f"**Сгенерирован** {now} скриптом `~/agent-os/bin/projects-index.py --write`.",
            "**Руками не править:** истина — паспорта в `AGENTS.md` проектов и git.",
            "Правила раскладки — `~/agent-os/method/layout.md`.",
            "",
            "| Ключ | Путь | Родитель | Статус | Планирование | Репозиторий | Ветка | Посл. коммит |",
            "|---|---|---|---|---|---|---|---|",
        ]
        def order(p):
            pp = p["passport"] or {}
            return (pp.get("parent") or pp.get("key") or p["path"].name, bool(pp.get("parent")), str(p["path"]))
        for p in sorted(self.projects, key=order):
            pp = p["passport"] or {}
            key = pp.get("key", "**?**")
            if pp.get("parent"):
                key = "↳ " + key
            origin = p.get("origin", "—")
            origin = re.sub(r"^git@github\.com:|^https://github\.com/|\.git$", "", origin)
            out.append("| {} | `{}` | {} | {} | {} | {} | {} | {} |".format(
                key, self.rel(p["path"]), pp.get("parent", ""), pp.get("status", ""),
                f"`{pp['planning']}`" if pp.get("planning") else "",
                origin, p.get("branch", ""), p.get("last", "")))
        out += ["", "## Рабочие ветки (worktree)", ""]
        if self.worktrees:
            out += ["| Репозиторий | Каталог | Ветка | Влита | На месте |", "|---|---|---|---|---|"]
            for w in self.worktrees:
                out.append("| `{}` | `{}` | {} | {} | {} |".format(
                    self.rel(w["repo"]), self.rel(w["path"]), w["branch"],
                    {True: "да — снять", False: "нет", None: "?"}[w["merged"]],
                    "да" if w["placed"] else "**нет**"))
        else:
            out.append("Нет.")
        out += ["", "## Нарушения раскладки", ""]
        if self.issues:
            for c, t in sorted(self.issues):
                out.append(f"- **{c}:** {t}")
        else:
            out.append("Нет.")
        return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", default=str(HOME / "projects"))
    ap.add_argument("--summary", action="store_true")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--strict", action="store_true")
    a = ap.parse_args()
    root = Path(a.root).expanduser()
    if not root.is_dir():
        print(f"нет каталога проектов: {root}", file=sys.stderr)
        return 2
    au = Audit(root)
    au.scan()
    if a.summary:
        print(au.summary())
    else:
        print(au.report())
    if a.write:
        (root / "INDEX.md").write_text(au.index_md(), encoding="utf-8")
        print(f"\nзаписан {root / 'INDEX.md'}")
    return 1 if (a.strict and au.issues) else 0


if __name__ == "__main__":
    sys.exit(main())
