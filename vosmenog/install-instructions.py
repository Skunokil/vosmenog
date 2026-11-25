"""Install shipped OpenCode instructions while retaining user-authored settings."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

SOURCE = Path(__file__).resolve().parent
MARKER = b"    # " + "При установке сюда дописываются".encode()
DENY = re.compile(rb'    "(?:/|~/)[^"\r\n]+": deny\r?\n')


def preserve_perimeter(live, previous, updated):
    """Recognize only the exact deny block inserted by setup before the marker."""
    prefix, marker, suffix = previous.partition(MARKER)
    if not marker or MARKER not in updated or not live.startswith(prefix):
        return None
    added, marker, tail = live[len(prefix):].partition(MARKER)
    if not marker or tail != suffix or not added:
        return None
    lines = added.splitlines(keepends=True)
    if not all(DENY.fullmatch(line) for line in lines):
        return None
    extra = b"".join(line for line in lines if line not in updated.splitlines(keepends=True))
    return updated.replace(MARKER, extra + MARKER, 1)


def install(relative, destination, revision):
    if destination.is_symlink() or (destination.exists() and not destination.is_file()):
        print(f"{destination.name}: сохранён пользовательский путь")
        return
    updated = (SOURCE / relative).read_bytes()
    if destination.is_file():
        live = destination.read_bytes()
        if live == updated:
            return
        previous = None
        if revision:
            result = subprocess.run(
                ["git", "-C", str(SOURCE.parent), "show", f"{revision}:vosmenog/{relative}"],
                capture_output=True,
            )
            if result.returncode == 0:
                previous = result.stdout
        if previous != live:
            updated = (preserve_perimeter(live, previous, updated)
                       if relative == "agents/Vosmenog.md" and previous else None)
            if updated is None:
                print(f"{destination.name}: сохранены локальные инструкции")
                return
    destination.parent.mkdir(parents=True, exist_ok=True)
    mode = destination.stat().st_mode & 0o777 if destination.exists() else 0o600
    with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as tmp:
        name = Path(tmp.name)
        tmp.write(updated)
    try:
        os.chmod(name, mode)
        os.replace(name, destination)
    finally:
        if name.exists():
            name.unlink()
    print(f"{destination.name}: инструкции установлены")


if __name__ == "__main__":
    config, agent_os = map(Path, sys.argv[1:])
    deployed = config / ".vosmenog-deployed"
    revision = deployed.read_text().strip() if deployed.is_file() else ""
    if not re.fullmatch("[0-9a-f]{40}", revision):
        revision = ""
    install("global-AGENTS.md", config / "AGENTS.md", revision)
    install("persona_vosya.md", agent_os / "persona_vosya.md", revision)
    install("agents/Vosmenog.md", config / "agents/Vosmenog.md", revision)
